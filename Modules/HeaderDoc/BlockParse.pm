#! /usr/bin/perl -w
#
# Module name: BlockParse
# Synopsis: Block parser code
#
# Author: David Gatwood (dgatwood@apple.com)
# Last Updated: $Date: 2004/06/12 05:50:24 $
# 
# Copyright (c) 1999-2004 Apple Computer, Inc.  All rights reserved.
#
# @APPLE_LICENSE_HEADER_START@
#
# This file contains Original Code and/or Modifications of Original Code
# as defined in and that are subject to the Apple Public Source License
# Version 2.0 (the 'License'). You may not use this file except in
# compliance with the License. Please obtain a copy of the License at
# http://www.opensource.apple.com/apsl/ and read it before using this
# file.
# 
# The Original Code and all software distributed under the License are
# distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
# EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
# INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
# Please see the License for the specific language governing rights and
# limitations under the License.
#
# @APPLE_LICENSE_HEADER_END@
#
######################################################################
package HeaderDoc::BlockParse;

BEGIN {
	foreach (qw(Mac::Files)) {
	    $MOD_AVAIL{$_} = eval "use $_; 1";
    }
}

use Exporter;
foreach (qw(Mac::Files Mac::MoreFiles)) {
    eval "use $_";
}

$VERSION = 1.02;
@ISA = qw(Exporter);
@EXPORT = qw(blockParse nspaces);

use HeaderDoc::Utilities qw(findRelativePath safeName getAPINameAndDisc convertCharsForFileMaker printArray printHash quote parseTokens isKeyword);

use strict;
use vars qw($VERSION @ISA);
$VERSION = '1.20';

# /*!
#    This is a trivial function that returns a look at the top of a stack.
#    This seems like it should be part of the language.  If there is an
#    equivalent, this should be dropped.
# */
sub peek
{
	my $ref = shift;
	my @stack = @{$ref};
	my $tos = pop(@stack);
	push(@stack, $tos);

	return $tos;
}

# /*!
#    This is a variant of peek that returns the right token to match
#    the left token at the top of a brace stack.
#  */
sub peekmatch
{
	my $ref = shift;
	my $filename = shift;
	my $linenum = shift;
	my @stack = @{$ref};
	my $tos = pop(@stack);
	push(@stack, $tos);

	SWITCH: {
	    ($tos eq "{") && do {
			return "}";
		};
	    ($tos eq "#") && do {
			return "#";
		};
	    ($tos eq "(") && do {
			return ")";
		};
	    ($tos eq "/") && do {
			return "/";
		};
	    ($tos eq "'") && do {
			return "'";
		};
	    ($tos eq "\"") && do {
			return "\"";
		};
	    ($tos eq "`") && do {
			return "`";
		};
	    ($tos eq "<") && do {
			return ">";
		};
	    ($tos eq "[") && do {
			return "]";
		};
	    {
		# default case
		warn "$filename:$linenum:Unknown regexp delimiter \"$tos\".  Please file a bug.\n";
		return $tos;
	    };
	}
}

# /*! The blockParse function is the core of HeaderDoc's parse engine.
#     @param filename the filename being parser.
#     @param fileoffset the line number where the current block begins.  The line number printed is (fileoffset + inputCounter).
#     @param inputLinesRef a reference to an array of code lines.
#     @param inputCounter the offset within the array.  This is added to fileoffset when printing the line number.
#     @param argparse disable warnings when parsing arguments to avoid seeing them twice.
#     @param ignoreref a reference to a hash of tokens to ignore on all headers.
#     @param perheaderignoreref a reference to a hash of tokens, generated from @ignore headerdoc comments.
#     @param keywordhashref a reference to a hash of keywords.
#     @param case_sensitive boolean: controls whether keywords should be processed in a case-sensitive fashion.
#     @result Returns ($inputCounter, $declaration, $typelist, $namelist, $posstypes, $value, \@pplStack, $returntype, $privateDeclaration, $treeTop, $simpleTDcontents, $availability).
# */
sub blockParse
{
    my $filename = shift;
    my $fileoffset = shift;
    my $inputLinesRef = shift;
    my $inputCounter = shift;
    my $argparse = shift;
    my $ignoreref = shift;
    my $perheaderignoreref = shift;
    my $keywordhashref = shift;
    my $case_sensitive = shift;

    # Initialize stuff
    my @inputLines = @{$inputLinesRef};
    my $declaration = "";
    my $publicDeclaration = "";

    # Debugging switches
    my $localDebug   = 0;
    my $listDebug    = 0;
    my $parseDebug   = 0;
    my $sodDebug     = 0;
    my $valueDebug   = 0;
    my $parmDebug    = 0;
    my $cbnDebug     = 0;
    my $macroDebug   = 0;
    my $apDebug      = 0;
    my $tsDebug      = 0;
    my $treeDebug    = 0;
    my $ilcDebug     = 0;
    my $regexpDebug  = 0;

    # State variables (part 1 of 3)
    my $typestring = "";
    my $continue = 1; # set low when we're done.
    my $parsedParamParse = 0; # set high when current token is part of param.
    my @parsedParamList = (); # currently active parsed parameter list.
    my @pplStack = (); # stack of parsed parameter lists.  Used to handle
                       # fields and parameters in nested callbacks/structs.
    my @freezeStack = (); # copy of pplStack when frozen.
    my $stackFrozen = 0; # set to prevent fake parsed params with inline funcs
    my $lang = $HeaderDoc::lang;
    my $perl_or_shell = 0;
    my $sublang = $HeaderDoc::sublang;
    my $callback_typedef_and_name_on_one_line = 1; # deprecated
    my $returntype = "";
    my $freezereturn = 0; # set to prevent fake return types with inline funcs
    my $treeNest = 0;   # 1: nest future content under this node.
                        # 2: used if you want to nest, but have already
                        # inserted the contents of the node.
    my $treepart = "";  # There are some cases where you want to drop a token
                        # for formatting, but keep it in the parse tree.
                        # In that case, treepart contains the original token,
                        # while part generally contains a space.
    my $availability = ""; # holds availability string if we find an av macro.
    my $seenTilde = 0;  # set to 1 for C++ destructor.

    if ($argparse && $tsDebug) { $tsDebug = 0; }

    # Configure the parse tree output.
    my $treeTop = HeaderDoc::ParseTree->new(); # top of parse tree.
    my $treeCur = $treeTop;   # current position in parse tree
    my $treeSkip = 0;         # set to 1 if "part" should be dropped in tree.
    my $treePopTwo = 0;       # set to 1 for tokens that nest, but have no
                              # explicit ending token ([+-:]).
    my $treePopOnNewLine = 0; # set to 1 for single-line comments, macros.
    my @treeStack = ();       # stack of parse trees.  Used for popping
                              # our way up the tree to simplify tree structure.

    # The argparse switch is a trigger....
    if ($argparse && $apDebug) { 
	$localDebug   = 1;
	$listDebug    = 1;
	$parseDebug   = 1;
	$sodDebug     = 1;
	$valueDebug   = 1;
	$parmDebug    = 1;
	$cbnDebug     = 1;
	$macroDebug   = 1;
	# $apDebug      = 1;
	$tsDebug      = 1;
	$treeDebug    = 1;
	$ilcDebug     = 1;
	$regexpDebug  = 1;
    }
    if ($argparse && ($localDebug || $apDebug)) {
	print "ARGPARSE MODE!\n";
	print "IPC: $inputCounter\nNLINES: ".$#inputLines."\n";
    }

# warn("in BlockParse\n");

    # State variables (part 2 of 3)
    my $inComment = 0;
    my $inInlineComment = 0;
    my $inString = 0;
    my $inChar = 0;
    my $inTemplate = 0;
    my @braceStack = ();
    my $inOperator = 0;
    my $inPrivateParamTypes = 0;  # after a colon in a C++ function declaration.
    my $onlyComments = 1;         # set to 0 to avoid switching to macro parse.
                                  # mode after we have seen a code token.
    my $inMacro = 0;
    my $inMacroLine = 0;          # for handling macros in middle of data types.
    my $seenMacroPart = 0;        # used to control dropping of macro body.
    my $macroNoTrunc = 1;         # used to avoid truncating body of macros
                                  # that don't begin with parenthesis or brace.
    my $inBrackets = 0;           # square brackets ([]).
    my $inPType = 0;              # in pascal types.
    my $inRegexp = 0;             # in perl regexp.
    my $inRegexpTrailer = 0;      # in the cruft at the end of a regexp.
    my $ppSkipOneToken = 0;       # Comments are always dropped from parsed
                                  # parameter lists.  However, inComment goes
                                  # to 0 on the end-of-comment character.
                                  # This prevents the end-of-comment character
                                  # itself from being added....

    my $regexppattern = "";       # optional characters at start of regexp
    my $singleregexppattern = ""; # members of regexppattern that take only
                                  # one argument instead of two.
    my $regexpcharpattern = "";   # legal chars to start a regexp.
    my @regexpStack = ();         # stack of RE tokens (since some can nest).

    # Get the parse tokens from Utilities.pm.
    my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
	$soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
	$typedefname, $varname, $constname, $structisbrace, $macronameref)
		= parseTokens($lang, $sublang);

    # Set up regexp patterns for perl, variable for perl or shell.
    if ($lang eq "perl" || $lang eq "shell") {
	$perl_or_shell = 1;
	if ($lang eq "perl") {
		$regexpcharpattern = '\\{|\\#\\(|\\/|\\\'|\\"|\\<|\\[|\\`';
		$regexppattern = "qq|qr|qx|qw|q|m|s|tr|y";
		$singleregexppattern = "qq|qr|qx|qw|q|m";
	}
    }

    my $pascal = 0;
    if ($lang eq "pascal") { $pascal = 1; }

    # State variables (part 3 of 3)
    my $lastsymbol = "";          # Name of the last token, wiped by braces,
                                  # parens, etc.  This is not what you are
                                  # looking for.  It is used mostly for
                                  # handling names of typedefs.

    my $name = "";                # Name of a basic data type.
    my $callbackNamePending = 0;  # 1 if callback name could be here.  This is
                                  # only used for typedef'ed callbacks.  All
                                  # other callbacks get handled by the parameter
                                  # parsing code.  (If we get a second set of
                                  # parsed parameters for a function, the first
                                  # one becomes the callback name.)
    my $callbackName = "";        # Name of this callback.
    my $callbackIsTypedef = 0;    # 1 if the callback is wrapped in a typedef---
                                  # sets priority order of type matching (up
                                  # one level in headerdoc2HTML.pl).

    my $namePending = 0;          # 1 if name of func/variable is coming up.
    my $basetype = "";            # The main name for this data type.
    my $posstypes = "";           # List of type names for this data type.
    my $posstypesPending = 1;     # If this token could be one of the
                                  # type names of a typedef/struct/union/*
                                  # declaration, this should be 1.
    my $sodtype = "";             # 'start of declaration' type.
    my $sodname = "";             # 'start of declaration' name.
    my $sodclass = "";            # 'start of declaration' "class".  These
                                  # bits allow us keep track of functions and
                                  # callbacks, mostly, but not the name of a
                                  # callback.

    my $simpleTypedef = 0;        # High if it's a typedef w/o braces.
    my $simpleTDcontents = "";    # Guts of a one-line typedef.  Don't ask.
    my $seenBraces = 0;           # Goes high after initial brace for inline
                                  # functions and macros -only-.  We
                                  # essentially stop parsing at this point.
    my $kr_c_function = 0;        # Goes high if we see a K&R C declaration.
    my $kr_c_name = "";           # The name of a K&R function (which would
                                  # otherwise get lost).

    my $lastchar = "";            # Ends with the last token, but may be longer.
    my $lastnspart = "";          # The last non-whitespace token.
    my $lasttoken = "";           # The last token seen (though [\n\r] may be
                                  # replaced by a space in some cases.
    my $startOfDec = 1;           # Are we at the start of a declaration?
    my $prespace = 0;             # Used for indentation (deprecated).
    my $prespaceadjust = 0;       # Indentation is now handled by the parse
                                  # tree (colorizer) code.
    my $scratch = "";             # Scratch space.
    my $curline = "";             # The current line.  This is pushed onto
                                  # the declaration at a newline and when we
                                  # enter/leave certain constructs.  This is
                                  # deprecated in favor of the parse tree.
    my $curstring = "";           # The string we're currently processing.
    my $continuation = 0;         # An obscure spacing workaround.  Deprecated.
    my $forcenobreak = 0;         # An obscure spacing workaround.  Deprecated.
    my $occmethod = 0;            # 1 if we're in an ObjC method.
    my $occspace = 0;             # An obscure spacing workaround.  Deprecated.
    my $occmethodname = "";       # The name of an objective C method (which
                                  # gets augmented to be this:that:theother).
    my $preTemplateSymbol = "";   # The last symbol prior to the start of a
                                  # C++ template.  Used to determine whether
                                  # the type returned should be a function or
                                  # a function template.
    my $preEqualsSymbol = "";     # Used to get the name of a variable that
                                  # is followed by an equals sign.
    my $valuepending = 0;         # True if a value is pending, used to
                                  # return the right value.
    my $value = "";               # The current value.
    my $parsedParam = "";         # The current parameter being parsed.
    my $postPossNL = 0;           # Used to force certain newlines to be added
                                  # to the parse tree (to end macros, etc.)

    # Loop unti the end of file or until we've found a declaration,
    # processing one line at a time.
    my $nlines = $#inputLines;
    while ($continue && ($inputCounter <= $nlines)) {
	my $line = $inputLines[$inputCounter++];
	my @parts = ();

	$line =~ s/^\s*//go;
	$line =~ s/\s*$//go;
	# $scratch = nspaces($prespace);
	# $line = "$scratch$line\n";
	# $curline .= $scratch;
	$line .= "\n";

	# The tokenizer
	if ($lang eq "perl" || $lang eq "shell") {
	    @parts = split(/("|'|\#|\{|\}|\(|\)|\s|;|\\|\W)/, $line);
	} else {
	    @parts = split(/("|'|\/\/|\/\*|\*\/|::|==|<=|>=|!=|\<\<|\>\>|\{|\}|\(|\)|\s|;|\\|\W)/, $line);
	}

	$inInlineComment = 0;
	print "inInlineComment -> 0\n" if ($ilcDebug);

        # warn("line $inputCounter\n");

if ($localDebug) {foreach my $partlist (@parts) {print "PARTLIST: $partlist\n"; }}

	# This block of code needs a bit of explanation, I think.
	# We need to be able to see the token that follows the one we
	# are currently processing.  To do this, we actually keep track
	# of the current token, and the previous token, but name then
	# $nextpart and $part.  We do processing on $part, which gets
	# assigned the value from $nextpart at the end of the loop.
	#
	# To avoid losing the last part of the declaration (or needing
	# to unroll an extra copy of the entire loop code) we push a
	# bogus entry onto the end of the stack, which never gets
	# used (other than as a bogus "next part") because we only
	# process the value in $part.
	#
	# To avoid problems, make sure that you don't ever have a regexp
	# that would match against this bogus token.
	#
	push(@parts, "BOGUSBOGUSBOGUSBOGUSBOGUS");
	my $part = "";
	foreach my $nextpart (@parts) {
	    $treeSkip = 0;
	    $treePopTwo = 0;
	    # $treePopOnNewLine = 0;

	    # The current token is now in "part", and the literal next
	    # token in "nextpart".  We can't just work with this as-is,
	    # though, because you can have multiple spaces, null
	    # tokens when two of the tokens in the split list occur
	    # consecutively, etc.

	    print "MYPART: $part\n" if ($localDebug);

	    $forcenobreak = 0;
	    if ($nextpart eq "\r") { $nextpart = "\n"; }
	    if ($localDebug && $nextpart eq "\n") { print "NEXTPART IS NEWLINE!\n"; }
	    if ($localDebug && $part eq "\n") { print "PART IS NEWLINE!\n"; }
	    if ($nextpart ne "\n" && $nextpart =~ /\s/o) {
		# Replace tabs with spaces.
		$nextpart = " ";
	    }
	    if ($part ne "\n" && $part =~ /\s/o && $nextpart ne "\n" &&
		$nextpart =~ /\s/o) {
			# we're a space followed by a space.  Drop ourselves.
			next;
	    }
	    print "PART IS \"$part\"\n" if ($localDebug);
	    print "CURLINE IS \"$curline\"\n" if ($localDebug);

	    if (!length($nextpart)) {
		print "SKIP NP\n" if ($localDebug);
		next;
	    }
	    if (!length($part)) {
		print "SKIP PART\n" if ($localDebug);
		$part = $nextpart;
		next;
	    }

	    # If we get here, we aren't skipping a null or whitespace token.
	    # Let's print a bunch of noise if debugging is enabled.

	    if ($parseDebug) {
		print "PART: $part, type: $typestring, inComment: $inComment, inInlineComment: $inInlineComment, inChar: $inChar.\n" if ($localDebug);
		print "PART: bracecount: " . scalar(@braceStack) . "\n";
		print "PART: inString: $inString, callbackNamePending: $callbackNamePending, namePending: $namePending, lastsymbol: $lastsymbol, lasttoken: $lasttoken, lastchar: $lastchar, SOL: $startOfDec\n" if ($localDebug);
		print "PART: sodclass: $sodclass sodname: $sodname\n";
		print "PART: posstypes: $posstypes\n";
		print "PART: seenBraces: $seenBraces inRegexp: $inRegexp\n";
		print "PART: seenTilde: $seenTilde\n";
		print "PART: CBN: $callbackName\n";
		print "PART: regexpStack is:";
		foreach my $token (@regexpStack) { print " $token"; }
		print "\n";
		print "PART: npplStack: ".scalar(@pplStack)." nparsedParamList: ".scalar(@parsedParamList)." nfreezeStack: ".scalar(@freezeStack)." frozen: $stackFrozen\n";
		print "PART: inMacro: $inMacro treePopOnNewLine: $treePopOnNewLine\n";
		print "length(declaration) = " . length($declaration) ."; length(curline) = " . length($curline) . "\n";
	    } elsif ($tsDebug || $treeDebug) {
		print "BPPART: $part\n";
	    }

	    # The ignore function returns either null, an empty string,
	    # or a string that gives the text equivalent of an availability
            # macro.  If the token is non-null and the length is non-zero,
	    # it's an availability macro, so blow it in as if the comment
	    # contained an @availability tag.
	    # 
	    my $tempavail = ignore($part, $ignoreref, $perheaderignoreref);
	    # printf("PART: $part TEMPAVAIL: $tempavail\n");
	    if ($tempavail && ($tempavail ne "1")) {
		$availability = $tempavail;
	    }

	    # Here be the parser.  Abandon all hope, ye who enter here.
	    $treepart = "";
	    SWITCH: {

		# Macro handlers

		(($inMacro == 1) && ($part eq "define")) && do{
			# define may be a multi-line macro
			$inMacro = 3;
			$sodname = "";
			my $pound = $treeCur->token();
			if ($pound eq "$sopreproc") {
				$treeNest = 2;
				$treePopOnNewLine = 2;
				$pound .= $part;
				$treeCur->token($pound);
			}
			last SWITCH;
		};
		(($inMacro == 1) && ($part =~ /(if|ifdef|ifndef|endif|else|pragma|import|include)/o)) && do {
			# these are all single-line macros
			$inMacro = 4;
			$sodname = "";
			my $pound = $treeCur->token();
			if ($pound eq "$sopreproc") {
				$treeNest = 2;
				$treePopOnNewLine = 1;
				$pound .= $part;
				$treeCur->token($pound);
				if ($part eq "endif") {
					# the rest of the line is not part of the macro
					$treeNest = 0;
					$treeSkip = 1;
				}
			}
			last SWITCH;
		};
		(($inMacroLine == 1) && ($part =~ /(if|ifdef|ifndef|endif|else|pragma|import|include|define)/o)) && do {
			my $pound = $treeCur->token();
			if ($pound eq "$sopreproc") {
				$pound .= $part;
				$treeCur->token($pound);
				if ($part =~ /define/o) {
					$treeNest = 2;
					$treePopOnNewLine = 2;
				} elsif ($part eq "endif") {
					# the rest of the line is not part of the macro
					$treeNest = 0;
					$treeSkip = 1;
				} else {
					$treeNest = 2;
					$treePopOnNewLine = 1;
				}
			}
			last SWITCH;
		};
		($inMacro == 1) && do {
			# error case.
			$inMacro = 2;
			last SWITCH;
		};
		($inMacro > 1 && $part ne "//") && do {
			print "PART: $part\n" if ($macroDebug);
			if ($seenMacroPart && $HeaderDoc::truncate_inline) {
				if (!scalar(@braceStack)) {
					if ($part =~ /\s/o && $macroNoTrunc == 1) {
						$macroNoTrunc = 0;
					} elsif ($part =~ /[\{\(]/o) {
						if (!$macroNoTrunc) {
							$seenBraces = 1;
						}
					} else {
						$macroNoTrunc = 2;
					}
				}
			}
			if ($part =~ /[\{\(]/o) {
				push(@braceStack, $part);
				print "PUSH\n" if ($macroDebug);
			} elsif ($part =~ /[\}\)]/o) {
				if ($part ne peekmatch(\@braceStack, $filename, $inputCounter)) {
					warn("$filename:$inputCounter:Initial braces in macro name do not match.\nWe may have a problem.\n");
				}
				pop(@braceStack);
				print "POP\n" if ($macroDebug);
			}

			if ($part =~ /\S/o) {
				$seenMacroPart = 1;
				$lastsymbol = $part;
				if (($sodname eq "") && ($inMacro == 3)) {
					print "DEFINE NAME IS $part\n" if ($macroDebug);
					$sodname = $part;
				}
			}
			$lastchar = $part;
			last SWITCH;
		};

		# Regular expression handlers

		(length($regexppattern) && $part =~ /^($regexppattern)$/ && !($inRegexp || $inRegexpTrailer || $inString || $inComment || $inInlineComment || $inChar)) && do {
			my $match = $1;
			print "REGEXP WITH PREFIX\n" if ($regexpDebug);
			if ($match =~ /^($singleregexppattern)$/) {
				# e.g. perl PATTERN?
				$inRegexp = 2;
			} else {
				$inRegexp = 4;
			}
			last SWITCH;
		}; # end regexppattern
		(($inRegexp || $lastsymbol eq "~") && (length($regexpcharpattern) && $part =~ /^($regexpcharpattern)$/ && (!scalar(@regexpStack) || $part eq peekmatch(\@regexpStack, $filename, $inputCounter)))) && do {
			print "REGEXP?\n" if ($regexpDebug);
			if (!$inRegexp) {
				$inRegexp = 2;
			}

			if ($lasttoken eq "\\") {
				# jump to next match.
				$lasttoken = $part;
				$lastsymbol = $part;
				next SWITCH;
			}
print "REGEXP POINT A\n" if ($regexpDebug);
			$lasttoken = $part;
			$lastsymbol = $part;

			if ($part eq "#" &&
			    ((scalar(@regexpStack) != 1) || 
			     (peekmatch(\@regexpStack, $filename, $inputCounter) ne "#"))) {
				if ($nextpart =~ /^\s/o) {
					# it's a comment.  jump to next match.
					next SWITCH;
				}
			}
print "REGEXP POINT B\n" if ($regexpDebug);

			if (!scalar(@regexpStack)) {
				push(@regexpStack, $part);
				$inRegexp--;
			} else {
				my $match = peekmatch(\@regexpStack, $filename, $inputCounter);
				my $tos = pop(@regexpStack);
				if (!scalar(@regexpStack) && ($match eq $part)) {
					$inRegexp--;
					if ($inRegexp == 2 && $tos eq "/") {
						# we don't double the slash in the
						# middle of a s/foo/bar/g style
						# expression.
						$inRegexp--;
					}
					if ($inRegexp) {
						push(@regexpStack, $tos);
					}
				} elsif (scalar(@regexpStack) == 1) {
					push(@regexpStack, $tos);
					if ($tos =~ /['"`]/o) {
						# these don't interpolate.
						next SWITCH;
					}
				} else {
					push(@regexpStack, $tos);
					if ($tos =~ /['"`]/o) {
						# these don't interpolate.
						next SWITCH;
					}
					push(@regexpStack, $part);
				}
			}
print "REGEXP POINT C\n" if ($regexpDebug);
			if (!$inRegexp) {
				$inRegexpTrailer = 2;
			}
			last SWITCH;
		}; # end regexpcharpattern

		# Start of preprocessor macros

		($part eq "$sopreproc") && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				if ($onlyComments) {
					print "inMacro -> 1\n" if ($macroDebug);
					$inMacro = 1;
					# $continue = 0;
		    			# print "continue -> 0 [1]\n" if ($localDebug || $macroDebug);
				} elsif ($curline =~ /^\s*$/o) {
					$inMacroLine = 1;
					print "IML\n" if ($localDebug);
				} elsif ($postPossNL) {
					print "PRE-IML \"$curline\"\n" if ($localDebug || $macroDebug);
					$treeCur = $treeCur->addSibling("\n", 0);
					bless($treeCur, "HeaderDoc::ParseTree");
					$inMacroLine = 1;
					$postPossNL = 0;
				}
			    }
			};

		# Start of token-delimited functions and procedures (e.g.
		# Pascal and PHP)

		($part eq "$sofunction" || $part eq "$soprocedure") && do {
				$sodclass = "function";
				print "K&R C FUNCTION FOUND [1].\n" if ($localDebug);
				$kr_c_function = 1;
				$typestring = "function";
				$startOfDec = 0;
				$namePending = 1;
				# if (!$seenBraces) { # TREEDONE
					# $treeNest = 1;
					# $treePopTwo++;
					# push(@treeStack, $treeCur);
					# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
					# bless($treeCur, "HeaderDoc::ParseTree");
				# }
				print "namePending -> 1 [1]\n" if ($parseDebug);
				last SWITCH;
			};

		# C++ destructor handler.

		($part =~ /\~/o && $lang eq "C" && $sublang eq "cpp") && do {
				print "TILDE\n" if ($localDebug);
				$seenTilde = 2;
				$lastchar = $part;
				$onlyComments = 0;
				# $name .= '~';
				last SWITCH;
			};

		# Objective-C method handler.

		($part =~ /[-+]/o && $declaration !~ /\S/o && $curline !~ /\S/o) && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				print "OCCMETHOD\n" if ($localDebug);
				# Objective C Method.
				$occmethod = 1;
				$lastchar = $part;
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				if (!$seenBraces) { # TREEDONE
				    $treeNest = 1;
				    $treePopTwo = 1;
				}
			    }
			    last SWITCH;
			};

		# Newline handler.

		($part =~ /[\n\r]/o) && do {
				$treepart = $part;
				if ($inRegexp) {
					warn "$filename:$inputCounter:multi-line regular expression\n";
				}
				print "NLCR\n" if ($tsDebug || $treeDebug || $localDebug);
				if ($lastchar !~ /[\,\;\{\(\)\}]/o && $nextpart !~ /[\{\}\(\)]/o) {
					if ($lastchar ne "*/" && $nextpart ne "/*") {
						if (!$inMacro && !$inMacroLine && !$treePopOnNewLine) {
							print "NL->SPC\n" if ($localDebug);
							$part = " ";
							print "LC: $lastchar\n" if ($localDebug);
							print "NP: $nextpart\n" if ($localDebug);
							$postPossNL = 2;
						} else {
							$inMacroLine = 0;
						}
					}
				}
				if ($treePopOnNewLine < 0) {
					# pop once for //, possibly again for macro
					$treePopOnNewLine = 0 - $treePopOnNewLine;
					$treeCur = $treeCur->addSibling($treepart, 0);
					bless($treeCur, "HeaderDoc::ParseTree");
					# push(@treeStack, $treeCur);
					$treeSkip = 1;
					$treeCur = pop(@treeStack);
					print "TSPOP [1]\n" if ($tsDebug || $treeDebug);
					if (!$treeCur) {
						$treeCur = $treeTop;
						warn "$filename:$inputCounter:Attempted to pop off top of tree\n";
					}
					bless($treeCur, "HeaderDoc::ParseTree");
				}
				if ($treePopOnNewLine == 1 || ($treePopOnNewLine && $lastsymbol ne "\\")) {
					$treeCur = $treeCur->addSibling($treepart, 0);
					bless($treeCur, "HeaderDoc::ParseTree");
					# push(@treeStack, $treeCur);
					$treeSkip = 1;
					$treeCur = pop(@treeStack);
					print "TSPOP [1a]\n" if ($tsDebug || $treeDebug);
					if (!$treeCur) {
						$treeCur = $treeTop;
						warn "$filename:$inputCounter:Attempted to pop off top of tree\n";
					}
					bless($treeCur, "HeaderDoc::ParseTree");
					$treePopOnNewLine = 0;
				}
				next SWITCH;
			};

		# C++ template handlers

		($part eq $sotemplate && !$seenBraces) && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				print "inTemplate -> 1\n" if ($localDebug);
	print "SBS: " . scalar(@braceStack) . ".\n" if ($localDebug);
				$inTemplate = 1;
				if (!scalar(@braceStack)) {
					$preTemplateSymbol = $lastsymbol;
				}
				$lastsymbol = "";
				$lastchar = $part;
				$onlyComments = 0;
				push(@braceStack, $part); pbs(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeNest = 1;
					# push(@treeStack, $treeCur);
					# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
					# bless($treeCur, "HeaderDoc::ParseTree");
				}
				print "onlyComments -> 0\n" if ($macroDebug);
			    }
			    last SWITCH;
			};
		($part eq $eotemplate && !$seenBraces) && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar) && (!scalar(@braceStack) || $inTemplate)) {
				if ($inTemplate)  {
					print "inTemplate -> 0\n" if ($localDebug);
					$inTemplate = 0;
					$lastsymbol = "";
					$lastchar = $part;
					$curline .= " ";
					$onlyComments = 0;
					print "onlyComments -> 0\n" if ($macroDebug);
				}
				my $top = pop(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeCur->addSibling($part, 0); $treeSkip = 1;
					$treeCur = pop(@treeStack) || $treeTop;
					print "TSPOP [2]\n" if ($tsDebug || $treeDebug);
					bless($treeCur, "HeaderDoc::ParseTree");
				}
				if ($top ne "$sotemplate") {
					warn("$filename:$inputCounter:Template (angle) brackets do not match.\nWe may have a problem.\n");
				}
			    }
			    last SWITCH;
			};

		# C++ copy constructor handler.  For example:
		# 
		# char *class(void *a, void *b) :
		#       class(pri_type, pri_type);
		#

		($part eq ":") && do {
			if (!($inString || $inComment || $inInlineComment || $inChar)) {
				if ($occmethod) {
				    $name = $lastsymbol;
				    $occmethodname .= "$lastsymbol:";
				    # Start doing line splitting here.
				    # Also, capture the method's name.
				    if ($occmethod == 1) {
					$occmethod = 2;
					if (!$prespace) { $prespaceadjust = 4; }
					$onlyComments = 0;
					print "onlyComments -> 0\n" if ($macroDebug);
				    }
				} else {
				    if ($lang eq "C" && $sublang eq "cpp") {
					if (!scalar(@braceStack) && $sodclass eq "function") {
					    $inPrivateParamTypes = 1;
					    $declaration .= "$curline";
					    $publicDeclaration = $declaration;
					    $declaration = "";
					} else {
					    next SWITCH;
					}
					if (!$stackFrozen) {
						if (scalar(@parsedParamList)) {
						    foreach my $node (@parsedParamList) {
							$node =~ s/^\s*//so;
							$node =~ s/\s*$//so;
							if (length($node)) {
								push(@pplStack, $node)
							}
						    }
						    @parsedParamList = ();
						    print "parsedParamList pushed\n" if ($parmDebug);
						}
						# print "SEOPPLS\n";
						# for my $item (@pplStack) {
							# print "PPLS: $item\n";
						# }
						# print "OEOPPLS\n";
						@freezeStack = @pplStack;
						$stackFrozen = 1;
					}
				    } else {
					next SWITCH;
				    }
				}
			    if (!$seenBraces) { # TREEDONE
				    # $treeCur->addSibling($part, 0); $treeSkip = 1;
				    $treeNest = 1;
				    $treePopTwo = 1;
				    # $treeCur = pop(@treeStack) || $treeTop;
				    # bless($treeCur, "HeaderDoc::ParseTree");
			    }
			    last SWITCH;
			    }
			};

		# Non-newline, non-carriage-return whitespace handler.

		($part =~ /\s/o) && do {
				# just add white space silently.
				# if ($part eq "\n") { $lastsymbol = ""; };
				$lastchar = $part;
				last SWITCH;
		};

		# backslash handler (largely useful for macros, strings).

		($part =~ /\\/o) && do { $lastsymbol = $part; $lastchar = $part; };

		# quote and bracket handlers.

		($part eq "\"") && do {
				print "dquo\n" if ($localDebug);

				# print "QUOTEDEBUG: CURSTRING IS '$curstring'\n";
				# print "QUOTEDEBUG: CURLINE IS '$curline'\n";
				if (!($inComment || $inInlineComment || $inChar)) {
					$onlyComments = 0;
					print "onlyComments -> 0\n" if ($macroDebug);
					print "LASTTOKEN: $lasttoken\nCS: $curstring\n" if ($localDebug);
					if (($lasttoken !~ /\\$/o) && ($curstring !~ /\\$/o)) {
						if (!$inString) {
						    if (!$seenBraces) { # TREEDONE
							$treeNest = 1;
							# push(@treeStack, $treeCur);
							# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
							# bless($treeCur, "HeaderDoc::ParseTree");
						    }
						} else {
						    if (!$seenBraces) { # TREEDONE
							$treeCur->addSibling($part, 0); $treeSkip = 1;
							$treeCur = pop(@treeStack) || $treeTop;
							print "TSPOP [3]\n" if ($tsDebug || $treeDebug);
							bless($treeCur, "HeaderDoc::ParseTree");
						    }
						}
						$inString = (1-$inString);
					}
				}
				$lastchar = $part;
				$lastsymbol = "";

				last SWITCH;
			};
		($part eq "[") && do {
				print "lbracket\n" if ($localDebug);

				if (!($inComment || $inInlineComment || $inString)) {
					$onlyComments = 0;
					print "onlyComments -> 0\n" if ($macroDebug);
				}
				push(@braceStack, $part); pbs(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeNest = 1;
					# push(@treeStack, $treeCur);
					# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
					# bless($treeCur, "HeaderDoc::ParseTree");
				}
				$curline = spacefix($curline, $part, $lastchar);
				$lastsymbol = "";
				$lastchar = $part;

				last SWITCH;
			};
		($part eq "]") && do {
				print "rbracket\n" if ($localDebug);

				if (!($inComment || $inInlineComment || $inString)) {
					$onlyComments = 0;
					print "onlyComments -> 0\n" if ($macroDebug);
				}
				my $top = pop(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeCur->addSibling($part, 0); $treeSkip = 1;
					$treeCur = pop(@treeStack) || $treeTop;
					print "TSPOP [4]\n" if ($tsDebug || $treeDebug);
					bless($treeCur, "HeaderDoc::ParseTree");
				}
				if ($top ne "[") {
					warn("$filename:$inputCounter:Square brackets do not match.\nWe may have a problem.\n");
					warn("Declaration to date: $declaration$curline\n");
				}
				pbs(@braceStack);
				$curline = spacefix($curline, $part, $lastchar);
				$lastsymbol = "";
				$lastchar = $part;

				last SWITCH;
			};
		($part eq "'") && do {
				print "squo\n" if ($localDebug);

				if (!($inComment || $inInlineComment || $inString)) {
					if ($lastchar ne "\\") {
						$onlyComments = 0;
						print "onlyComments -> 0\n" if ($macroDebug);
						if (!$inChar) {
						    if (!$seenBraces) { # TREEDONE
							$treeNest = 1;
							# push(@treeStack, $treeCur);
							# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
							# bless($treeCur, "HeaderDoc::ParseTree");
						    }
						} else {
						    if (!$seenBraces) { # TREEDONE
							$treeCur->addSibling($part, 0); $treeSkip = 1;
							$treeCur = pop(@treeStack) || $treeTop;
							print "TSPOP [5]\n" if ($tsDebug || $treeDebug);
							bless($treeCur, "HeaderDoc::ParseTree");
						    }
						}
						$inChar = !$inChar;
					}
					if ($lastchar =~ /\=$/o) {
						$curline .= " ";
					}
				}
				$lastsymbol = "";
				$lastchar = $part;

				last SWITCH;
			};

		# Inline comment (two slashes in c++, hash in perl/shell)
		# handler.

		($part eq $ilc && ($lang ne "perl" || $lasttoken ne "\$")) && do {
				print "ILC\n" if ($localDebug || $ilcDebug);

				if (!($inComment || $inChar || $inString || $inRegexp)) {
					$inInlineComment = 1;
					print "inInlineComment -> 1\n" if ($ilcDebug);
					$curline = spacefix($curline, $part, $lastchar, $soc, $eoc, $ilc);
					if (!$seenBraces) { # TREEDONE
						$treeNest = 1;

						if (!$treePopOnNewLine) {
							$treePopOnNewLine = 1;
						} else {
							$treePopOnNewLine = 0 - $treePopOnNewLine;
						}
						print "treePopOnNewLine -> $treePopOnNewLine\n" if ($ilcDebug);

						# $treeCur->addSibling($part, 0); $treeSkip = 1;
						# $treePopOnNewLine = 1;
						# $treeCur = pop(@treeStack) || $treeTop;
						# bless($treeCur, "HeaderDoc::ParseTree");
					}
				} elsif ($inComment) {
					my $linenum = $inputCounter + $fileoffset;
					if (!$argparse) {
						# We've already seen these.
						warn("$filename:$linenum:Nested comment found [1].  Ignoring.\n");
					}
					# warn("XX $argparse XX $inputCounter XX $fileoffset XX\n");
				}
				$lastsymbol = "";
				$lastchar = $part;

				last SWITCH;
			};

		# Standard comment handlers: soc = start of comment,
		# eoc = end of comment.

		($part eq $soc) && do {
				print "SOC\n" if ($localDebug);

				if (!($inComment || $inInlineComment || $inChar || $inString)) {
					$inComment = 1; 
					$curline = spacefix($curline, $part, $lastchar);
					if (!$seenBraces) {
						$treeNest = 1;
						# print "TSPUSH\n" if ($tsDebug || $treeDebug);
						# push(@treeStack, $treeCur);
						# $treeCur = $treeCur->addChild("", 0);
						# bless($treeCur, "HeaderDoc::ParseTree");
					}
				} elsif ($inComment) {
					my $linenum = $inputCounter + $fileoffset;
					warn("$filename:$linenum:Nested comment found [2].  Ignoring.\n");
				}
				$lastsymbol = "";
				$lastchar = $part;

				last SWITCH;
			};
		($part eq $eoc) && do {
				print "EOC\n" if ($localDebug);

				if ($inComment && !($inInlineComment || $inChar || $inString)) {
					$inComment = 0;
					$curline = spacefix($curline, $part, $lastchar);
					$ppSkipOneToken = 1;
					if (!$seenBraces) {
                                        	$treeCur->addSibling($part, 0); $treeSkip = 1;
                                        	$treeCur = pop(@treeStack) || $treeTop;
                                        	print "TSPOP [6]\n" if ($tsDebug || $treeDebug);
                                        	bless($treeCur, "HeaderDoc::ParseTree");
					}
}
				elsif (!$inComment) {
					my $linenum = $inputCounter + $fileoffset;
					warn("$filename:$linenum:Unmatched close comment tag found.  Ignoring.\n");
				} elsif ($inInlineComment) {
					my $linenum = $inputCounter + $fileoffset;
					warn("$filename:$linenum:Nested comment found [3].  Ignoring.\n");
				}
				$lastsymbol = "";
				$lastchar = $part;

				last SWITCH;
			};

		# Parenthesis and brace handlers.

		($part eq "(") && do {
			    my @tempppl = undef;
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
			        if (!(scalar(@braceStack))) {
				    # start parameter parsing after this token
				    print "parsedParamParse -> 2\n" if ($parmDebug);
				    $parsedParamParse = 2;
				    print "parsedParamList wiped\n" if ($parmDebug);
				    @tempppl = @parsedParamList;
				    @parsedParamList = ();
				    $parsedParam = "";
			        }
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				if ($simpleTypedef) {
					$simpleTypedef = 0;
					$simpleTDcontents = "";
					$sodname = $lastsymbol;
					$sodclass = "function";
					$returntype = "$declaration$curline";
				}
				$posstypesPending = 0;
				if ($callbackNamePending == 2) {
					$callbackNamePending = 3;
					print "callbackNamePending -> 3\n" if ($localDebug || $cbnDebug);
				}
				print "lparen\n" if ($localDebug);

				push(@braceStack, $part); pbs(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeNest = 1;
					# push(@treeStack, $treeCur);
					# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
					# bless($treeCur, "HeaderDoc::ParseTree");
				}
				$curline = spacefix($curline, $part, $lastchar);

				print "LASTCHARCHECK: \"$lastchar\" \"$lastnspart\" \"$curline\".\n" if ($localDebug);
				if ($lastnspart eq ")") {  # || $curline =~ /\)\s*$/so
print "HERE: DEC IS $declaration\nENDDEC\nCURLINE IS $curline\nENDCURLINE\n" if ($localDebug);
				    # print "CALLBACKMAYBE: $callbackNamePending $sodclass ".scalar(@braceStack)."\n";
				    print "SBS: ".scalar(@braceStack)."\n" if ($localDebug);
				    if (!$callbackNamePending && ($sodclass eq "function") && (scalar(@braceStack) == 1)) { #  && $argparse
					# Guess it must be a callback anyway.
					my $temp = pop(@tempppl);
					$callbackName = $temp;
					$name = "";
					$sodclass = "";
					$sodname = "";
					print "CALLBACKHERE ($temp)!\n" if ($cbnDebug);
				    }
				    if ($declaration =~ /.*\n(.*?)\n$/so) {
					my $lastline = $1;
print "LL: $lastline\nLLDEC: $declaration" if ($localDebug);
					$declaration =~ s/(.*)\n(.*?)\n$/$1\n/so;
					$curline = "$lastline $curline";
					$curline =~ s/^\s*//so;
					$prespace -= 4;
					$prespaceadjust += 4;
					
					$forcenobreak = 1;
print "NEWDEC: $declaration\nNEWCURLINE: $curline\n" if ($localDebug);
				    } elsif (length($declaration) && $callback_typedef_and_name_on_one_line) {
print "SCARYCASE\n" if ($localDebug);
					$declaration =~ s/\n$//so;
					$curline = "$declaration $curline";
					$declaration = "";
					$prespace -= 4;
					$prespaceadjust += 4;
					
					$forcenobreak = 1;
				    }
				} else { print "OPARENLC: \"$lastchar\"\nCURLINE IS: \"$curline\"\n" if ($localDebug);}

				$lastsymbol = "";
				$lastchar = $part;

				if ($startOfDec == 2) {
					$sodclass = "function";
					$freezereturn = 1;
					$returntype =~ s/^\s*//so;
					$returntype =~ s/\s*$//so;
				}
				$startOfDec = 0;
				if ($curline !~ /\S/o) {
					# This is the first symbol on the line.
					# adjust immediately
					$prespace += 4;
					print "PS: $prespace immediate\n" if ($localDebug);
				} else {
					$prespaceadjust += 4;
					print "PSA: $prespaceadjust\n" if ($localDebug);
				}
			    }
			    print "OUTGOING CURLINE: \"$curline\"\n" if ($localDebug);
			    last SWITCH;
			};
		($part eq ")") && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
			        if (scalar(@braceStack) == 1) {
				    # stop parameter parsing
				    $parsedParamParse = 0;
				    print "parsedParamParse -> 0\n" if ($parmDebug);
				    $parsedParam =~ s/^\s*//so; # trim leading space
				    $parsedParam =~ s/\s*$//so; # trim trailing space

				    if ($parsedParam ne "void") {
					# ignore foo(void)
					push(@parsedParamList, $parsedParam);
					print "pushed $parsedParam into parsedParamList [1]\n" if ($parmDebug);
				    }
				    $parsedParam = "";
			        }
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				print "rparen\n" if ($localDebug);


				my $test = pop(@braceStack); pbs(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeCur->addSibling($part, 0); $treeSkip = 1;
					$treeCur = pop(@treeStack) || $treeTop;
					print "TSPOP [6a]\n" if ($tsDebug || $treeDebug);
					bless($treeCur, "HeaderDoc::ParseTree");
				}
				if (!($test eq "(")) {		# ) brace hack for vi
					warn("$filename:$inputCounter:Parentheses do not match.\nWe may have a problem.\n");
					warn("Declaration to date: $declaration$curline\n");
				}
				$curline = spacefix($curline, $part, $lastchar);
				$lastsymbol = "";
				$lastchar = $part;

				$startOfDec = 0;
				if ($curline !~ /\S/o) {
					# This is the first symbol on the line.
					# adjust immediately
					$prespace -= 4;
					print "PS: $prespace immediate\n" if ($localDebug);
				} else {
					$prespaceadjust -= 4;
					print "PSA: $prespaceadjust\n" if ($localDebug);
				}
			    }
			    last SWITCH;
			};
		($part eq "$lbrace") && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				if (scalar(@parsedParamList)) {
					foreach my $node (@parsedParamList) {
						$node =~ s/^\s*//so;
						$node =~ s/\s*$//so;
						if (length($node)) {
							push(@pplStack, $node)
						}
					}
					@parsedParamList = ();
					print "parsedParamList pushed\n" if ($parmDebug);
				}

				# start parameter parsing after this token
				print "parsedParamParse -> 2\n" if ($parmDebug);
				$parsedParamParse = 2;

				if ($sodclass eq "function" || $inOperator) {
					$seenBraces = 1;
					if (!$stackFrozen) {
						@freezeStack = @pplStack;
						$stackFrozen = 1;
					}
					@pplStack = ();
				}
				$posstypesPending = 0;
				$namePending = 0;
				$callbackNamePending = -1;
				$simpleTypedef = 0;
				$simpleTDcontents = "";
				print "callbackNamePending -> -1\n" if ($localDebug || $cbnDebug);
				print "lbrace\n" if ($localDebug);

				push(@braceStack, $part); pbs(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeNest = 1;
					# push(@treeStack, $treeCur);
					# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
					# bless($treeCur, "HeaderDoc::ParseTree");
				}
				$curline = spacefix($curline, $part, $lastchar);
				$lastsymbol = "";
				$lastchar = $part;

				$startOfDec = 0;
				if ($curline !~ /\S/o) {
					# This is the first symbol on the line.
					# adjust immediately
					$prespace += 4;
					print "PS: $prespace immediate\n" if ($localDebug);
				} else {
					$prespaceadjust += 4;
					print "PSA: $prespaceadjust\n" if ($localDebug);
				}
			    }
			    last SWITCH;
			};
		($part eq "$rbrace") && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				$onlyComments = 0;

				if (scalar(@braceStack) == 1) {
					# stop parameter parsing
					$parsedParamParse = 0;
					print "parsedParamParse -> 0\n" if ($parmDebug);
					$parsedParam =~ s/^\s*//so; # trim leading space
					$parsedParam =~ s/\s*$//so; # trim trailing space

					if (length($parsedParam)) {
						# ignore foo(void)
						push(@parsedParamList, $parsedParam);
						print "pushed $parsedParam into parsedParamList [1b]\n" if ($parmDebug);
					}
					$parsedParam = "";
				} else {
					# start parameter parsing after this token
					print "parsedParamParse -> 2\n" if ($parmDebug);
					$parsedParamParse = 2;
				}

				if (scalar(@parsedParamList)) {
					foreach my $node (@parsedParamList) {
						$node =~ s/^\s*//so;
						$node =~ s/\s*$//so;
						if (length($node)) {
							push(@pplStack, $node)
						}
					}
					@parsedParamList = ();
					print "parsedParamList pushed\n" if ($parmDebug);
				}

				print "onlyComments -> 0\n" if ($macroDebug);
				print "rbrace\n" if ($localDebug);

				my $test = pop(@braceStack); pbs(@braceStack);
				if (!$seenBraces) { # TREEDONE
					$treeCur->addSibling($part, 0); $treeSkip = 1;
					$treeCur = pop(@treeStack) || $treeTop;
					print "TSPOP [7]\n" if ($tsDebug || $treeDebug);
					bless($treeCur, "HeaderDoc::ParseTree");
				}
				if (!($test eq "$lbrace") && (!length($structname) || (!($test eq $structname) && $structisbrace))) {		# } brace hack for vi.
					warn("$filename:$inputCounter:Braces do not match.\nWe may have a problem.\n");
					warn("Declaration to date: $declaration$curline\n");
				}
				$curline = spacefix($curline, $part, $lastchar);
				$lastsymbol = "";
				$lastchar = $part;

				$startOfDec = 0;
				if ($curline !~ /\S/o) {
					# This is the first symbol on the line.
					# adjust immediately
					$prespace -= 4;
					print "PS: $prespace immediate\n" if ($localDebug);
				} else {
					$prespaceadjust -= 4;
					print "PSA: $prespaceadjust\n" if ($localDebug);
				}
			    }
			    last SWITCH;
			};

		# Typedef, struct, enum, and union handlers.

		($part eq $structname || $part =~ /^enum$/o || $part =~ /^union$/o) && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				if ($structisbrace) {
                                	if ($sodclass eq "function") {
                                        	$seenBraces = 1;
						if (!$stackFrozen) {
							@freezeStack = @pplStack;
							$stackFrozen = 1;
						}
						@pplStack = ();
                                	}
                                	$posstypesPending = 0;
                                	$callbackNamePending = -1;
                                	$simpleTypedef = 0;
					$simpleTDcontents = "";
                                	print "callbackNamePending -> -1\n" if ($localDebug || $cbnDebug);
                                	print "lbrace\n" if ($localDebug);

                                	push(@braceStack, $part); pbs(@braceStack);
					if (!$seenBraces) { # TREEDONE
						$treeNest = 1;
						# push(@treeStack, $treeCur);
						# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
						# bless($treeCur, "HeaderDoc::ParseTree");
					}
                                	$curline = spacefix($curline, $part, $lastchar);
                                	$lastsymbol = "";
                                	$lastchar = $part;

                                	$startOfDec = 0;
                                	if ($curline !~ /\S/o) {
                                        	# This is the first symbol on the line.
                                        	# adjust immediately
                                        	$prespace += 4;
                                        	print "PS: $prespace immediate\n" if ($localDebug);
                                	} else {
                                        	$prespaceadjust += 4;
                                        	print "PSA: $prespaceadjust\n" if ($localDebug);
                                	}
				} else {
					if (!$simpleTypedef) {
						$simpleTypedef = 2;
					}
					# if (!$seenBraces) { # TREEDONE
						# $treePopTwo++;
						# $treeNest = 1;
						# push(@treeStack, $treeCur);
						# $treeCur = $treeCur->addChild($part, 0); $treeSkip = 1;
						# bless($treeCur, "HeaderDoc::ParseTree");
					# }
				}
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				$continuation = 1;
				# $simpleTypedef = 0;
				if ($basetype eq "") { $basetype = $part; }
				# fall through to default case when we're done.
				if (!($inComment || $inInlineComment || $inString || $inChar)) {
					$namePending = 2;
					print "namePending -> 2 [2]\n" if ($parseDebug);
					if ($posstypesPending) { $posstypes .=" $part"; }
				}
				if ($sodclass eq "") {
					$startOfDec = 0; $sodname = "";
print "sodname cleared (seu)\n" if ($sodDebug);
				}
				$lastchar = $part;
			    }; # end if
			}; # end do
		($part =~ /^$typedefname$/) && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				if (!scalar(@braceStack)) { $callbackIsTypedef = 1; }
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				$continuation = 1;
				$simpleTypedef = 1;
				# previous case falls through, so be explicit.
				if ($part =~ /^$typedefname$/) {
				    if (!($inComment || $inInlineComment || $inString || $inChar)) {
					if ($pascal) {
					    $namePending = 2;
					    $inPType = 1;
					    print "namePending -> 2 [3]\n" if ($parseDebug);
					}
					if ($posstypesPending) { $posstypes .=" $part"; }
					if (!($callbackNamePending)) {
						print "callbackNamePending -> 1\n" if ($localDebug || $cbnDebug);
						$callbackNamePending = 1;
					}
				    }
				}
				if ($sodclass eq "") {
					$startOfDec = 0; $sodname = "";
print "sodname cleared ($typedefname)\n" if ($sodDebug);
				}
				$lastchar = $part;
			    }; # end if
			}; # end do

		# C++ operator keyword handler

		($part eq "$operator") && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				$inOperator = 1;
				$sodname = "";
			    }
			    $lastsymbol = $part;
			    $lastchar = $part;
			    last SWITCH;
			    # next;
			};

		# Punctuation handlers

		($part =~ /;/o) && do {
			    if (!($inString || $inComment || $inInlineComment || $inChar)) {
				if ($parsedParamParse) {
					$parsedParam =~ s/^\s*//so; # trim leading space
					$parsedParam =~ s/\s*$//so; # trim trailing space
					if (length($parsedParam)) { push(@parsedParamList, $parsedParam); }
					print "pushed $parsedParam into parsedParamList [2semi]\n" if ($parmDebug);
					$parsedParam = "";
				}
				# skip this token
				$parsedParamParse = 2;
				$freezereturn = 1;
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				print "valuepending -> 0\n" if ($valueDebug);
				$valuepending = 0;
				$continuation = 1;
				if ($occmethod) {
					$prespaceadjust = -$prespace;
				}
				# previous case falls through, so be explicit.
				if ($part =~ /;/o && !$inMacroLine && !$inMacro) {
				    my $bsCount = scalar(@braceStack);
				    if (!$bsCount && !$kr_c_function) {
					if ($startOfDec == 2) {
						$sodclass = "constant";
						$startOfDec = 1;

					} elsif (!($inComment || $inInlineComment || $inChar || $inString)) {
						$startOfDec = 1;

					}
					# $lastsymbol .= $part;
				    }
				    if (!$bsCount) {
					$treeCur = pop(@treeStack) || $treeTop;
					print "TSPOP [8]\n" if ($tsDebug || $treeDebug);
					bless($treeCur, "HeaderDoc::ParseTree");
					while ($treePopTwo--) {
						$treeCur = pop(@treeStack) || $treeTop;
						print "TSPOP [9]\n" if ($tsDebug || $treeDebug);
						bless($treeCur, "HeaderDoc::ParseTree");
					}
					$treePopTwo = 0;
				    }
				}
				$lastchar = $part;
			    }; # end if
			}; # end do
		($part eq "=" && ($lastsymbol ne "operator")) && do {
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
				if ($part =~ /=/o && !scalar(@braceStack) &&
				    $nextpart !~ /=/o && $lastchar !~ /=/o &&
				    $sodclass ne "function" && !$inPType) {
					print "valuepending -> 1\n" if ($valueDebug);
					$valuepending = 1;
					$preEqualsSymbol = $lastsymbol;
					$sodclass = "constant";
					$startOfDec = 0;
				}; # end if
			}; # end do
		($part =~ /,/o) && do {
				if (!($inString || $inComment || $inInlineComment || $inChar)) {
					$onlyComments = 0;
					print "onlyComments -> 0\n" if ($macroDebug);
				}
				if ($part =~ /,/o && $parsedParamParse && (scalar(@braceStack) == 1)) {
					$parsedParam =~ s/^\s*//so; # trim leading space
					$parsedParam =~ s/\s*$//so; # trim trailing space
					if (length($parsedParam)) { push(@parsedParamList, $parsedParam); }
					print "pushed $parsedParam into parsedParamList [2]\n" if ($parmDebug);
					$parsedParam = "";
					# skip this token
					$parsedParamParse = 2;
					print "parsedParamParse -> 2\n" if ($parmDebug);
				}; # end if
			}; # end do
		{ # SWITCH default case

		    # Handler for all other text (data types, string contents,
		    # comment contents, character contents, etc.)

	# print "TEST CURLINE IS \"$curline\".\n";
		    if (!($inString || $inComment || $inInlineComment || $inChar)) {
		      if (!ignore($part, $ignoreref, $perheaderignoreref)) {
			if ($part =~ /\S/o) {
				$onlyComments = 0;
				print "onlyComments -> 0\n" if ($macroDebug);
			}
			if (!$continuation && !$occspace) {
				$curline = spacefix($curline, $part, $lastchar);
			} else {
				$continuation = 0;
				$occspace = 0;
			}
	# print "BAD CURLINE IS \"$curline\".\n";
			if (length($part) && !($inComment || $inInlineComment)) {
				if ($localDebug && $lastchar eq ")") {print "LC: $lastchar\nPART: $part\n";}
	# print "XXX LC: $lastchar SC: $sodclass LG: $lang\n";
				if ($lastchar eq ")" && $sodclass eq "function" && ($lang eq "C" || $lang eq "Csource")) {
					if ($part !~ /^\s*;/o) {
						# warn "K&R C FUNCTION FOUND.\n";
						# warn "NAME: $sodname\n";
						if (!isKeyword($part, $keywordhashref, $case_sensitive)) {
							print "K&R C FUNCTION FOUND [2].\n" if ($localDebug);
							$kr_c_function = 1;
							$kr_c_name = $sodname;
						}
					}
				}
				$lastchar = $part;
				if ($part =~ /\w/o || $part eq "::") {
				    if ($callbackNamePending == 1) {
					if (!($part =~ /^struct$/o || $part =~ /^enum$/o || $part =~ /^union$/o || $part =~ /^$typedefname$/)) {
						# we've seen the initial type.  The name of
						# the callback is after the next open
						# parenthesis.
						print "callbackNamePending -> 2\n" if ($localDebug || $cbnDebug);
						$callbackNamePending = 2;
					}
				    } elsif ($callbackNamePending == 3) {
					print "callbackNamePending -> 4\n" if ($localDebug || $cbnDebug);
					$callbackNamePending = 4;
					$callbackName = $part;
					$name = "";
					$sodclass = "";
					$sodname = "";
				    } elsif ($callbackNamePending == 4) {
					if ($part eq "::") {
						print "callbackNamePending -> 5\n" if ($localDebug || $cbnDebug);
						$callbackNamePending = 5;
						$callbackName .= $part;
					} elsif ($part !~ /\s/o) {
						print "callbackNamePending -> 0\n" if ($localDebug || $cbnDebug);
						$callbackNamePending = 0;
					}
				    } elsif ($callbackNamePending == 5) {
					if ($part !~ /\s/o) {
						print "callbackNamePending -> 4\n" if ($localDebug || $cbnDebug);
						if ($part !~ /\*/o) {
							$callbackNamePending = 4;
						}
						$callbackName .= $part;
					}
				    }
				    if ($namePending == 2) {
					$namePending = 1;
					print "namePending -> 1 [4]\n" if ($parseDebug);
				    } elsif ($namePending) {
					if ($name eq "") { $name = $part; }
					$namePending = 0;
					print "namePending -> 0 [5]\n" if ($parseDebug);
				    }
				} # end if ($part =~ /\w/o)
				if ($part !~ /[;\[\]]/o && !$inBrackets)  {
					my $opttilde = "";
					if ($seenTilde) { $opttilde = "~"; }
					if ($startOfDec == 1) {
						print "Setting sodname (maybe type) to \"$part\"\n" if ($sodDebug);
						$sodname = $opttilde.$part;
						if ($part =~ /\w/o) {
							$startOfDec++;
						}
					} elsif ($startOfDec == 2) {
						if ($part =~ /\w/o && !$inTemplate) {
							$preTemplateSymbol = "";
						}
						if ($inOperator) {
						    $sodname .= $part;
						} else {
						    if (length($sodname)) {
							$sodtype .= " $sodname";
						    }
						    $sodname = $opttilde.$part;
						}
print "sodname set to $part\n" if ($sodDebug);
					} else {
						$startOfDec = 0;
					}
				} elsif ($part eq "[") { # if ($part !~ /[;\[\]]/o)
					$inBrackets += 1;
					print "inBrackets -> $inBrackets\n" if ($sodDebug);
				} elsif ($part eq "]") {
					$inBrackets -= 1;
					print "inBrackets -> $inBrackets\n" if ($sodDebug);
				} # end if ($part !~ /[;\[\]]/o)
				if (!($part eq $eoc)) {
					if ($typestring eq "") { $typestring = $part; }
					if ($lastsymbol =~ /\,\s*$/o) {
						$lastsymbol .= $part;
					} elsif ($part =~ /^\s*\;\s*$/o) {
						$lastsymbol .= $part;
					} elsif (length($part)) {
						# warn("replacing lastsymbol with \"$part\"\n");
						$lastsymbol = $part;
					}
				} # end if (!($part eq $eoc))
			} # end if (length($part) && !($inComment || $inInlineComment))
		      }
		    } # end if (!($inString || $inComment || $inInlineComment || $inChar))
		} # end SWITCH default case
	    } # end SWITCH
	    if (length($part)) { $lasttoken = $part; }
	    if (length($part) && $inRegexpTrailer) { --$inRegexpTrailer; }
	    if ($postPossNL) { --$postPossNL; }
	    if (($simpleTypedef == 1) && ($part ne $typedefname) &&
		   !($inString || $inComment || $inInlineComment || $inChar ||
		     $inRegexp)) {
		# print "NP: $namePending PTP: $posstypesPending PART: $part\n";
		$simpleTDcontents .= $part;
	    }

	    my $ignoretoken = ignore($part, $ignoreref, $perheaderignoreref);
	    my $hide = ($ignoretoken && !($inString || $inComment || $inInlineComment || $inChar));
	    print "TN: $treeNest TS: $treeSkip\n" if ($tsDebug);
	    if (!$treeSkip) {
		if (!$seenBraces) { # TREEDONE
			if ($treeNest != 2) {
				# If we really want to skip and nest, set treeNest to 2.
				if (length($treepart)) {
					$treeCur = $treeCur->addSibling($treepart, $hide);
					$treepart = "";
				} else {
					$treeCur = $treeCur->addSibling($part, $hide);
				}
				bless($treeCur, "HeaderDoc::ParseTree");
			}
			# print "TC IS $treeCur\n";
			# $treeCur = %{$treeCur};
			if ($treeNest) {
				print "TSPUSH\n" if ($tsDebug || $treeDebug);
				push(@treeStack, $treeCur);
				$treeCur = $treeCur->addChild("", 0);
				bless($treeCur, "HeaderDoc::ParseTree");
			}
		}
	    }
	    $treeNest = 0;

	    if (!$freezereturn) {
		$returntype = "$declaration$curline";
 	    }

	    # From here down is... magic.  This is where we figure out how
	    # to handle parsed parameters, K&R C types, and in general,
	    # determine whether we've received a complete declaration or not.
	    #
	    # About 90% of this is legacy code to handle proper spacing.
	    # Those bits got effectively replaced by the parseTree class.
	    # The only way you ever see this output is if you don't have
	    # any styles defined in your config file.

	    if (($inString || $inComment || $inInlineComment || $inChar) ||
		!$ignoretoken) {
		if (!($inString || $inComment || $inInlineComment || $inChar) &&
                    !$ppSkipOneToken) {
	            if ($parsedParamParse == 1) {
		        $parsedParam .= $part;
	            } elsif ($parsedParamParse == 2) {
		        $parsedParamParse = 1;
		        print "parsedParamParse -> 1\n" if ($parmDebug);
	            }
		}
		$ppSkipOneToken = 0;
		print "MIDPOINT CL: $curline\nDEC:$declaration\nSCR: \"$scratch\"\n" if ($localDebug);
	        if (!$seenBraces) {
		    # Add to current line (but don't put inline function/macro
		    # declarations in.

		    if ($inString) {
			$curstring .= $part;
		    } else {
			if (length($curstring)) {
				if (length($curline) + length($curstring) >
				    $HeaderDoc::maxDecLen) {
					$scratch = nspaces($prespace);
					# @@@ WAS != /\n/ which is clearly
					# wrong.  Suspect the next line
					# if we start losing leading spaces
					# where we shouldn't (or don't where
					# we should).  Also was just /g.
					if ($curline !~ /^\s*\n/so) { $curline =~ s/^\s*//sgo; }
					
					# NEWLINE INSERT
					print "CURLINE CLEAR [1]\n" if ($localDebug);
					$declaration .= "$scratch$curline\n";
					$curline = "";
					$prespace += $prespaceadjust;
					$prespaceadjust = 0;
					$prespaceadjust -= 4;
					$prespace += 4;
				} else {
					# no wrap, so maybe add a space.
					if ($lastchar =~ /\=$/o) {
						$curline .= " ";
					}
				}
				$curline .= $curstring;
				$curstring = "";
			}
			if ((length($curline) + length($part) > $HeaderDoc::maxDecLen)) {
				$scratch = nspaces($prespace);
				# @@@ WAS != /\n/ which is clearly
				# wrong.  Suspect the next line
				# if we start losing leading spaces
				# where we shouldn't (or don't where
				# we should).  Also was /g instead of /sg.
				if ($curline !~ /^\s*\n/so) { $curline =~ s/^\s*//sgo; }
				# NEWLINE INSERT
				$declaration .= "$scratch$curline\n";
				print "CURLINE CLEAR [2]\n" if ($localDebug);
				$curline = "";
				$prespace += $prespaceadjust;
				$prespaceadjust = 0;
				$prespaceadjust -= 4;
				$prespace += 4;
			}
			if (length($curline) || $part ne " ") {
				# Add it to curline unless it's a space that
				# has inadvertently been wrapped to the
				# start of a line.
				$curline .= $part;
			}
		    }
		    if (peek(\@braceStack) ne "<") {
		      if ($part =~ /\n/o || ($part =~ /[\(;,]/o && $nextpart !~ /\n/o &&
		                      !$occmethod) ||
                                     ($part =~ /[:;.]/o && $nextpart !~ /\n/o &&
                                      $occmethod)) {
			if ($curline !~ /\n/o && !($inMacro || ($pascal && scalar(@braceStack)) || $inInlineComment || $inComment || $inString)) {
					# NEWLINE INSERT
					$curline .= "\n";
			}
			# Add the current line to the declaration.

			$scratch = nspaces($prespace);
			if ($curline !~ /\n/o) { $curline =~ s/^\s*//go; }
			if ($declaration !~ /\n\s*$/o) {
				$scratch = " ";
				if ($localDebug) {
					my $zDec = $declaration;
					$zDec = s/ /z/sg;
					$zDec = s/\t/Z/sg;
					print "ZEROSCRATCH\n";
					print "zDec: \"$zDec\"\n";
				}
			}
			$declaration .= "$scratch$curline";
				print "CURLINE CLEAR [3]\n" if ($localDebug);
			$curline = "";
			# $curline = nspaces($prespace);
			print "PS: $prespace -> " . $prespace + $prespaceadjust . "\n" if ($localDebug);
			$prespace += $prespaceadjust;
			$prespaceadjust = 0;
		      } elsif ($part =~ /[\(;,]/o && $nextpart !~ /\n/o &&
                                      ($occmethod == 1)) {
			print "SPC\n" if ($localDebug);
			$curline .= " "; $occspace = 1;
		      } else {
			print "NOSPC: $part:$nextpart:$occmethod\n" if ($localDebug);
		      }
		    }
		}
	        print "CURLINE IS \"$curline\".\n" if ($localDebug);
	        my $bsCount = scalar(@braceStack);
		print "ENDTEST: $bsCount \"$lastsymbol\"\n" if ($localDebug);
		print "KRC: $kr_c_function SB: $seenBraces\n" if ($localDebug);
	        if (!$bsCount && $lastsymbol =~ /;\s*$/o) {
		    if (!$kr_c_function || $seenBraces) {
			    $continue = 0;
			    print "continue -> 0 [3]\n" if ($localDebug);
		    }
	        } else {
		    print("bsCount: $bsCount, ls: $lastsymbol\n") if ($localDebug);
		    pbs(@braceStack);
	        }
	        if (!$bsCount && $seenBraces && ($sodclass eq "function" || $inOperator) && 
		    ($nextpart ne ";")) {
			# Function declarations end at the close curly brace.
			# No ';' necessary (though we'll eat it if it's there.
			$continue = 0;
			print "continue -> 0 [4]\n" if ($localDebug);
	        }
	        if (($inMacro == 3 && $lastsymbol ne "\\") || $inMacro == 4) {
		    if ($part =~ /[\n\r]/o) {
			print "MLS: $lastsymbol\n" if ($macroDebug);
			$continue = 0;
			print "continue -> 0 [5]\n" if ($localDebug);
		    }
	        } elsif ($inMacro == 2) {
		    warn "$filename:$inputCounter:Declaration starts with # but is not preprocessor macro\n";
	        } elsif ($inMacro == 3 && $lastsymbol eq "\\") {
			print "TAIL BACKSLASH ($continue)\n" if ($localDebug || $macroDebug);
		}
	        if ($valuepending == 2) {
		    # skip the "=" part;
		    $value .= $part;
	        } elsif ($valuepending) {
		    $valuepending = 2;
		    print "valuepending -> 2\n" if ($valueDebug);
	        }
	    } # end if "we're not ignoring this token"

	    if (length($part) && $part =~ /\S/o) { $lastnspart = $part; }
	    if ($seenTilde && length($part) && $part !~ /\s/o) { $seenTilde--; }
	    $part = $nextpart;
	} # end foreach (parts of the current line)
    } # end while (continue && ...)

    # Format and insert curline into the declaration.  This handles the
    # trailing line.  (Deprecated.)

    if ($curline !~ /\n/) { $curline =~ s/^\s*//go; }
    if ($curline =~ /\S/o) {
	$scratch = nspaces($prespace);
	$declaration .= "$scratch$curline\n";
    }

    print "($typestring, $basetype)\n" if ($localDebug || $listDebug);

    print "LS: $lastsymbol\n" if ($localDebug);
    # if ($simpleTypedef) { $name = ""; }

    # From here down is a bunch of code for determining which names
    # for a given type/function/whatever are legit and which aren't.
    # It is mostly a priority scheme.  The data type names are first,
    # and thus lowest priority.

    my $typelist = "";
    my $namelist = "";
    my @names = split(/[,\s;]/, $lastsymbol);
    foreach my $insname (@names) {
	$insname =~ s/\s//so;
	$insname =~ s/^\*//sgo;
	if (length($insname)) {
	    $typelist .= " $typestring";
	    $namelist .= ",$insname";
	}
    }
    $typelist =~ s/^ //o;
    $namelist =~ s/^,//o;

    if ($pascal) {
	# Pascal only has one name for a type, and it follows the word "type"
	if (!length($typelist)) {
		$typelist .= "$typestring";
		$namelist .= "$name";
	}
    }

print "TL (PRE): $typelist\n" if ($localDebug);

    if (!length($basetype)) { $basetype = $typestring; }
print "BT: $basetype\n" if ($localDebug);

print "NAME is $name\n" if ($localDebug || $listDebug);

# print $HeaderDoc::outerNamesOnly . " or " . length($namelist) . ".\n";

    # If the name field contains a value, and if we've seen at least one brace or parenthesis
    # (to avoid "typedef struct foo bar;" giving us an empty declaration for struct foo), and
    # if either we want tag names (foo in "struct foo { blah } foo_t") or there is no name
    # other than a tag name (foo in "struct foo {blah}"), then we give the tag name.  Scary
    # little bit of logic.  Sorry for the migraine.

    # Note: at least for argparse == 2 (used when handling nested headerdoc
    # markup), we don't want to return more than one name/type EVER.

    if ($name && length($name) && !$simpleTypedef && (!($HeaderDoc::outerNamesOnly || $argparse == 2) || !length($namelist))) {


	# print "NM: $name\nSTD: $simpleTypedef\nONO: ".$HeaderDoc::outerNamesOnly."\nAP: $argparse\nLNL: ".length($namelist)."\n";

	my $quotename = quote($name);
	if ($namelist !~ /$quotename/) {
		if (length($namelist)) {
			$namelist .= ",";
			$typelist .= " ";
		}
		$namelist .= "$name";
		$typelist .= "$basetype";
	}
    } else {
	# if we never found the name, it might be an anonymous enum,
	# struct, union, etc.

	if (!scalar(@names)) {
		print "Empty output ($basetype, $typestring).\n" if ($localDebug || $listDebug);
		$namelist = " ";
		$typelist = "$basetype";
	}

	print "NUMNAMES: ".scalar(@names)."\n" if ($localDebug || $listDebug);
    }

print "NL: \"$namelist\".\n" if ($localDebug || $listDebug);
print "TL: \"$typelist\".\n" if ($localDebug || $listDebug);
print "PT: \"$posstypes\"\n" if ($localDebug || $listDebug);

    # If it's a callback, the other names and types are bogus.  Throw them away.

    $callbackName =~ s/^.*:://o;
    $callbackName =~ s/^\*+//o;
    print "CBN: \"$callbackName\"\n" if ($localDebug || $listDebug);
    if (length($callbackName)) {
	$name = $callbackName;
	print "DEC: \"$declaration\"\n" if ($localDebug || $listDebug);
	$namelist = $name;
	if ($callbackIsTypedef) {
		$typelist = "typedef";
		$posstypes = "function";
	} else {
		$typelist = "function";
		$posstypes = "typedef";
	}
	print "NL: \"$namelist\".\n" if ($localDebug || $listDebug);
	print "TL: \"$typelist\".\n" if ($localDebug || $listDebug);
	print "PT: \"$posstypes\"\n" if ($localDebug || $listDebug);

	# my $newdec = "";
	# my $firstpart = 2;
	# foreach my $decpart (split(/\n/, $declaration)) {
		# if ($firstpart == 2) {
			# $newdec .= "$decpart ";
			# $firstpart--;
		# } elsif ($firstpart) {
			# $decpart =~ s/^\s*//o;
			# $newdec .= "$decpart\n";
			# $firstpart--;
		# } else {
			# $newdec .= "$decpart\n";
		# }
	# }
	# $declaration = $newdec;
    }

    if (length($preTemplateSymbol) && ($sodclass eq "function")) {
	$sodname = $preTemplateSymbol;
	$sodclass = "ftmplt";
	$posstypes = "ftmplt function method"; # can it really be a method?
    }

    # If it isn't a constant, the value is something else.  Otherwise,
    # the variable name is whatever came before the equals sign.

    print "TVALUE: $value\n" if ($localDebug);
    if ($sodclass ne "constant") {
	$value = "";
    } elsif (length($value)) {
	$value =~ s/^\s*//so;
	$value =~ s/\s*$//so;
	$posstypes = "constant";
	$sodname = $preEqualsSymbol;
    }

    # We lock in the name prior to walking through parameter names for
    # K&R C-style declarations.  Restore that name first.
    if (length($kr_c_name)) { $sodname = $kr_c_name; $sodclass = "function"; }

    # Okay, so now if we're not an objective C method and the sod code decided
    # to specify a name for this function, it takes precendence over other naming.

    if (length($sodname) && !$occmethod) {
	if (!length($callbackName)) { # && $callbackIsTypedef
	    if (!$perl_or_shell) {
		$name = $sodname;
		$namelist = $name;
	    }
	    $typelist = "$sodclass";
	    if (!length($preTemplateSymbol)) {
	        $posstypes = "$sodclass";
	    }
	    print "SETTING NAME/TYPE TO $sodname, $sodclass\n" if ($sodDebug);
	    if ($sodclass eq "function") {
		$posstypes .= " method";
	    }
	}
    }

    # If we're an objective C method, obliterate everything and just
    # shove in the right values.

    print "DEC: $declaration\n" if ($sodDebug || $localDebug);
    if ($occmethod) {
	$typelist = "method";
	$posstypes = "method function";
	if ($occmethod == 2) {
		$namelist = "$occmethodname";
	}
    }

    # If we're a macro... well, this gets ugly.  We rebuild the parsed
    # parameter list from the declaration and otherwise use the name grabbed
    # by the sod code.
    if ($inMacro == 3) {
	$typelist = "#define";
	$posstypes = "function method";
	$namelist = $sodname;
	$value = "";
	@parsedParamList = ();
	if ($declaration =~ /#define\s+\w+\s*\(/o) {
		my $pplref = defParmParse($declaration, $inputCounter);
		print "parsedParamList replaced\n" if ($parmDebug);
		@parsedParamList = @{$pplref};
	} else {
		# It can't be a function-like macro, but it could be
		# a constant.
		$posstypes = "constant";
	}
    } elsif ($inMacro == 4) { 
	$typelist = "MACRO";
	$posstypes = "MACRO";
	$value = "";
	@parsedParamList = ();
    }

    # If we're an operator, our type is 'operator', not 'function'.  Our fallback
    # name is 'function'.
    if ($inOperator) {
	$typelist = "operator";
	$posstypes = "function";
    }

    # if we saw private parameter types, restore the first declaration (the
    # public part) and store the rest for later.  Note that the parse tree
    # code makes this deprecated.

    my $privateDeclaration = "";
    if ($inPrivateParamTypes) {
	$privateDeclaration = $declaration;
	$declaration = $publicDeclaration;
    }

print "TYPELIST WAS \"$typelist\"\n" if ($localDebug);;
# warn("left blockParse (macro)\n");
# print "NumPPs: ".scalar(@parsedParamList)."\n";
print "LEFTBP\n" if ($localDebug);

# $treeTop->printTree();

    # If we have parsed parameters that haven't been pushed onto
    # the stack of parsed parameters, push them now.

    if (scalar(@parsedParamList)) {
		foreach my $stackitem (@parsedParamList) {
			$stackitem =~ s/^\s*//so;
			$stackitem =~ s/\s*$//so;
			if (length($stackitem)) {
				push(@pplStack, $stackitem);
			}
		}
    }

    # Restore the frozen stack (to avoid bogus parameters after
    # the curly brace for inline functions/methods)
    if ($stackFrozen) { @pplStack = @freezeStack; }

    if ($localDebug) {
	foreach my $stackitem (@pplStack) {
		print "stack contained $stackitem\n";
	}
    }

    # If we have a simple typedef, do some formatting on the contents.
    # This is used by the upper layers so that if you have
    # "typedef struct myStruct;", you can associate the fields from
    # "struct myStruct" with the typedef, thus allowing more
    # flexibility in tagged/parsed parameter comparison.
    # 
    $simpleTDcontents =~ s/^\s*//so;
    $simpleTDcontents =~ s/\s*;\s*$//so;
    if ($simpleTDcontents =~ s/\s*\w+$//so) {
	my $continue = 1;
	while ($simpleTDcontents =~ s/\s*,\s*$//so) {
		$simpleTDcontents =~ s/\s*\w+$//so;
	}
    }
    if (length($simpleTDcontents)) {
	print "SIMPLETYPEDEF: $inputCounter, $declaration, $typelist, $namelist, $posstypes, $value, OMITTED pplStack, $returntype, $privateDeclaration, $treeTop, $simpleTDcontents, $availability\n" if ($parseDebug || $sodDebug || $localDebug);
	$typelist = "typedef";
	$namelist = $sodname;
	$posstypes = "";
    }

    # print "Return type was: $returntype\n" if ($argparse || $sodclass eq "function" || $occmethod);
    if (length($sodtype) && !$occmethod) {
	$returntype = $sodtype;
    }
    # print "Return type: $returntype\n" if ($argparse || $sodclass eq "function" || $occmethod);
    # print "DEC: $declaration\n" if ($argparse || $sodclass eq "function" || $occmethod);

    # We're outta here.
    return ($inputCounter, $declaration, $typelist, $namelist, $posstypes, $value, \@pplStack, $returntype, $privateDeclaration, $treeTop, $simpleTDcontents, $availability);
}


sub spacefix
{
my $curline = shift;
my $part = shift;
my $lastchar = shift;
my $soc = shift;
my $eoc = shift;
my $ilc = shift;
my $localDebug = 0;

if ($HeaderDoc::use_styles) { return $curline; }

print "SF: \"$curline\" \"$part\" \"$lastchar\"\n" if ($localDebug);

	if (($part !~ /[;,]/o)
	  && length($curline)) {
		# space before most tokens, but not [;,]
		if ($part eq $ilc) {
				if ($lastchar ne " ") {
					$curline .= " ";
				}
			}
		elsif ($part eq $soc) {
				if ($lastchar ne " ") {
					$curline .= " ";
				}
			}
		elsif ($part eq $eoc) {
				if ($lastchar ne " ") {
					$curline .= " ";
				}
			}
		elsif ($part =~ /\(/o) {
print "PAREN\n" if ($localDebug);
			if ($curline !~ /[\)\w\*]\s*$/o) {
				print "CASEA\n" if ($localDebug);
				if ($lastchar ne " ") {
					print "CASEB\n" if ($localDebug);
					$curline .= " ";
				}
			} else {
				print "CASEC\n" if ($localDebug);
				$curline =~ s/\s*$//o;
			}
		} elsif ($part =~ /^\w/o) {
			if ($lastchar eq "\$") {
				$curline =~ s/\s*$//o;
			} elsif ($part =~ /^\d/o && $curline =~ /-$/o) {
				$curline =~ s/\s*$//o;
			} elsif ($curline !~ /[\*\(]\s*$/o) {
				if ($lastchar ne " ") {
					$curline .= " ";
				}
			} else {
				$curline =~ s/\s*$//o;
			}
		} elsif ($lastchar =~ /\w/o) {
			#($part =~ /[=!+-\/\|\&\@\*/ etc.)
			$curline .= " ";
		}
	}

	if ($curline =~ /\/\*$/o) { $curline .= " "; }

	return $curline;
}

sub nspaces
{
    my $n = shift;
    my $string = "";

    while ($n-- > 0) { $string .= " "; }
    return $string;
}

sub pbs
{
    my @braceStack = shift;
    my $localDebug = 0;

    if ($localDebug) {
	print "BS: ";
	foreach my $p (@braceStack) { print "$p "; }
	print "ENDBS\n";
    }
}

# parse #define arguments
sub defParmParse
{
    my $declaration = shift;
    my $inputCounter = shift;
    my @myargs = ();
    my $localDebug = 0;
    my $curname = "";
    my $filename = "";

    $declaration =~ s/.*#define\s+\w+\s*\(//o;
    my @braceStack = ( "(" );

    my @tokens = split(/(\W)/, $declaration);
    foreach my $token (@tokens) {
	print "TOKEN: $token\n" if ($localDebug);
	if (!scalar(@braceStack)) { last; }
	if ($token =~ /[\(\[]/o) {
		print "open paren/bracket - $token\n" if ($localDebug);
		push(@braceStack, $token);
	} elsif ($token =~ /\)/o) {
		print "close paren\n" if ($localDebug);
		my $top = pop(@braceStack);
		if ($top !~ /\(/o) {
			warn("$filename:$inputCounter:Parentheses do not match (macro).\nWe may have a problem.\n");
		}
	} elsif ($token =~ /\]/o) {
		print "close bracket\n" if ($localDebug);
		my $top = pop(@braceStack);
		if ($top !~ /\[/o) {
			warn("$filename:$inputCounter:Braces do not match (macro).\nWe may have a problem.\n");
		}
	} elsif ($token =~ /,/o && (scalar(@braceStack) == 1)) {
		$curname =~ s/^\s*//sgo;
		$curname =~ s/\s*$//sgo;
		push(@myargs, $curname);
		print "pushed \"$curname\"\n" if ($localDebug);
		$curname = "";
	} else {
		$curname .= $token;
	}
    }
    $curname =~ s/^\s*//sgo;
    $curname =~ s/\s*$//sgo;
    if (length($curname)) {
	print "pushed \"$curname\"\n" if ($localDebug);
	push(@myargs, $curname);
    }

    return \@myargs;
}

sub ignore
{
    my $part = shift;
    my $ignorelistref = shift;
    my %ignorelist = %{$ignorelistref};
    my $phignorelistref = shift;
    my %perheaderignorelist = %{$phignorelistref};
    my $localDebug = 0;

    # if ($part =~ /AVAILABLE/o) {
	# $localDebug = 1;
    # }

    my $def = $HeaderDoc::availability_defs{$part};
    if ($def && length($def)) { return $def; }

    if ($ignorelist{$part}) {
	    print "IGNORING $part\n" if ($localDebug);
	    return 1;
    }
    if ($perheaderignorelist{$part}) {
	    print "IGNORING $part\n" if ($localDebug);
	    return 1;
    }
    print "NO MATCH FOUND\n" if ($localDebug);
    return 0;
}

1;

