#! /usr/bin/perl -w
#
# Class name: 	ParseTree
# Synopsis: 	Used by gatherHeaderDoc.pl to hold references to doc 
#		for individual headers and classes
# Author: David Gatwood(dgatwood@apple.com)
# Last Updated: $Date: 2004/06/14 17:03:13 $
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
package HeaderDoc::ParseTree;

use strict;
use vars qw($VERSION @ISA);
use HeaderDoc::Utilities qw(isKeyword parseTokens quote stringToFields);
use HeaderDoc::BlockParse qw(blockParse nspaces);

$VERSION = '1.00';
################ General Constants ###################################
my $debugging = 0;

my $treeDebug = 0;

sub new {
    my($param) = shift;
    my($class) = ref($param) || $param;
    my $self = {};
    
    bless($self, $class);
    $self->_initialize();
    # Now grab any key => value pairs passed in
    my (%attributeHash) = @_;
    foreach my $key (keys(%attributeHash)) {
        my $ucKey = uc($key);
        $self->{$ucKey} = $attributeHash{$key};
    }  
    return ($self);
}

sub _initialize {
    my($self) = shift;
    # $self->{TOKEN} = undef;
    # $self->{NEXT} = undef;
    # $self->{FIRSTCHILD} = undef;
    $self->{APIOWNER} = ();
    $self->{PARSEDPARAMS} = ();
    # $self->{PETDONE} = 0;
    # $self->{HIDDEN} = 0;
    # $self->{XMLTREE} = undef;
    # $self->{HTMLTREE} = undef;
    # $self->{CPNC} = undef;
    # # $self->{NPCACHE} = undef;
    # $self->{NTNC} = undef;
    # # $self->{CTSUB} = undef;
    # # $self->{CTSTRING} = undef;
}

my $colorDebug = 0;

sub clone {
    my $self = shift;
    my $clone = undef;
    if (@_) {
        $clone = shift;
    } else {
        $clone = HeaderDoc::ParseTree->new(); 
    }

    # $self->SUPER::clone($clone);

    # now clone stuff specific to ParseTree

    $clone->{TOKEN} = $self->{TOKEN};

    # Note: apiOwner is no longer recursive, so there is no need
    # to recursively clone parse trees.  Only the top node will
    # ever be modified legitimately (except when pruning headerdoc
    # comments, but that needs to occur for all instances).

    $clone->{FIRSTCHILD} = $self->{FIRSTCHILD};
    $clone->{NEXT} = $self->{NEXT};

    # $clone->{FIRSTCHILD} = undef;
    # if ($self->{FIRSTCHILD}) {
	# my $firstchild = $self->{FIRSTCHILD};
	# $clone->{FIRSTCHILD} = $firstchild->clone();
    # }
    # $clone->{NEXT} = undef;
    # if ($self->{NEXT}) {
	# my $next = $self->{NEXT};
	# $clone->{NEXT} = $next->clone();
    # }

    $clone->{APIOWNER} = $self->{APIOWNER};
    $clone->{PARSEDPARAMS} = $self->{PARSEDPARAMS};
    $clone->{PETDONE} = 0;

    return $clone;
}

sub addSibling
{
    my $self = shift;
    my $name = shift;
    my $hide = shift;
    my $newnode = HeaderDoc::ParseTree->new();

# print "addSibling $self\n";
    print "addSibling $self \"$name\"\n" if ($treeDebug);

    my $pos = $self;
    bless($pos, "HeaderDoc::ParseTree");

    # print "POS: $pos\n";
    while ($pos && $pos->next()) {
	$pos = $pos->next();
	bless($pos, "HeaderDoc::ParseTree");
	# print "POS: $pos\n";
    }
    bless($pos, "HeaderDoc::ParseTree");
    $newnode->token($name);
    $newnode->hidden($hide);

    my $noderef = $newnode;

    return $pos->next($noderef);
}

sub addChild
{
    my $self = shift;
    my $name = shift;
    my $hide = shift;

# print "addChild\n";
    print "addChild $self \"$name\"\n" if ($treeDebug);

    if (!$self->firstchild()) {
	my $newnode = HeaderDoc::ParseTree->new();
	$newnode->hidden($hide);
	$newnode->token($name);
	my $noderef = $newnode;
	return $self->firstchild($noderef);
    } else {
	my $node = $self->firstchild();
	bless($node, "HeaderDoc::ParseTree");
	return $node->addSibling($name, $hide);
    }
}

# /*! Add an additional apiOwner for a tree.
#  */
sub addAPIOwner {
    my $self = shift;

    my $newapio = shift;
    push(@{$self->{APIOWNER}}, $newapio);
}

# /*! Set the apiOwner for the tree.
#  */
sub apiOwner {
    my $self = shift;

    if (@_) {
	my $newapio = shift;
	$self->{APIOWNER} = ();
        push(@{$self->{APIOWNER}}, $newapio);
    }

    my $apio = pop(@{$self->{APIOWNER}});
    push(@{$self->{APIOWNER}}, $apio);

    return $apio;
}

sub apiOwners
{
    my $self = shift;
    return $self->{APIOWNER};
}

sub token {
    my $self = shift;

    if (@_) {
        $self->{TOKEN} = shift;
    }
    return $self->{TOKEN};
}

sub hidden {
    my $self = shift;

    if (@_) {
	my $value = shift;
        $self->{HIDDEN} = $value;
	my $fc = $self->firstchild();
	if ($fc) { $fc->hiddenrec($value); }
    }
    return $self->{HIDDEN};
}

sub hiddenrec
{
    my $self = shift;
    my $value = shift;

    # print "SETTING HIDDEN VALUE OF TOKEN ".$self->token()." to $value\n";
    # $self->hidden($value);
    $self->{HIDDEN} = $value;

    my $fc = $self->firstchild();
    if ($fc) { $fc->hiddenrec($value); }
    my $nx = $self->next();
    if ($nx) { $nx->hiddenrec($value); }
}

sub objCparsedParams()
{
    my $self = shift;
    my @parsedParams = ();
    my $objCParmDebug = 0;

    my $inType = 0;
    my $inName = 0;
    my $position = 0;
    my $curType = "";
    my $curName = "";
    my $cur = $self;
    my @stack = ();

    my $eoDec = 0;

    my $noParse = 1;
    while ($cur || scalar(@stack)) {
	while (!$cur && !$eoDec) {
	    if (!($cur = pop(@stack))) {
		$eoDec = 1;
	    } else {
		$cur = $cur->next();
	    }
	}

	if ($eoDec) { last; }

	# process this element
	my $token = $cur->token();
	if ($token eq ":") {
	    $noParse = 0;
	} elsif ($noParse) {
	    # drop token on the floor.  It's part of the name.
	} elsif ($token eq "(") {
	    $inType++;
	    $curType .= $token;
	} elsif ($token eq ")") {
	    if (!(--$inType)) {
		$inName = 1;
	    }
	    $curType .= $token;
	} elsif ($token =~ /^[\s\W]/o && !$inType) {
	    # drop white space and symbols on the floor (except
	    # for pointer types)

	    if ($inName && length($curName)) {
		$inName = 0;
		my $param = HeaderDoc::MinorAPIElement->new();
		$param->linenum($self->apiOwner()->linenum());
		$param->outputformat($self->apiOwner()->outputformat());
		$param->name($curName);
		$param->type($curType);
		$param->position($position++);
		print "ADDED $curType $curName\n" if ($objCParmDebug);
		$curName = "";
		$curType = "";
		push(@parsedParams, $param);
		$noParse = 1;
	    }

	} elsif ($inType) {
	    $curType .= $token;
	} elsif ($inName) {
	    $curName .= $token;
	}

	my $fc = $cur->firstchild();
	if ($fc) {
	    push(@stack, $cur);
	    $cur = $fc;
	} else { 
	    $cur = $cur->next();
	}
    }

    if ($objCParmDebug) {
	foreach my $parm (@parsedParams) {
	    print "OCCPARSEDPARM: ".$parm->type()." ".$parm->name()."\n";
	}
    }

    return @parsedParams;
}

# /*! This subroutine is for future transition.  The end goal is to
#     move the parsed parameter support from the HeaderElement level
#     entirely into the parse tree. */
sub parsedParams()
{
    my $self = shift;
    my @array = ();

    if (@_) {
	if ($self->apiOwner() eq "HeaderDoc::Method") {
	    @{$self->{PARSEDPARAMS}} = $self->objCparsedParams();
	} else {
	    @{$self->{PARSEDPARAMS}} = @_;
	}
    }

    return @{$self->{PARSEDPARAMS}};
}

# /*! This subroutine handles embedded HeaderDoc markup, returning a list
#     of parameters, constants, etc.
#  */
sub processEmbeddedTags
{
    my $self = shift;
    my $xmlmode = shift;
    my $apiolist = $self->apiOwners();
    my $apio = $self->apiOwner();
    # $self->printTree();
    my $localDebug = 0;

    print $apio->name()."\n" if ($localDebug);

    if ($self->{PETDONE}) {
	print "SHORTCUT\n" if ($localDebug);
	return;
    }
    $self->{PETDONE} = 1;

    if (!$apio) { return; }
    my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        $typedefname, $varname, $constname, $structisbrace, $macronamesref) =
		@_;
		# parseTokens($apio->lang(), $apio->sublang());

    my $eoDeclaration = 1;
    my $lastDeclaration = "";
    my $curDeclaration = "";
    my $pendingHDcomment = "";

    my ($case_sensitive, $keywordhashref) = $apio->keywords();

	my $eocquot = quote($eoc);
    $self->processEmbeddedTagsRec($xmlmode, $eoDeclaration, $soc, $eoc, $eocquot, $ilc, $lbrace, $rbrace, $typedefname,
	$case_sensitive, $keywordhashref, $lastDeclaration, $curDeclaration, $pendingHDcomment,
	$apio, $apiolist);

    return;
}

# /*! This subroutine helps the parse tree code by simplifying the
#     work needed to use the block parser.
#  */
sub getNameAndFieldTypeFromDeclaration
{
    my $string = shift;
    my $apio = shift;
    my $typedefname = shift;
    my $case_sensitive = shift;
    my $keywordhashref = shift;

    my $localDebug = 0;
    my $inputCounter = 0;

    my $filename = $apio->filename();
    my $linenum = $apio->linenum();
    my $lang = $apio->lang();
    my $sublang = $apio->sublang();

    my $blockoffset = $linenum;
    my $argparse = 2;

    # This never hurts just to make sure the parse terminates.
    # Be sure to add a newline before the semicolon in case
    # there's an inline comment at the end.
    $string .= "\n;\n";

    print "STRING WAS $string\n" if ($localDebug);

    my @lines = split(/\n/, $string);

    # my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        # $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        # $typedefname, $varname, $constname, $structisbrace, $macronameref)
		# = parseTokens($lang, $sublang);

    # my @newlines = ();
    foreach my $line (@lines) {
	$line .= "\n";
	# push(@newlines, $line);
        # print "LINE: $line\n" if ($localDebug);
    }
    # @lines = @newlines;

    # my ($case_sensitive, $keywordhashref) = $apio->keywords();

    my ($inputCounter, $declaration, $typelist, $namelist, $posstypes, $value, $pplStackRef, $returntype, $privateDeclaration, $treeTop, $simpleTDcontents, $availability) = blockParse($filename, $blockoffset, \@lines, $inputCounter, $argparse, \%HeaderDoc::ignorePrefixes, \%HeaderDoc::perHeaderIgnorePrefixes, $keywordhashref, $case_sensitive);

    print "IC:$inputCounter DEC:$declaration TL:$typelist NL:$namelist PT:$posstypes VAL:$value PSR:$pplStackRef RT:$returntype PD:$privateDeclaration TT:$treeTop STC:$simpleTDcontents AV:$availability\n" if ($localDebug);

    my $name = $namelist;
    $name =~ s/^\s*//so; # ditch leading spaces
    $name =~ s/\s.*$//so; # ditch any additional names. (There shouldn't be any)
    my $typestring = $typelist . $posstypes;

print "TS: $typestring\n" if ($localDebug);

    my $type = "\@constant";
    if ($typestring =~ /^(function|method|ftmplt|operator|callback)/o) {
	$type = "\@callback";
    } elsif ($typestring =~ /^(struct|union|record|enum|typedef)/o || (length($typedefname) && $typestring =~ /^$typedefname/)) {
	$type = "\@field";
    } elsif ($typestring =~ /(MACRO|#define)/o) {
	$type = "\@field";
	if ($apio eq "HeaderDoc::PDefine") {
		# The @defineblock case
		$type = "\@define";
	}
    } elsif ($typestring =~ /(constant)/o) {
	$type = "\@constant";
	print "VALUE: \"$value\"\n" if ($localDebug);
	if (!length($value)) {
		# It's just a variable.
		$type = "\@field";
	}
    } else {
	warn "getNameAndFieldTypeFromDeclaration: UNKNOWN TYPE ($typestring) RETURNED BY BLOCKPARSE\n";
	print "STRING WAS $string\n" if ($localDebug);
    }

    if (!length($name)) {
	warn "COULD NOT GET NAME FROM DECLARATION.  DECLARATION WAS:\n$string\n";
	return ("", "");
    }
    print "TYPE $type, NAME $name\n" if ($localDebug);

    return ($name, $type);
}

# /*! This subroutine tells whether to process comments nested as children of
#     a given node in the parse tree.  We explicitly avoid things like strings
#     and regular expressions without the need to search for them by
#     disallowing children of any non-word, non-whitespace characters
#     other than parentheses, curly braces, and colons.
#  */
sub commentsNestedIn
{
    my $token = shift;
    my $soc = shift;
    my $eoc = shift;
    my $ilc = shift;
    my $lbrace = shift;
    my $case_sensitive = shift;

    # if ($token eq $soc || $token eq $eoc || $token eq $ilc) { return 1; }
    if ($token =~ /[{(}):]/o) { return 1; }
    if ($token =~ /^#/o) { return 2; }
    if (casecmp($token, $lbrace, $case_sensitive)) { return 1; }
    if ($token =~ /\s/o) { return 1; }
    if ($token =~ /\W/o) { return 0; }
    return 1;
}

# /*! This subroutine processes the parse tree recursively looking for
#     (and subsequently processing) embedded headerdoc markup.  This does
#     the actual work for processEmbeddedTags.
#  */
sub processEmbeddedTagsRec
{
    my $self = shift;
    my $xmlmode = shift;
    my $eoDeclaration = shift;
    my $soc = shift;
    my $eoc = shift;
    my $eocquot = shift;
    my $ilc = shift;
    my $lbrace = shift;
    my $rbrace = shift;
    my $typedefname = shift;
    my $case_sensitive = shift;
    my $keywordhashref = shift;
    my $lastDeclaration = shift;
    my $curDeclaration = shift;
    my $pendingHDcomment = shift;
    my $apio = shift;
    my $apiolist = shift;

    my $localDebug = 0;
    my $oldCurDeclaration = $curDeclaration;
    my $ntoken = $self->nextpeeknc($soc, $ilc);
    my $skipchildren = 0;

    if (!$self) { return ($eoDeclaration); }
    # print "lastDec: $lastDeclaration\ncurDec: $curDeclaration\neoDec: $eoDeclaration\n" if ($localDebug);

    # Walk the tree.
    my $token = $self->token();
    $curDeclaration .= $token;

    print "TOKEN: $token\n" if ($localDebug);

# if ($token !~ /\s/o) { print "TOKEN: \"$token\" SOC: \"$soc\" ILC: \"$ilc\".\n"; }

    if ($token eq $soc || $token eq $ilc) {
	my $firstchild = $self->firstchild();

	if ($firstchild) {
	print "FCT: ".$firstchild->token()."\n" if ($localDebug);
	  my $nextchild = $firstchild->next();
	  if ($nextchild && $nextchild->token eq "!") {
	      print "NCT: ".$nextchild->token()."\n" if ($localDebug);

	      my $string = $firstchild->textTree();
	      my $filename = $apio->filename();
	      my $linenum = $apio->linenum();
	      if ($token eq $soc) {
		$string =~ s/$eocquot\s*$//s;
	      }
	      if ($string =~ /^\s*\!/o) {
		      $string =~ s/^\s*\!//so;

		      print "EOD $eoDeclaration NT $ntoken STR $string\n" if ($localDebug);;

		      if (($eoDeclaration || !$ntoken ||
			   $ntoken =~ /[)}]/o || casecmp($ntoken, $rbrace, $case_sensitive)) &&
			  $string !~ /^\s*\@/o) {
			# If we're at the end of a declaration (prior to the
			# following newline) and the declaration starts with
			# a string of text (JavaDoc-style markup), we need to
			# figure out the name of the previous declaration and
			# insert it.

			if (!$eoDeclaration) {
				print "LASTDITCH\n" if ($localDebug);
			}

			$string =~ s/^\s*//so;
	
			print "COMMENTSTRING WAS: $string\n" if ($localDebug);
			# print "PRE1\n";
			my ($name, $type) = getNameAndFieldTypeFromDeclaration($lastDeclaration, $apio, $typedefname, $case_sensitive, $keywordhashref);
	
			$string = "$type $name\n$string";
			print "COMMENTSTRING NOW: $string\n" if ($localDebug);
		      }
		      $string =~ s/^\s*//so;
		      if ($string =~ /^\s*\@/o) {
			print "COMMENTSTRING: $string\n" if ($localDebug);
	
			my $fieldref = stringToFields($string, $filename, $linenum);
		# print "APIO: $apio\n";
			foreach my $owner (@{$apiolist}) {
				my $copy = $fieldref;
				$owner->processComment($copy);
			}
# print "APIO: $apio\n";
			$apio->{APIREFSETUPDONE} = 0;
		      } else {
			$pendingHDcomment = $string;
		      }
		      if (!$HeaderDoc::dumb_as_dirt) {
			# Drop this comment from the output.
			if ($xmlmode) {
				# We were doing this for HTML when we needed to
				# be able to reparse the tree after copying
				# it to a cloned data type.  This is no longer
				# needed, and the old method (above) is slightly
				# faster.
				$self->hidden(1); $skipchildren = 1;
			} else {
				$self->{TOKEN} = "";
				$self->{FIRSTCHILD} = undef;
			}
			print "DROP\n" if ($localDebug);
			$curDeclaration = $oldCurDeclaration;
		      }
	      }
	   }
	}
    } elsif ($token =~ /[;,]/o) {
	$lastDeclaration = "$curDeclaration\n";
	if ($pendingHDcomment) {
                # If we're at the end of a declaration (prior to the
                # following newline) and the declaration starts with
                # a string of text (JavaDoc-style markup), we need to
                # figure out the name of the previous declaration and
                # insert it.

			# print "PRE2\n";
                my ($name, $type) = getNameAndFieldTypeFromDeclaration($lastDeclaration, $apio, $typedefname, $case_sensitive, $keywordhashref);
                my $string = "$type $name\n$pendingHDcomment";
		my $filename = $apio->filename();
		my $linenum = $apio->linenum();

                my $fieldref = stringToFields($string, $filename, $linenum);
		print "COMMENTSTRING: $string\n" if ($localDebug);
		foreach my $owner (@{$apiolist}) {
			my $copy = $fieldref;
			$owner->processComment($copy);
		}
# print "APIO: $apio\n";
		$apio->{APIREFSETUPDONE} = 0;

		$pendingHDcomment = "";
	} else {
		$eoDeclaration = 1;
	}
	$curDeclaration = "";
    } elsif ($token !~ /\s/o) {
	$eoDeclaration = 0;
    }

    my $firstchild = $self->firstchild();
    my $next = $self->next();

    my $nestallowed = commentsNestedIn($token, $soc, $eoc, $ilc, $lbrace, $case_sensitive);
    if ($nestallowed && $firstchild && !$skipchildren) {
	if ($nestallowed == 1) {
		($eoDeclaration) = $firstchild->processEmbeddedTagsRec($xmlmode, $eoDeclaration, $soc, $eoc, $eocquot, $ilc, $lbrace, $rbrace, $typedefname, $case_sensitive, $keywordhashref, "", "", "", $apio, $apiolist);
	} else {
		($eoDeclaration) = $firstchild->processEmbeddedTagsRec($xmlmode, $eoDeclaration, $soc, $eoc, $eocquot, $ilc, $lbrace, $rbrace, $typedefname, $case_sensitive, $keywordhashref, "", "$curDeclaration", "", $apio, $apiolist);
	}
	$curDeclaration .= textTree($firstchild);
    } elsif ($firstchild && !$skipchildren) {
	$curDeclaration .= textTree($firstchild);
    }

    if ($ntoken) {
	print "NTOKEN: $ntoken\n" if ($localDebug);
    } else {
	print "NTOKEN: (null)\n" if ($localDebug);
    }

    if (!$ntoken || $ntoken =~ /[)]/o || casecmp($ntoken, $rbrace, $case_sensitive)) {
	# Last-ditch chance to process pending comment.
	# This takes care of the edge case where some languages
	# do not require the last item in a struct/record to be
	# terminated by a semicolon or comma.

	if ($ntoken =~ /[)}]/o || casecmp($ntoken, $rbrace, $case_sensitive)) {
		$lastDeclaration = $oldCurDeclaration;
	} else {
		$lastDeclaration = $curDeclaration;
	}
	if ($pendingHDcomment) {
		print "LASTDITCH\n" if ($localDebug);

                # If we're at the end of a declaration (prior to the
                # following newline) and the declaration starts with
                # a string of text (JavaDoc-style markup), we need to
                # figure out the name of the previous declaration and
                # insert it.

			# print "PRE3\n";
                my ($name, $type) = getNameAndFieldTypeFromDeclaration($lastDeclaration, $apio, $typedefname, $case_sensitive, $keywordhashref);
                my $string = "$type $name\n$pendingHDcomment";
		my $filename = $apio->filename();
		my $linenum = $apio->linenum();

                my $fieldref = stringToFields($string, $filename, $linenum);
		print "COMMENTSTRING: $string\n" if ($localDebug);
		foreach my $owner (@{$apiolist}) {
			my $copy = $fieldref;
			$owner->processComment($copy);
		}
# print "APIO: $apio\n";
		$apio->{APIREFSETUPDONE} = 0;

		$pendingHDcomment = "";
	}
    }
    if ($next) {
	($eoDeclaration) = $next->processEmbeddedTagsRec($xmlmode, $eoDeclaration, $soc, $eoc, $eocquot, $ilc, $lbrace, $rbrace, $typedefname, $case_sensitive, $keywordhashref, $lastDeclaration, $curDeclaration, $pendingHDcomment, $apio, $apiolist);
    }

    return ($eoDeclaration);
}

# THIS CODE USED TO PROCESS COMMENTS WHENEVER IT IS TIME.
	      # my $fieldref = stringToFields($string, $filename, $linenum);
	      # $apio->processComment($fieldref);
		# $apio->{APIREFSETUPDONE} = 0;

sub next {
    my $self = shift;

    if (@_) {
	my $node = shift;
        $self->{NEXT} = $node;
    }
    return $self->{NEXT};
}

sub firstchild {
    my $self = shift;

    if (@_) {
	my $node = shift;
        $self->{FIRSTCHILD} = $node;
    }
    return $self->{FIRSTCHILD};
}


sub printTree {
    my $self = shift;

    print "BEGINPRINTTREE\n";
    print $self->textTree();
    print "ENDPRINTTREE\n";
}

sub textTree {
    my $self = shift;
    my $string = "";

    $string .= $self->token();
    if ($self->{FIRSTCHILD}) {
	my $node = $self->{FIRSTCHILD};
	bless($node, "HeaderDoc::ParseTree");
	$string .= $node->textTree();
    }
    if ($self->{NEXT}) {
	my $node = $self->{NEXT};
	bless($node, "HeaderDoc::ParseTree");
	$string .= $node->textTree();
    }

    return $string;
}


sub xmlTree {
    my $self = shift;
    my $apio = $self->apiOwner();

    my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        $typedefname, $varname, $constname, $structisbrace, $macroListRef) = parseTokens($apio->lang(), $apio->sublang());

    $self->processEmbeddedTags(1, $sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        $typedefname, $varname, $constname, $structisbrace, $macroListRef);


    if ($self->{XMLTREE}) { return $self->{XMLTREE}; }

    # $self->printTree();
    my $apiOwner = undef;
    my $lang = undef;
    my $sublang = undef;
    my $occmethod = 0;
    my $localDebug = 0;

    my $debugName = ""; # "TypedefdStructWithCallbacksAndStructs";

    if ($self->apiOwner()) {
	$apiOwner = $self->apiOwner();
	bless($apiOwner, "HeaderDoc::HeaderElement");
	bless($apiOwner, $apiOwner->class());
	$lang = $apiOwner->lang();
	$sublang = $apiOwner->sublang();

	if (length($debugName) && ($apiOwner->name() eq $debugName)) {
		$colorDebug = 1;
	} else {
		$colorDebug = 0;
		print $apiOwner->name()."\n" if ($localDebug);
	}

	if ($apiOwner->class() eq "HeaderDoc::Method") {
		$occmethod = 1;
	} else {
		$occmethod = 0;
	}

	# print "APIOWNER was type $apiOwner\n";
    } else {
	$apiOwner = HeaderDoc::HeaderElement->new();
	$lang = $HeaderDoc::lang;
	$sublang = $HeaderDoc::sublang;
	$apiOwner->lang($lang);
	$apiOwner->sublang($sublang);
	$occmethod = 0; # guess
    }
    # colorizer goes here

    my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        $typedefname, $varname, $constname, $structisbrace, $macroListRef) = parseTokens($lang, $sublang);

    my ($retvalref, $junka, $junkb, $junkc) = $self->colorTreeSub($apiOwner, "", 0, 0, 0, $occmethod, "", $sotemplate, $soc, $eoc, $ilc, $lbrace, $rbrace, $sofunction, $soprocedure, $varname, $constname, $unionname, $structname, $typedefname, $structisbrace, $macroListRef, "", $lang, $sublang, 1, 0, 0, 0, 0, 0, "", "");
    my $retval = ${$retvalref};

    # my $retval = "";
    # $retval = $self->textTree();
    # $self->printTree();

    $self->{XMLTREE} = $retval;

    return $retval;
}

sub htmlTree {
    my $self = shift;

    # print "TREE\n";
    # $self->printTree();
    # print "ENDTREE\n";
    my $apiOwner = undef;
    my $lang = undef;
    my $sublang = undef;
    my $occmethod = 0;
    my $localDebug = 0;

    my $debugName = ""; # "TypedefdStructWithCallbacksAndStructs";

    if ($self->{HTMLTREE}) {
	 print "SHORTCUT\n" if ($localDebug);
	 return $self->{HTMLTREE};
    }

    if ($self->apiOwner()) {
	$apiOwner = $self->apiOwner();
	bless($apiOwner, "HeaderDoc::HeaderElement");
	bless($apiOwner, $apiOwner->class());
	$lang = $apiOwner->lang();
	$sublang = $apiOwner->sublang();

	if (length($debugName) && ($apiOwner->name() eq $debugName)) {
		$colorDebug = 1;
	} else {
		$colorDebug = 0;
		print $apiOwner->name()."\n" if ($localDebug);
	}

	if ($apiOwner->class() eq "HeaderDoc::Method") {
		$occmethod = 1;
	} else {
		$occmethod = 0;
	}

	# print "APIOWNER was type $apiOwner\n";
    } else {
	$apiOwner = HeaderDoc::HeaderElement->new();
	$lang = $HeaderDoc::lang;
	$sublang = $HeaderDoc::sublang;
	$apiOwner->lang($lang);
	$apiOwner->sublang($sublang);
	$occmethod = 0; # guess
    }
    # colorizer goes here

    my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        $typedefname, $varname, $constname, $structisbrace, $macroListRef) = parseTokens($lang, $sublang);

    $self->processEmbeddedTags(0, $sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        $typedefname, $varname, $constname, $structisbrace, $macroListRef);

    my ($retvalref, $junka, $junkb, $junkc) = $self->colorTreeSub($apiOwner, "", 0, 0, 0, $occmethod, "", $sotemplate, $soc, $eoc, $ilc, $lbrace, $rbrace, $sofunction, $soprocedure, $varname, $constname, $unionname, $structname, $typedefname, $structisbrace, $macroListRef, "", $lang, $sublang, 0, 0, 0, 0, 0, 0, "", "");
    my $retval = ${$retvalref};

    # my $retval = "";
    # $retval = $self->textTree();
    # $self->printTree();

    $self->{HTMLTREE} = $retval;

    return $retval;
}

sub childpeeknc
{
    my $self = shift;
    my $soc = shift;
    my $ilc = shift;
    my $cache = $self->{CPNC};
    if ($cache) { return $cache; }

    my $node = $self->{FIRSTCHILD};

    if (!$node) { return ""; }

    bless($node, "HeaderDoc::ParseTree");

    if (!$node->token()) { return $node->childpeeknc($soc, $ilc) || return $node->nextpeeknc($soc, $ilc); }
    if ($node->token() =~ /\s/o) { return $node->childpeeknc($soc, $ilc) || return $node->nextpeeknc($soc, $ilc); }
    if ($node->token() eq $soc) { return $node->childpeeknc($soc, $ilc) || return $node->nextpeeknc($soc, $ilc); }
    if ($node->token() eq $ilc) { return $node->childpeeknc($soc, $ilc) || return $node->nextpeeknc($soc, $ilc); }

    $cache = $node->token();
    $self->{CPNC} = $cache;

    return $cache;
}

sub nextpeek
{
    my $self = shift;
    my $soc = shift;
    my $ilc = shift;

    # This cache appears to be slowing things down.
    # if ($self->{NPCACHE}) { return $self->{NPCACHE}; }

    my $node = undef;
    if ($self->firstchild()) {
	$node = $self->firstchild();
	$node = $node->next;
    } else {
	$node = $self->next();
    }

    if (!$node) {
	# $self->{NPCACHE} = "";
	return "";
    }

    my $token = $node->token();
    if ($token =~ /\s/o && $token !~ /[\r\n]/o) {
	my $ret = $node->nextpeek($soc, $ilc);
	# $self->{NPCACHE} = $ret;
	return $ret;
    }

    # $self->{NPCACHE} = $node->token();
    return $node->token();

}

sub nextpeeknc
{
    my $self = shift;
    my $soc = shift;
    my $ilc = shift;

    my $node = $self->nextTokenNoComments($soc, $ilc);
    if (!$node) { return ""; }

    return $node->token();

}

sub nextnextpeeknc
{
    my $self = shift;
    my $soc = shift;
    my $ilc = shift;

    my $node = $self->nextTokenNoComments($soc, $ilc);
    if (!$node) { return ""; }

    my $nodeafter = $node->nextTokenNoComments($soc, $ilc);
    if (!$nodeafter) { return ""; }

    return $nodeafter->token();

}

sub nextTokenNoComments
{
    my $self = shift;
    my $soc = shift;
    my $ilc = shift;

    my $cache = $self->{NTNC};
    if ($cache) { return $cache; }

    my $node = $self->{NEXT};

    if (!$node) { return undef }

    bless($node, "HeaderDoc::ParseTree");
# print "SOC: $soc ILC: $ilc\n" if ($colorDebug);

    # print "MAYBE ".$node->token()."\n" if ($colorDebug);

    if (!$node->token()) { return $self->{NTNC} = $node->nextTokenNoComments($soc, $ilc); }
    if ($node->token() =~ /\s/o) { return $self->{NTNC} = $node->nextTokenNoComments($soc, $ilc); }
    if ($node->token() eq $soc) { return $self->{NTNC} = $node->nextTokenNoComments($soc, $ilc); }
    if ($node->token() eq $ilc) { return $self->{NTNC} = $node->nextTokenNoComments($soc, $ilc); }

    $self->{NTNC} = $node;
    return $node;
}

sub isMacro
{
    my $self = shift;
    my $token = shift;
    my $lang = shift;
    my $sublang = shift;

    if ($lang ne "C") { return 0; }

    if ($token =~ /^\#\w+/o) { return 1; }

    return 0;
}

sub casecmp
{
    my $a = shift;
    my $b = shift;
    my $case = shift;

    if ($case) {
	if (($a eq $b) && length($a) && length($b)) { return 1; }
    } else {
	my $bquot = quote($b);
	if (($a =~ /^$bquot$/) && length($a) && length($b)) { return 1; }
    }

    return 0;
}

sub colorTreeSub
{
    my $self = shift;
    my $apio = shift;
    my $type = shift;
    my $depth = shift;
    my $inComment = shift;
    my $inQuote = shift;
    my $inObjCMethod = shift;
    my $lastBrace = shift;
    my $sotemplate = shift;
    my $soc = shift;
    my $eoc = shift;
    my $ilc = shift;
    my $lbrace = shift;
    my $rbrace = shift;
    my $sofunction = shift;
    my $soprocedure = shift;
    my $varname = shift;
    my $constname = shift;
    my $unionname = shift;
    my $structname = shift;
    my $typedefname = shift;
    my $structisbrace = shift;
    my $macroListRef = shift;
    my $prespace = shift;
    my $lang = shift;
    my $sublang = shift;
    my $xmlmode = shift;
    my $newlen = shift;
    my $breakable = shift;
    my $inMacro = shift;
    my $inEnum = shift;
    my $seenEquals = shift;
    my $lastKeyword = shift;
    my $lastnstoken = shift;

    my %macroList = %{$macroListRef};
    my $oldLastBrace = $lastBrace;
    my $oldDepth = $depth;
    my $oldInMacro = $inMacro;
    my $oldInQuote = $inQuote;
    my $oldLastKeyword = $lastKeyword;
    my $oldInComment = $inComment;
    my $dropFP = 0;

    # This cache slows things down now that it works....
    # if ($self->{CTSUB}) { return (\$self->{CTSTRING}, $self->{CTSUB}); }
    my $localDebug = 0;
    my $psDebug = 0;
    my $treeDebug = 0;
    my $dropDebug = 0;

    if ($xmlmode && $localDebug) {
	print "XMLMODE.\n";
    }

    # foreach my $listitem (@macroList) { print "ML: $listitem\n"; }

    print "IM: $inMacro\n" if ($localDebug);

    my $mustbreak = 0;
    my $nextprespace = "";
    my $string = "";
    my $tailstring = "";
    my $token = $self->{TOKEN};
    my $escapetoken = "";
    my ($case_sensitive, $keywordhashref) = $apio->keywords();
    my $tokennl = 0;
    if ($token =~ /^[\r\n]/o) { $tokennl = 1; }

    # my $ctoken = $self->childpeek($soc, $ilc);
    # print "TK $token\n" if ($colorDebug);
    my $ctoken = $self->childpeeknc($soc, $ilc);
    my $ntoken = $self->nextpeek($soc, $ilc);
    my $ntokennc = $self->nextpeeknc($soc, $ilc);
    my $nntokennc = $self->nextnextpeeknc($soc, $ilc);
    my $tokenType = undef;
    my $drop = 0;
    my $firstCommentToken = 0;
    my $leavingComment = 0;
    my $hidden = ($self->hidden() && !$xmlmode);

    print "TOKEN: $token NTOKEN: $ntoken LASTNSTOKEN: $lastnstoken IC: $inComment\n" if ($treeDebug || $localDebug);
    print "OCC: $inObjCMethod\n" if ($colorDebug || $localDebug);
    print "HIDDEN: $hidden\n" if ($localDebug);

    # last one in each chain prior to a "," or at end of chain is "var"
    # or "parm" (functions)
    print "TK $token NT $ntoken NTNC $ntokennc NNTNC $nntokennc LB: $lastBrace PS: ".length($prespace)."\n" if ($colorDebug);

    my $nextbreakable = 0;
    if ($breakable == 2) {
	$breakable = 0;
	$nextbreakable = 1;
    } elsif ($breakable == 3) {
	$mustbreak = 1;
	$breakable = 1;
	$nextbreakable = 0;
    }

    if ($lang eq "C" && $token eq "enum") {
	my $curname = $apio->name();
	print "NAME: $curname\n" if ($localDebug);
	print "NOW ENUM\n" if ($localDebug);
	$inEnum = 1;
    }

    if ($inObjCMethod && $token =~ /^[+-]/o && !length($lastBrace)) {
	$lastBrace = $token;
    }

    my $splitchar = "";
    if ($type =~ /^(typedef|struct|record|union)/o) {
		$splitchar = ";";
    } elsif ($type =~ /^(enum|funcptr)/o) {
		$splitchar = ",";
    } elsif ($lastBrace eq "(") {
		$splitchar = ",";
		if ($lang eq "C" && $sublang eq "MIG") { $splitchar = ";"; }
    } elsif ($lastBrace eq "$lbrace") {
		if ($inEnum) {
			$splitchar = ",";
		} else {
			$splitchar = ";";
		}
    } elsif (($lastBrace eq "$structname") && $structisbrace) {
		$splitchar = ";";
    }
print "SPLITCHAR IS $splitchar\n" if ($localDebug);
    if ($splitchar && ($token eq $splitchar)) { # && ($ntoken !~ /^[\r\n]/o)) {
	print "WILL SPLIT AFTER \"$token\" AND BEFORE \"$ntoken\".\n" if ($localDebug);
	$nextbreakable = 3;
    }

print "SOC: \"$soc\"\nEOC: \"$eoc\"\nILC: \"$ilc\"\nLBRACE: \"$lbrace\"\nRBRACE: \"$rbrace\"\nSOPROC: \"$soprocedure\"\nSOFUNC: \"$sofunction\"\nVAR: \"$varname\"\nSTRUCTNAME: \"$structname\"\nTYPEDEFNAME: \"$typedefname\"\n" if ($localDebug);

print "inQuote: $inQuote\noldInQuote: $oldInQuote\ninComment: $inComment\ninMacro: $inMacro\ninEnum: $inEnum\n" if ($localDebug);
print "oldInMacro: $oldInMacro\noldInComment: $oldInComment\n" if ($localDebug);

    # print "TOKEN: $token\n" if ($localDebug);

    if ($inEnum) {
	# If we see this, anything nested below here is clearly not a union.
	if (casecmp($token, $unionname, $case_sensitive)) { $inEnum = 0; };
	if (casecmp($token, $structname, $case_sensitive)) { $inEnum = 0; };
	if (casecmp($token, $typedefname, $case_sensitive)) { $inEnum = 0; };
    }
    if ($lang eq "C" || $lang eq "java" || $lang eq "pascal" ||
		$lang eq "php" || $lang eq "perl" ||
		$lang eq "Csource" || $lang eq "shell") {
	if ($inQuote == 1) {
		print "STRING\n" if ($localDebug);
		$tokenType = "string";
	} elsif ($inQuote == 2) {
		print "CHAR\n" if ($localDebug);
		$tokenType = "char";
	} elsif ($token eq "$soc" && length($soc)) {
	    if (!$hidden) {
		$tokenType = "comment";
		print "COMMENT [1]\n" if ($localDebug);
		if (!$inComment) {
			$inComment = 1;
			$firstCommentToken = 1;
			if ($xmlmode) {
				$string .= "<declaration_comment>";
			} else {
				$string .= "<font class=\"comment\">";
			}
		} else {
			print "nested comment\n" if ($localDebug);
		}
	    }
	} elsif (($token eq "$ilc") && length($ilc)) {
	    if (!$hidden) {
		print "ILCOMMENT [1]\n" if ($localDebug);
		$tokenType = "comment";
		if (!$inComment) {
			print "REALILCOMMENT\n" if ($localDebug);
			$inComment = 2;
			$firstCommentToken = 1;
			if ($xmlmode) {
				$string .= "<declaration_comment>";
			} else {
				$string .= "<font class=\"comment\">";
			}
		} else {
			print "nested comment\n" if ($localDebug);
		}
	    }
	} elsif ($token eq "$eoc" && length($eoc)) {
		print "EOCOMMENT [1]\n" if ($localDebug);
		$tokenType = "comment";
		if ($xmlmode) {
			$tailstring .= "</declaration_comment>";
		} else {
			$tailstring = "</font>";
		}
		$leavingComment = 1;
		$inComment = 0;
	} elsif ($tokennl && $ntoken !~ /^[\r\n]/o) {
		if ($inComment == 2) {
			print "EOILCOMMENT [1]\n" if ($localDebug);
			$tokenType = "comment";
			if ($xmlmode) {
				$string .= "</declaration_comment>";
			} else {
				$string .= "</font>";
			}
			$inComment = 0;
			$newlen = 0;
			$mustbreak = 1;
			# $token = "";
			$drop = 1;
		} elsif ($inMacro) {
			$mustbreak = 1;
			$newlen = 0;
		} elsif ($inComment) {
			$mustbreak = 1;
			$newlen = 0;
			# $token = "";
			$drop = 1;
		}
		$breakable = 0;
		$nextbreakable = 0;
		# $nextprespace = nspaces(4 * $depth);
		$newlen = 0;
	# } elsif ($ntoken =~ /^[\r\n]/o) {
		# print "NEXT TOKEN IS NLCR\n" if ($localDebug);
		# $breakable = 0;
		# $nextbreakable = 0;
	} elsif ($inComment) {
		print "COMMENT [2:$inComment]\n" if ($localDebug);
		$tokenType = "comment";
		if ($inComment == 1) {
			if ($token =~ /^\s/o && !$tokennl && $ntoken !~ /^\s/o) {
				# Only allow wrapping of multi-line comments.
				# Don't blow in extra newlines at existing ones.
				$breakable = 1;
			}
		}
	} elsif ($inMacro) {
		print "MACRO [IN]\n" if ($localDebug);
		$tokenType = "preprocessor";
	} elsif ($token eq "=") {
		$nextbreakable = 1;
		if ($type eq "pastd") {
			$type = "";
			print "END OF VAR\n" if ($localDebug);
		}
		if ($lang eq "pascal") { $seenEquals = 1; }
	} elsif ($token eq "-") {
		if ($ntoken =~ /^\d/o) {
			$tokenType = "number";
			print "NUMBER [1]\n" if ($localDebug);
		} else {
			print "TEXT [1]\n" if ($localDebug);
			$tokenType = "";
		}
	} elsif ($token =~ /^\d+$/o || $token =~ /^0x[\dabcdef]+$/o) {
		$tokenType = "number";
		$type = "hexnumber";
		print "\nNUMBER [2]: $token\n" if ($localDebug);
	} elsif (casecmp($token, $sofunction, $case_sensitive) || casecmp($token, $soprocedure, $case_sensitive)) {
		$tokenType = "keyword";
		$lastKeyword = $token;
		print "SOFUNC/SOPROC\n" if ($localDebug);
		$type = "funcproc";
		$lastBrace = "(";
		$oldLastBrace = "(";
	} elsif ($type eq "funcproc") {
		if ($token =~ /^\;/o) {
			$type = "";
			$nextbreakable = 3;
		}
		print "FUNC/PROC NAME\n" if ($localDebug);
		$tokenType = "function";
	} elsif (casecmp($token, "$constname", $case_sensitive)) {
		$tokenType = "keyword";
		print "VAR\n" if ($localDebug);
		$type = "pasvar";
	} elsif (casecmp($token, "$varname", $case_sensitive)) {
		$tokenType = "keyword";
		print "VAR\n" if ($localDebug);
		$type = "pasvar";
	} elsif (($type eq "pasvar" || $type eq "pastd") &&
		 ($token =~ /^[\;\:\=]/o)) {
			# NOTE: '=' is handled elsewhere,
			# but it is included above for clarity.
			$type = "";
			print "END OF VAR\n" if ($localDebug);
	} elsif ($type eq "pasvar" || $type eq "pastd") {
		print "VAR NAME\n" if ($localDebug);
		$tokenType = "var";
	} elsif (($lang eq "pascal") && casecmp($token, "$typedefname", $case_sensitive)) {
		# TYPE
		print "TYPE\n" if ($localDebug);
		$tokenType = "keyword";
		$type = "pastd";
	} elsif (($lang eq "pascal") && casecmp($token, "$structname", $case_sensitive)) {
		# RECORD
		print "RECORD\n" if ($localDebug);
		$lastBrace = $token;
		$tokenType = "keyword";
		$type = "pasrec";
	} elsif (isKeyword($token, $keywordhashref, $case_sensitive)) {
		$tokenType = "keyword";

		# NOTE: If anybody ever wants "class" to show up colored
		# as a keyword within a template, the next block should be
		# made conditional on a command-line option.  Personally,
		# I find it distracting, hene the addition of these lines.

		if ($lastBrace eq "$sotemplate" && length($sotemplate)) {
			$tokenType = "template";
		}

		print "KEYWORD\n" if ($localDebug);
		# $inMacro = $self->isMacro($token, $lang, $sublang);
		# We could have keywords in a macro, so don't set this
		# to zero.  It will get zeroed when we pop a level
		# anyway.  Just set it to 1 if needed.
		if ($case_sensitive) {
			if ($macroList{$token}) { $inMacro = 1; }
		} else {
		    foreach my $cmpToken (keys %macroList) {
			if (casecmp($token, $cmpToken, $case_sensitive)) {
				$inMacro = 1;
			}
		    }
		}
		print "TOKEN IS $token, IM is now $inMacro\n" if ($localDebug);
		if (casecmp($token, $rbrace, $case_sensitive)) {
			print "PS: ".length($prespace)." -> " if ($psDebug);
			# $prespace = nspaces(4 * ($depth-1));
			$mustbreak = 2;
			print length($prespace)."\n" if ($psDebug);
		}
	} elsif ($ntokennc eq ":" && $inObjCMethod) {
		print "FUNCTION [1]\n" if ($localDebug);
		$tokenType = "function";
	} elsif ($token eq ":" && $inObjCMethod) {
		print "FUNCTION [2]\n" if ($localDebug);
		$tokenType = "function";
	} elsif ($token eq ":" && $ctoken) {
		$depth = $depth - 1; # We'll change it back before the next token.
	} elsif ($ntokennc eq "(" && !$seenEquals) {
		$tokenType = "function";
		print "FUNCTION [3]\n" if ($localDebug);
		if ($nntokennc eq "(") {
			$tokenType = "type";
			$type = "funcptr";
		}
		if ($inObjCMethod) {
			$tokenType = ""; # shouldn't happen 
		}
		if ($token eq "(") { $dropFP = 1; }
	} elsif ($ntokennc eq "$lbrace" && length($lbrace)) {
		$tokenType = "type";
		print "TYPE [1]\n" if ($localDebug);

	} elsif ($token eq "(") {
		if ($inObjCMethod && $lastBrace =~ /^[+-]/o) {
			$nextbreakable = 0;
			$oldLastBrace = "";
		} elsif ($ctoken ne ")") {
			$nextbreakable = 3;
		}
		$lastBrace = $token;
	} elsif ($token eq "$sotemplate" && length($sotemplate)) {
		$lastBrace = $token;
		$nextbreakable = 0;
		$breakable = 0;
	} elsif (casecmp($token, $lbrace, $case_sensitive)) {
		$lastBrace = $token;
		$nextbreakable = 3;
		if (!casecmp($ctoken, $rbrace, $case_sensitive)) {
			$nextbreakable = 3;
		}
	} elsif ($token =~ /^\"/o) {
		$inQuote = 1;
	} elsif ($token =~ /^\'/o) {
		$inQuote = 2;
	} elsif ($ntokennc =~ /^(\)|\,|\;)/o || casecmp($ntokennc, $rbrace, $case_sensitive)) {
		# last token
		print "LASTTOKEN\n" if ($localDebug);
		if ($nextbreakable != 3) {
			$nextbreakable = 2;
		}
		if ($lastBrace eq "$sotemplate" && length($sotemplate)) {
			$nextbreakable = 0;
		}
		if ($lastBrace eq "(") {
			if ($sublang eq "MIG" || $lang eq "pascal") {
				$tokenType = "type";
				print "TYPE [2]\n" if ($localDebug);
			} else {
				$tokenType = "param";
				print "PARAM [1]\n" if ($localDebug);
			}
		} elsif ($lastBrace eq "$sotemplate" && length($sotemplate)) {
			print "TEMPLATE[1]\n" if ($localDebug);
			$tokenType = "template";
		} elsif ($type eq "funcptr") {
			$tokenType = "function";
			print "FUNCTION [1]\n" if ($localDebug);
			$breakable = 0;
			$nextbreakable = 0;
		} else {
			if ($sublang eq "MIG" || $lang eq "pascal") {
				$tokenType = "type";
				print "TYPE [2a]\n" if ($localDebug);
			} else {
				$tokenType = "var";
				print "VAR [1] (LB: $lastBrace)\n" if ($localDebug);
			}
		}
		if (casecmp($ntokennc, $rbrace, $case_sensitive) && $type eq "pasrec") {
			$type = "";
		}
		if ($ntokennc eq ")") {
			$nextbreakable = 0;
			if ($inObjCMethod || ($token eq "*")) {
				print "TYPE [3]\n" if ($localDebug);
				$tokenType = "type";
			}
		}
	} elsif ($prespace ne "" && ($token =~ /^\)/o || casecmp($token, $rbrace, $case_sensitive))) {
		print "PS: ".length($prespace)." -> " if ($psDebug);
		$prespace = nspaces(4 * ($depth-1));
		print length($prespace)."\n" if ($psDebug);
		$mustbreak = 2;
	} elsif (casecmp($token, $rbrace, $case_sensitive)) {
		$prespace = nspaces(4 * ($depth-1));
		print length($prespace)."\n" if ($psDebug);
		$mustbreak = 2;
	} else {
		if ($inObjCMethod) {
			if ($lastBrace eq "(") {
				print "TYPE [4]\n" if ($localDebug);
				$tokenType = "type";
			} else { 
				print "PARAM [2]\n" if ($localDebug);
				$tokenType = "param";
			}
		} elsif ($sublang eq "MIG" || $lang eq "pascal") {
			if ($lastBrace eq "(") {
				print "PARAM [3]\n" if ($localDebug);
				$tokenType = "param";
			}
		} else {
			if ($lastBrace eq "$sotemplate" && length($sotemplate)) {
				print "TEMPLATE [5]\n" if ($localDebug);
				$tokenType = "template";
			} else {
				print "TYPE [5]\n" if ($localDebug);
				$tokenType = "type";
			}
		}
	}
    } else {
	my $filename = $apio->filename;
	my $linenum = $apio->linenum;
	warn "$filename:$linenum:Unknown language $lang.  Not coloring.  Please file a bug.\n";
    }

    if ($hidden) {
	$tokenType = "ignore";
	$nextbreakable = 0;
	$mustbreak = 0;
	$breakable = 0;
    }

    if (length($ilc) && $ntoken eq $ilc && !$inComment) {
	$breakable = 0; $nextbreakable = 0;
    } elsif (length($soc) && $ntoken eq $soc && !$inComment) {
	$breakable = 0; $nextbreakable = 0;
    }
print "NB: $nextbreakable\n" if ($localDebug);

    if ($type eq "pasrec" && $tokenType eq "") { $tokenType = "var"; }
    else { print "TYPE: $type TT: $tokenType\n" if ($localDebug); }
    print "IM: $inMacro\n" if ($localDebug);

    if (!$inComment && $token =~ /^\s/o && !$tokennl && ($mustbreak || !$newlen)) {
	print "CASEA\n" if ($localDebug);
	print "NL: $newlen TOK: \"$token\" PS: \"$prespace\" NPS: \"$nextprespace\"\n" if ($localDebug);
	print "dropping leading white space\n" if ($localDebug);
	$drop = 1;
    } elsif (!$inComment && $tokennl) {
	print "CASEB\n" if ($localDebug);
	if ($lastnstoken ne $eoc) {
		# Insert a space instead.

		print "dropping newline\n" if ($localDebug);
		$drop = 1;
		$string .= " ";
	} else {
		$mustbreak = 1;
	}
    } elsif ($inComment || $token =~ /^\s/o || ($token =~ /^\W/o && $token ne "*") || !$tokenType) {
	print "CASEC\n" if ($localDebug);
	my $macroTail = "";
	$escapetoken = $apio->textToXML($token);
	print "OLDPS: \"$prespace\" ET=\"$escapetoken\" DROP=$drop\n" if ($localDebug);
	if ($inComment && $prespace ne "" && !$hidden) {
		if ($xmlmode) {
			$string .= "</declaration_comment>\n$prespace<declaration_comment>";
		} else {
			$string .= "</font>\n$prespace<font class=\"comment\">";
		}
	} elsif ($inMacro) {
		# Could be the initial keyword, which contains a '#'
		if ($xmlmode) {
			$string .= "$prespace<declaration_$tokenType>";
			$macroTail = "</declaration_$tokenType>";
		} else {
			$string .= "$prespace<font class=\"$tokenType\">";
			$macroTail = "</font>";
		}
	} elsif (!$hidden) {
		$string .= "$prespace";
	}
	if ($drop) { $escapetoken = ""; }
	if ($tokenType eq "ignore") {
	    if (!$HeaderDoc::dumb_as_dirt) {
		# Drop token.
		print "HD: DROPPING IGNORED TOKEN $escapetoken\n" if ($dropDebug);
		$escapetoken = "";
	    } else {
		print "HD BASIC: KEEPING IGNORED TOKEN $escapetoken\n" if ($dropDebug);
	    }
	}

	$string .= "$escapetoken$macroTail";
	print "comment: $token\n" if ($localDebug);
    } else {
	print "CASED\n" if ($localDebug);

	my $add_link_requests = $HeaderDoc::add_link_requests;
	$escapetoken = $apio->textToXML($token);

	if (length($tokenType) && length($token) && token !~ /^\s/o) {
		my $fontToken = "";
		if ($xmlmode) {
			$fontToken = "<declaration_$tokenType>$escapetoken</declaration_$tokenType>";
		} else {
		    if ($tokenType ne "ignore") {
			$fontToken = "<font class=\"$tokenType\">$escapetoken</font>";
		    } elsif (!$HeaderDoc::dumb_as_dirt) {
			# Drop token.
			print "HD: DROPPING IGNORED TOKEN $escapetoken\n" if ($dropDebug);
			$fontToken = "";
		    } else {
			print "HD BASIC: KEEPING IGNORED TOKEN $escapetoken\n" if ($dropDebug);
			$fontToken = $escapetoken;
		    }
		}
		my $refToken = $apio->genRef($lastKeyword, $escapetoken, $fontToken);

		# Don't add noisy link requests in XML.
		if ($add_link_requests && $tokenType =~ /^(function|type|preprocessor)/o && !$xmlmode) {
			$string .= "$prespace$refToken";
		} else {
			$string .= "$prespace$fontToken";
		}
	} else {
		$escapetoken = $apio->textToXML($token);
		if ($tokenType eq "ignore") {
		    if (!$HeaderDoc::dumb_as_dirt) {
			# Drop token.
			print "HD: DROPPING IGNORED TOKEN $escapetoken\n" if ($dropDebug);
			$escapetoken = "";
		    } else {
			print "HD BASIC: KEEPING IGNORED TOKEN $escapetoken\n" if ($dropDebug);
		    }
		}
		$string .= "$prespace$escapetoken";
	}
	print "$tokenType: $token\n" if ($localDebug);
    }
    $prespace = $nextprespace;

    if (!$drop) {
	$newlen += length($token);
    }

    print "NL $newlen MDL $HeaderDoc::maxDecLen BK $breakable IM $inMacro\n" if ($localDebug);
    if ($mustbreak ||
		(($newlen > $HeaderDoc::maxDecLen) &&
		    $breakable && !$inMacro && !$hidden)) {
	if ($token =~ /^\s/o || $token eq "") {
		$nextprespace = nspaces(4 * ($depth+(1-$mustbreak)));
		print "PS WILL BE \"$nextprespace\"\n" if ($localDebug);
		$nextbreakable = 3;
	} else {
		print "NEWLEN: $newlen\n" if ($localDebug);
		$newlen = length($token);
		print "NEWLEN [2]: $newlen\n" if ($localDebug);
		print "MB: $mustbreak, DP: $depth\n" if ($localDebug);
		my $ps = nspaces(4 * ($depth+(1-$mustbreak)));
		if (($inComment == 1 && !$firstCommentToken) || $leavingComment) {
		    if ($xmlmode) {
			$string = "</declaration_comment>\n$ps<declaration_comment>$string";
		    } else {
			$string = "</font>\n$ps<font class=\"comment\">$string";
		    }
		} else {
			$string = "\n$ps$string";
		}
		print "PS WAS \"$ps\"\n" if ($localDebug);
	}
    }

    if ($token !~ /^\s/o) { $lastnstoken = $token; }

    my $newstring = "";
    my $node = $self->{FIRSTCHILD};
    my $newstringref = undef;
    if ($node) {
	print "BEGIN CHILDREN\n" if ($localDebug || $colorDebug || $treeDebug);
	bless($node, "HeaderDoc::ParseTree");
	($newstringref, $newlen, $nextbreakable, $prespace, $lastnstoken) = $node->colorTreeSub($apio, $type, $depth + 1, $inComment, $inQuote, $inObjCMethod, $lastBrace, $sotemplate, $soc, $eoc, $ilc, $lbrace, $rbrace, $sofunction, $soprocedure, $varname, $constname, $unionname, $structname, $typedefname, $structisbrace, $macroListRef, $prespace, $lang, $sublang, $xmlmode, $newlen, $nextbreakable, $inMacro, $inEnum, $seenEquals, $lastKeyword, $lastnstoken);
	$newstring = ${$newstringref};
	print "END CHILDREN\n" if ($localDebug || $colorDebug || $treeDebug);
    }
    $string .= $newstring; $newstring = "";

    if (length($prespace)) {
	# if we inherit a need for prespace from a descendant, it means
	# that the descendant ended with a newline.  We don't want to
	# propagate the extra indentation to the next node, though, so
	# we'll regenerate the value of prespace here.
	$prespace = nspaces(4 * $depth);
    }

    $string .= $tailstring;
    $tailstring = "";
    print "LB $lastBrace -> $oldLastBrace\n" if ($colorDebug || $localDebug);
    $lastBrace = $oldLastBrace;
    $depth = $oldDepth;
    $inMacro = $oldInMacro;
    $lastKeyword = $oldLastKeyword;
    $inComment = $oldInComment;
    $inQuote = $oldInQuote;
    # if ($inComment && !$oldInComment) {
	# $inComment = $oldInComment;
	# if ($xmlmode) {
		# $string .= "</declaration_comment>";
	# } else {
		# $string .= "</font>";
	# }
    # }

    if ($dropFP) { $type = $apio->class(); }

    $node = $self->{NEXT};
    if ($node) {
	bless($node, "HeaderDoc::ParseTree");
	($newstringref, $newlen, $nextbreakable, $prespace, $lastnstoken) = $node->colorTreeSub($apio, $type, $depth, $inComment, $inQuote, $inObjCMethod, $lastBrace, $sotemplate, $soc, $eoc, $ilc, $lbrace, $rbrace, $sofunction, $soprocedure, $varname, $constname, $unionname, $structname, $typedefname, $structisbrace, $macroListRef, $prespace, $lang, $sublang, $xmlmode, $newlen, $nextbreakable, $inMacro, $inEnum, $seenEquals, $lastKeyword, $lastnstoken);
	$newstring = ${$newstringref};
    }
    $string .= $newstring;

    # $self->{CTSTRING} = $string;
    # $self->{CTSUB} = ($newlen, $nextbreakable, $prespace, $lastnstoken);
    return (\$string, $newlen, $nextbreakable, $prespace, $lastnstoken);
}


sub printObject {
    my $self = shift;
 
    print "----- ParseTree Object ------\n";
    print "token: $self->{TOKEN}\n";
    print "next: $self->{NEXT}\n";
    print "firstchild: $self->{FIRSTCHILD}\n";
    print "\n";
}

1;
