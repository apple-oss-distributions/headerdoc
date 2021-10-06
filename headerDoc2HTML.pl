#!/usr/bin/perl
#
# Script name: headerDoc2HTML
# Synopsis: Scans a file for headerDoc comments and generates an HTML
#           file from the comments it finds.
#
# Last Updated: $Date: 2012/01/11 09:43:51 $
#
# ObjC additions by SKoT McDonald <skot@tomandandy.com> Aug 2001 
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
# $Revision: 1326303831 $
#####################################################################


# /*!
#     @header
#         The main HeaderDoc tool, <code>headerDoc2HTML.pl</code>
#         (<code>headerdoc2html</code> when installed), translates a
#         header file (or source code file) into HTML
#         (or XML).
#
#         This document provides API-level documentation
#         on the tool's internals.  For user documentation, see
#         {@linkdoc //apple_ref/doc/uid/TP40001215 HeaderDoc User Guide}.
#     @indexgroup HeaderDoc Tools
#  */



# /*!
#     @abstract
#         The version number of the HeaderDoc suite.
#  */
my $HeaderDoc_Version = "8.9";

# /*!
#     @abstract
#         The revision control revision number for this script.
#     @discussion
#         In the git repository, contains the number of seconds since
#         January 1, 1970.
#  */
my $VERSION = '$Revision: 1326303831 $';

# /*!
#     @abstract
#         The default comment in the right side if a header or
#         class lacks a discussion.
#  */
$HeaderDoc::defaultHeaderComment = "Use the links in the table of contents to the left to access the documentation.<br>\n";    

# /*!
#     @abstract
#         Enables parsing of a bit more of the C programming
#         language to support nonstandard (external) uses of
#         the parser.
#     @discussion
#         HeaderDoc itself does not use this functionality.
#  */
$HeaderDoc::parseIfElse = 0;

# /*!
#     @abstract
#         Storage for the bareNamesFromAPIRefs flag
#     @discussion
#         By default, if you use an \@link tag and
#         specify only an API reference marker (apple_ref),
#         as a link destination (with no link text),
#         HeaderDoc substitutes a class method call for
#         Objective-C methods and a name in the form
#         <code>classname::methodName</code> for other
#         methods.
#
#         If you set this flag to 1, this behavior is
#         disabled for Objective-C methods.
#
#         If you set this flag to 2, this behavior is
#         disabled for non-Objective-C methods.
#
#         If you set this flag to 3, this behavior is
#         disabled for all methods.
#  */
$HeaderDoc::nameFromAPIRefReturnsOnlyName = 0;


################ General Constants ###################################
# /*! @abstract
#         If running in MacPerl in Mac OS 9, contains 1; normally 0.
#  */
my $isMacOS;			

# /*! @abstract
#         Normally "/", but ":" if running in MacPerl in Mac OS 9.
#  */
my $pathSeparator;

################ Flag Storage ###################################
# /*! @abstract
#         Storage for the -o flag.
#  */
my $specifiedOutputDir;

# /*! @abstract
#         Storage for the -d flag.
#  */
my $debugging = 0;

# /*! @abstract
#         Storage for the -v flag.
#  */
my $printVersion;

# /*! @abstract
#         Storage for the -q flag.
#  */
my $quietLevel;

# /*! @abstract
#         Storage for the -X flag. Also set for the -m flag.
#  */
my $xml_output;

# /*! @abstract
#         Storage for the -m flag.
#  */
my $man_output;

# /*! @abstract
#         Storage for the -f flag.
#  */
my $function_list_output;

# /*! @abstract
#         Storage for the -x flag.
#  */
my $doxytag_output;

# /*! @abstract
#         Storage for the -s flag.
#  */
my $headerdoc_strip;

# /*! @abstract
#         Storage for the -P flag. Also set for the -f flag.
#  */
my $use_stdout;

# /*! @abstract
#         Storage for the -r flag (not yet implemented).
#  */
my $regenerate_headers;

# # /*! @abstract
#         Storage for the -h flag.  (Legacy cruft.)
#  */
# my $write_control_file;

################ Other Globals ###################################
# /*! @abstract
#         Language currently being parsed.
#  */
my $lang = "C";


# Legacy cruft for "DB export" module.  To be deleted in the future.
# my $testingExport = 0;
# my $export;
# Look-up tables are used when exporting API and doc to tab-delimited
# data files, which can be used for import to a database.  
# The look-up tables supply uniqueID-to-APIName mappings.
# my $lookupTableDirName;
# my $lookupTableDir;
# my $functionFilename;
# my $typesFilename;
# my $enumsFilename;

# /*!
#     @abstract
#         The array of input files to be procesed.
#  */
my @inputFiles;

# /*! @abstract
#         Temp storage for list of temp files.
#  */
my @doxyTagFiles;

# Described later.  Defined inside the BEGIN block.
# @HeaderDoc::ignorePrefixes = ();
# @HeaderDoc::perHeaderIgnorePrefixes = ();
# %HeaderDoc::perHeaderIncludes = ();

# /*!
#     @abstract
#         Used to set the owning class when processing
#         embedded API symbols.
#  */
$HeaderDoc::currentClass = undef;


# /*!
#     @abstract
#         Provides an out-of-band way for the block
#         parser to change the main API owner at the
#         top level of HeaderDoc.
#     @discussion
#         Used to work around the rather odd way
#         Perl's classes are designed.  (They have no
#         end, and due to limitations in HeaderDoc,
#         they cannot be parsed as a single block
#         and pulled apart as other languages can.)
#
#         Normally, this is empty.  When set by the
#         parser, the top-level API owner is reset
#         to that object.
#  */
$HeaderDoc::perlClassChange = undef;

# /*!
#     @abstract
#         Determines whether the macro filter code
#         should treat the <code>!=</code> token as
#         a <code>==</code> token due to consistent
#         eccentricities in what is being parsed.
#     @discussion
#         HeaderDoc <code>never</code> uses this
#         feature.  It is provided entirely for other
#         (internal) tools that use the same code for
#         very different purposes.
#     @seealso HeaderDoc::reverse_match
#  */
$HeaderDoc::enable_reverse_match = 0;

# /*!
#     @abstract
#         The specific value that causes HeaderDoc
#         to treat the <code>!=</code> token as
#         a <code>==</code> token due to consistent
#         eccentricities in what is being parsed.
#     @discussion
#         HeaderDoc <code>never</code> uses this
#         feature.  It is provided entirely for other
#         (internal) tools that use the same code for
#         very different purposes.
#
#     @seealso HeaderDoc::enable_reverse_match
#  */
$HeaderDoc::reverse_match = 0;

# /*!
#     @abstract
#         Determines whether the macro filter code
#         attempts to handle <code>switch</code> and
#         <code>case</code> statements.
#     @discussion
#         HeaderDoc <code>never</code> uses this
#         feature.  It is provided entirely for other
#         (internal) tools that use the same code for
#         very different purposes.
#  */
$HeaderDoc::interpret_case = 0;

# /*!
#     @abstract
#         Set high to idicate that HeaderDoc needs to process a file again.
#     @abstract
#         In practice, this goes high whenever HeaderDoc encounters
#         an <code>\@ignore</code> or <code>\@ignorefuncmacro</code>
#         tag in an <code>\@header</code> comment.
#  */
my $reprocess_input = 0;

# No longer used.  Always zero.
# $HeaderDoc::nodec = 0;

# /*!
#     @abstract
#         The name of the current function group.
#     @discussion
#         Set by the <code>\@functiongroup</code> tag.  Reset to empty upon
#         changing to a new header.  (If empty, the value of
#         {@link HeaderDoc::globalGroup}
#         is used instead.
#  */
my $functionGroup = "";

# $HeaderDoc::outerNamesOnly = 0;

# /*!
#     @abstract
#         The name of the current group.
#     @discussion
#         Set by the <code>\@group</code> tag.  Reset to empty upon
#         changing to a new header.
#  */
$HeaderDoc::globalGroup = "";

# /*!
#     @abstract
#         Indicates that all token objects should be marked hidden.
#
#     @discussion
#         The block parser uses this variable as an out-of-band way to
#         pass the "hide node" flag data to the parse tree package.
#
#         Ideally, this should eventuallly go away and should be replaced
#         by changes to every place where a new node gets created, but
#         that isn't nearly as easy as it sounds.
#  */
$HeaderDoc::hidetokens = 0;

# /*!
#     @abstract
#         The exit status.  Changed to nonzero whenever an error occurs.
#  */
$HeaderDoc::exitstatus = 0;

# /*!
#     @abstract
#         The skiplist file.
#     @discussion
#         If HeaderDoc is processing a single directory as its input,
#         it looks for a file at the top level of that directory called
#         <code>skiplist</code>.  If it finds that file, it reads it,
#         and for each line that is not commented out (with a # sign),
#         it adds it into this newline-delimited list.
#
#         HeaderDoc later uses this list to determine which files
#         to skip when processing the content.  Note that the
#         preferred way to do this is with exclude lists (the
#         <code>-e</code> flag).
#  */
$HeaderDoc::skiplist = "";

# /*!
#     @abstract
#         The API reference language for IDL file content.
#     @discussion
#         An IDL file contains an interface description in an abstract
#         interface description language (hence the abbreviation).
#         Thus, the actual interfaces could be for any programming
#         language.
#
#         By default, IDL file API references (apple_ref symbol markers)
#         are emitted using <code>idl</code> as the language name, but
#         you can override this by specifying a different value for
#         the <code>IDLLanguage</code> field in the HeaderDoc
#         config file.
#  */
$HeaderDoc::idl_language = "idl";

# /*!
#     @abstract
#         The default C compiler.
#     @discussion
#         By default, HeaderDoc uses <code>/usr/bin/gcc</code> to calculate
#         the values of complex #define macros.  This can be overridden with
#         the <code>cCompiler</code> field in the HeaderDoc config file.
#  */
$HeaderDoc::c_compiler = "/usr/bin/gcc";

# /*!
#     @abstract
#         Turns on debug output when objects are allocated and released.
#  */
$HeaderDoc::debugAllocations = 0;

# /*!
#     @abstract
#         New TOC style variable.
#     @discussion
#         Set by {@link setTOCFormat}.
#  */
$HeaderDoc::newTOC = 0;

my @headerObjects;	# holds finished objects, ready for printing
					# we defer printing until all header objects are ready
					# so that we can merge ObjC category methods into the 
					# headerObject that holds the class, if it exists.
my @categoryObjects;	    # holds finished objects that represent ObjC categories
my %objCClassNameToObject = ();	# makes it easy to find the class object to add category methods to
my %headerIncluded = ();

# /*!
#     @abstract
#         A hash of all API reference markers for minir API elements emitted so far.
#     @discussion
#         Used to prevent anyAPI reference markers from being
#         emitted when a documentation block that describes a declaration
#         with multiple names gets emitted a second (or subsequent) time.
#  */
%HeaderDoc::appleRefUsed = ();

# /*!
#     @abstract
#         A hash table mapping availability macros
#         to the text that describes them.
#     @discussion
#         Used in the block parser to get a human-readable
#         string that describes the availability of the
#         current declaration.
#  */
%HeaderDoc::availability_defs = ();

# /*!
#     @abstract
#         A hash table mapping availability macros
#         to whether or not the macro declaration takes
#         a parenthesized argument list.
#     @discussion
#         Used in the block parser to determine whether to
#         strip off the subsequent parenthetical
#         code or not.
#  */
%HeaderDoc::availability_has_args = ();

# /*!
#     @abstract
#         The list of filename patterns to exclude when
#         producing documentation.
#     @discussion
#         Obtained from the file specified by the
#         <code>-e</code> flag.
#  */
@HeaderDoc::exclude_patterns = ();

# $HeaderDoc::enable_custom_references = 0;

my @classObjects;

# /*!
#     @abstract
#         Set to 1 if you need to enable lots of debugging
#         for a single file.
#     @discussion
#         Most of the time, when debugging, you can get by
#         with processing a single file.  When debugging
#         subtle C preprocessing bugs or other subtle
#         misbehavior, however, it is occasionally
#         necessary to process a <b>lot</b> of files to
#         reproduce the bug.
#         
#         This flag allows you to leave debugging off until
#         you get to a particular file, then turn it
#         on temporarily for the duration of that file.
#
#         This flag must be used in conjunction with
#         {@link HeaderDoc::debugFile}.
#   */
$HeaderDoc::fileDebug = 0;

# /*!
#     @abstract
#         Set to the name of a file to tell HeaderDoc
#         to enable debugging when processing that file.
#     @discussion
#         Only active if {@link HeaderDoc::fileDebug} is
#         nonzero.
#   */
$HeaderDoc::debugFile = "";

# /*!
#     @abstract
#         The current line number being parsed.
#     @discussion
#         Used as an out-of-band way to get this information
#         into the parse tree.  Should ideally be an argument
#         when each parse tree node is being created, but that
#         isn't nearly as easy as it sounds.
#  */
$HeaderDoc::CurLine = 0;

# $HeaderDoc::debugFile = "AAutoToolbar.h";
# $HeaderDoc::debugFile = "IOFWCommand.h";
# $HeaderDoc::debugFile = "IONetworkInterface.h";
					
# Turn on autoflushing of 'print' output.  This is useful
# when HeaderDoc is operating in support of a GUI front-end
# which needs to get each line of log output as it is printed. 
$| = 1;

# Check options in BEGIN block to avoid overhead of loading supporting 
# modules in error cases.
my $uninstalledModulesPath;
my $devtoolsModulesPath;
BEGIN {
    use FindBin qw ($Bin);
    use Cwd;
    # use Getopt::Std;
    use Getopt::Long;
    use File::Find;

    # /*!
    #     @abstract
    #         Magic flag used when parsing manual page declarations.
    #
    #     @discussion
    #         Set to 1 if (in C) you want a function declaration
    #         to end after the closing parenthesis even if there
    #         is no trailing semicolon.  Do NOT set this for
    #         normal parsing; it will break many typedef
    #         declarations and similar.  This also enables
    #         some broken man page detection for deleting lines
    #         that say <code>or</code> and <code>and</code>.
    #
    #         Note that HeaderDoc does not actually set this flag.
    #         It is used by other tools that share this parser.
    # */
    $HeaderDoc::parsing_man_pages = undef;

    # /*!
    #     @abstract
    #         Global header object for the header currently
    #         being parsed.
    #     @discussion
    #         This should eventually go away.
    #  */
    $HeaderDoc::headerObject = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>-T</code> flag.
    #  */
    $HeaderDoc::testmode = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>-M</code> flag.
    #  */
    $HeaderDoc::man_section = "3";

    # /*!
    #     @abstract
    #         Global variable where the language family info for the
    #         header currently being parsed is stored.
    #     @discussion
    #         Historical versions of HeaderDoc used this in place
    #         of passing this information around through the code.
    #         This has been corrected in current versions, but
    #         the {@link //apple_ref/perl/instm/HeaderDoc::BlockParse/blockParse//() blockParse} and {@link //apple_ref/perl/instm/HeaderDoc::BlockParse/blockParseOutside//() blockParseOutside}
    #         functions still support falling back to this and
    #         {@link HeaderDoc::sublang} for backwards
    #         compatibility.  (This backward compatibility is
    #         temporary, however.)
    #  */
    $HeaderDoc::lang = undef;

    # /*!
    #     @abstract
    #         Global variable where the language info for the
    #         header currently being parsed is stored.
    #     @discussion
    #         Historical versions of HeaderDoc used this in place
    #         of passing this information around through the code.
    #         This has been corrected in current versions, but
    #         the {@link //apple_ref/perl/instm/HeaderDoc::BlockParse/blockParse//() blockParse} and {@link //apple_ref/perl/instm/HeaderDoc::BlockParse/blockParseOutside//() blockParseOutside}
    #         functions still support falling back to this and
    #         {@link HeaderDoc::lang} for backwards
    #         compatibility.  (This backward compatibility is
    #         temporary, however.)
    #  */
    $HeaderDoc::sublang = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>-H</code> flag.
    #  */
    $HeaderDoc::insert_header = 0;

    # /*!
    #     @abstract
    #         Storage for the <code>introductionName</code> configuration file field.
    #  */
    $HeaderDoc::introductionName = "Introduction";

    # /*!
    #     @abstract
    #         Storage for the <code>--auto-availability</code> flag.
    #     @discussion
    #         By default, HeaderDoc ignores <code>#if</code>
    #         directives with Apple-provided availability
    #         macros.  This flag enables that support by
    #         setting this value to 1.
    #  */
    $HeaderDoc::auto_availability = 0;

    # /*!
    #     @abstract
    #         Enable internal documentation.
    #     @discussion
    #         Storage for the <code>--document-internal</code> flag.
    #  */
    $HeaderDoc::document_internal = 0;

    # /*!
    #     @abstract
    #         Flags certain XML tags as illegal due to
    #         Apple-internal constraints.
    #  */
    $HeaderDoc::ExtraAppleWarnings = 0;

    # /*!
    #     @abstract
    #         Storage for the <code>-C</code> flag.
    #  */
    $HeaderDoc::ClassAsComposite = 0;

    # /*!
    #     @abstract
    #         The current access control state used and modified by the parser.
    #     @discussion
    #         This should probably be passed around through arguments, but
    #         for now, it is't.
    #  */
    $HeaderDoc::AccessControlState = "";

    # /*!
    #     @abstract
    #         Disables adding the next <code>#define</code>declaration to the
    #         C preprocessor macro set.
    #     @discussion
    #         Triggered by a <code>\@noparse</code> directive in comment.
    #         When this directive is encountered, the directive is parsed for
    #         documentation purposes, but is not added to the set of
    #         macros that affect parsing of other declarations.
    #  */
    $HeaderDoc::skipNextPDefine = 0;

    # /*!
    #     @abstract
    #         Deprecated.
    #     @discussion
    #         Storage for an old scheme to ignore junk CPP tokens at the start of line.
    #         This holds the value of the ignorePrefixes field in the config file.
    #
    #         The currently recommended way to do this is with the C preprocessor
    #         on the command line (-D FOO="") or in code.
    #  */
    %HeaderDoc::ignorePrefixes = ();

    # /*!
    #     @abstract
    #         Deprecated.
    #     @discussion
    #         Storage for an old scheme to ignore junk CPP tokens at the start of line.
    #         This holds the list of values from <code>\@ignore</code> tags.
    #
    #         The currently recommended way to do this is with the C preprocessor
    #         on the command line (-D FOO="") or in code.
    #  */
    %HeaderDoc::perHeaderIgnorePrefixes = ();


    # /*!
    #     @abstract
    #         Deprecated.
    #     @discussion
    #         Storage for an old scheme to ignore junk CPP tokens at the start of line.
    #         This holds the list of values from <code>\@ignorefuncmacro</code> tags.
    #
    #         The currently recommended way to do this is with the C preprocessor
    #         in the code itself.
    #  */
    %HeaderDoc::perHeaderIgnoreFuncMacros = ();

    # /*!
    #     @abstract
    #         A hash of macro definition states passed in on the command
    #         line that are interpreted by the macro filter engine.
    #     @discussion
    #         Legal values are:
    #
    #         <dl>
    #             <dt>  1</dt><dd>Value we want defined to a particular value
    #                            (<code>-D</code> flag specified).</dd>
    #             <dt> -1</dt><dd>Value we want to be explicitly undefined
    #                            (<code>-U</code> flag specified).</dd>
    #             <dt>  0</dt><dd>Don't care.  (Default behavior for any token.)</dd>
    #         </dl>
    #
    #         This variable is used only if <code>-D</code> or <code>-U</code> is
    #         passed on the command line (which, in turn, sets the variable
    #         {@link HeaderDoc::filter_macro_definition_state}
    #         to 1).
    #  */
    %HeaderDoc::filter_macro_definition_state = ();

    # /*!
    #     @abstract
    #         A hash of macro values passed in on the command
    #         line that are interpreted by the macro filter engine.
    #     @discussion
    #         This hash contains the actual numerical values passed in on
    #         the command line.  If no value is specified, the value
    #         defaults to 1.
    #
    #         This variable is used only if <code>-D</code> or <code>-U</code> is
    #         passed on the command line (which, in turn, sets the variable
    #         {@link HeaderDoc::filter_macro_definition_state}
    #         to 1).
    #
    #         For explicitly undefined values (<code>-U</code>), this value is
    #         unimportant and should be left blank.
    #  */
    %HeaderDoc::filter_macro_definition_value = ();

    # /*!
    #     @abstract
    #         A list of <code>#include</code> directives in the current header.
    #  */
    %HeaderDoc::perHeaderIncludes = ();

    # /*!
    #     @abstract
    #         A list of line numbers where CPP <code>#include</code> and
    #         <code>#if</code> directives appear.
    #     @discussion
    #         Used for determining which C preprocessor directives should be
    #         applied to a given block of code.
    #  */
    %HeaderDoc::perHeaderRanges = ();

    # /*!
    #     @abstract
    #         Enables/disables "outer name" type handling (<code>-O</code> flag).
    #     @discussion
    #         By default, HeaderDoc documents all names for type declarations.
    #         This flag disables emission of documentation for inner
    #         (structure, enumeration, or union) tag names declared inline.
    #
    #         For example, <code>typdef struct a { ... } b;</code> has two
    #         names by default: <code>a</code> and <code>b</code>.  With the
    #         <code>-O</code> flag, only the outer name (<code>b</code>) is
    #         emitted in the documentation.
    #  */
    $HeaderDoc::outerNamesOnly = 0;             # storage for -O flag.

    # /*!
    #     @abstract
    #         Used for quickly looking up names of
    #         fields in data types by the data type name
    #         and field name.
    #  */
    %HeaderDoc::namerefs = ();

    # /*!
    #     @abstract
    #         A counter used for generating UUIDs for inherited content.
    #  */
    $HeaderDoc::uniquenumber = 0;

    # $HeaderDoc::counter = 0;                    # Now unused. @@@

    # /*!
    #     @abstract
    #         The configuration file path specified by the <code>-c</code>flag.
    #  */
    $HeaderDoc::specified_config_file = "";

    # /*!
    #     @abstract
    #         Storage for the <code>-F</code> flag.
    #     @discussion
    #         Note that this variable may get removed eventually in favor
    #         of a more flexible output style variable.
    #  */
    $HeaderDoc::use_iframes = 1;

    use lib '/Library/Perl/TechPubs';           # Apple configuration workaround
    use lib '/AppleInternal/Library/Perl';      # Apple configuration workaround

    my %options = ();
    # $lookupTableDirName = "LookupTables";       # Legacy cruft.
    # $functionFilename = "functions.tab";;       # Legacy cruft.
    # $typesFilename = "types.tab";               # Legacy cruft.
    # $enumsFilename = "enumConstants.tab";       # Legacy cruft.

    # /*!
    #     @abstract
    #         Sorts content in the right side (content) pane by group.
    #  */
    $HeaderDoc::groupright = 0;

    # /*!
    #     @abstract
    #         Enables support for JavaDoc-style comments (comments with a second
    #         asterisk at the start of the comment instead of an exclamation point).
    #  */
    $HeaderDoc::parse_javadoc = 0;

    # /*!
    #     @abstract
    #         Enables strict parameter taggint warnings (<code>-t</code> flag).
    #  */
    $HeaderDoc::force_parameter_tagging = 0;

    # /*!
    #     @abstract
    #         Controls whether to include the body of macros or not.
    #     @discussion
    #         By default, HeaderDoc omits the body of macro definitions
    #         in the documentation.  You can pass the <code>-i</code>
    #         flag to include macro bodies in the output.  Doing so
    #         sets this variable to zero.  Omitting the flag sets this
    #         variable to 1.
    #  */
    $HeaderDoc::truncate_inline = 0;

    # /*!
    #     @abstract
    #         Deprecated.
    #     @discussion
    #         Storage for the <code>-b</code> flag.  This flag uses
    #         parser functionality that is no longer maintained.
    #         It may or may not work, and you should not count on
    #         it to continue working.  It was primarily intended
    #         as a way of checking parser behavior when the
    #         colorizer code was nascent.
    #  */
    $HeaderDoc::dumb_as_dirt = 1;

    # /*!
    #     @abstract
    #         Disables link requests in declarations (<code>-l</code> flag).
    #     @discussion
    #         By default, HeaderDoc inserts link requests into the
    #         declarations in HTML output.  If you have no interest
    #         in declaration linking, you can turn this off by
    #         passing the <code>-l</code> flag on the command line.
    #         Doing so clears this variable to 0.
    #  */
    $HeaderDoc::add_link_requests = 1;

    # /*!
    #     @abstract
    #         Tells HeaderDoc to suppress local variable documentation.
    #     @discussion
    #         By default, a local variable (an <code>\@var</code> tag
    #         inside a function or method discussion) is emitted on the
    #         output.  This is desirable for internal documentation
    #         purposes, but is undesirable for public documentation
    #         purposes.
    #
    #         Passing the <code>-L</code> flag on the command line sets this
    #         flag and suppresses the emission of documentation on these
    #         local variables.
    #  */
    $HeaderDoc::suppress_local_variables = 0;

    # /*!
    #     @abstract
    #         Enables emission of various stylesheet bits.
    #     @discussion
    #         Set if certain keys appear (with content) in the config file.
    #  */
    $HeaderDoc::use_styles = 0;

    # /*!
    #     @abstract
    #         Set to true when HeaderDoc should suppress warnings about
    #         API reference conficts, object name changes, and so on.
    #     @discussion
    #         This is set to 1 when HeaderDoc is deliberately making a
    #         change to an object that would normally trigger a warning.
    #         Do not set this indiscriminately, as doing so can mask
    #         actual errors in source content that result in incorrect
    #         output.
    #  */
    $HeaderDoc::ignore_apiuid_errors = 0;

    # /*!
    #     @abstract
    #         Storage for the <code>tocformat</code> value from the config file.
    #  */
    $HeaderDoc::explicit_toc_format = undef;

    # /*!
    #     @abstract
    #         Storage for the contents of the file described in the
    #         <code>styleSheetExtrasFile</code> field of the config file.
    #  */
    $HeaderDoc::styleSheetExtras = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>externalStyleSheets</code> value from the config file.
    #  */
    $HeaderDoc::externalStyleSheets = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>externalTOCStyleSheets</code> value from the config file.
    #  */
    $HeaderDoc::externalTOCStyleSheets = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>styleImports</code> value from the config file.
    #  */
    $HeaderDoc::styleImports = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>tocStyleImports</code> value from the config file.
    #  */
    $HeaderDoc::tocStyleImports = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>-C</code> flag.  Set to <code>-1</code> if
    #         flag is set.
    #     @discussion
    #         This flag is only supported when combined with the older
    #         TOC formats (<code>-F</code> flag).
    #  */
    $HeaderDoc::flagDashC = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>-u</code> (unsorted) flag.
    #     @discussion
    #         Set to <code>0</code> if flag is set, else 1.
    #  */
    $HeaderDoc::sort_entries = undef;

    # /*!
    #     @abstract
    #         Storage for the <code>-F</code> flag (legacy frames output mode).
    #  */
    $HeaderDoc::flagDashF = undef;

    # /*!
    #     @abstract
    #         Maximum line length for wrapping declarations.
    #     @discussion
    #         You can override this with the <code>wrapAtColumn</code>
    #         field in the configuration file.
    #  */
    $HeaderDoc::maxDecLen = 60; # Wrap functions, etc. if declaration longer than this length

    # /*!
    #     @abstract
    #         Storage for the <code>superclassName</code> value from the config file.
    #  */
    $HeaderDoc::superclassName = "Superclass";

    # /*!
    #     @abstract
    #         Storage for the <code>suppressDefaultJavaScript</code> value from the config file.
    #  */
    $HeaderDoc::suppressDefaultJavaScript = 0;

    # /*!
    #     @abstract
    #         Storage for the <code>suppressDefaultStyles</code> value from the config file.
    #  */
    $HeaderDoc::suppressDefaultStyles = 0;

    if ($^O =~ /MacOS/io) {
		$pathSeparator = ":";
		$isMacOS = 1;
		#$Bin seems to return a colon after the path on certain versions of MacPerl
		#if it's there we take it out. If not, leave it be
		#WD-rpw 05/09/02
		($uninstalledModulesPath = $FindBin::Bin) =~ s/([^:]*):$/$1/o;
    } else {
		$pathSeparator = "/";
		$isMacOS = 0;
    }
    $uninstalledModulesPath = "$FindBin::Bin"."$pathSeparator"."Modules";
    $devtoolsModulesPath = "$FindBin::Bin"."$pathSeparator".".."."$pathSeparator"."share"."$pathSeparator"."headerdoc"."$pathSeparator"."Modules";
	
    foreach (qw(Mac::Files)) {
	    $MOD_AVAIL{$_} = eval "use $_; 1";
    }

    # /*!
    #     @abstract
    #         Deprecated.
    #     @discussion
    #         Twig isn't installed by default in Mac OS X.  This is used in a
    #         feature that never got implemented---specifically, parsing
    #         modified HeaderDoc XML output and updating the HeaderDoc
    #         comments in the headers to allow round-tripping HeaderDoc markup
    #         through XML editor tools.  (The need for this functionality
    #         never materialized.  Also, in hindsight, a more lightweight,
    #         and more commonly installed XML parser API would also be better.)
    #  */
    $HeaderDoc::twig_available = 0;
    foreach my $path (@INC) {
	# print STDERR "$path\n";
	my $name = $path.$pathSeparator."XML".$pathSeparator."Twig.pm";
	# print STDERR "NAME: $name\n";
	if (-f $name) {
		$HeaderDoc::twig_available = 1;
	}
    }

    # /*!
    #     @abstract
    #         Indicates whether the FreezeThaw Perl module is available.
    #     @discussion
    #         Not all Mac OS X versions have this.  It's in 10.5 and later.
    #         For backwards compatibility, this code does a check here and
    #         doesn't allow the test code (-T flag) to run if it isn't
    #         available.
    #  */
    $HeaderDoc::FreezeThaw_available = 0;
    foreach my $path (@INC) {
	# print STDERR "$path\n";
	my $name = $path.$pathSeparator."FreezeThaw.pm";
	# print STDERR "NAME: $name\n";
	if (-f $name) {
		$HeaderDoc::FreezeThaw_available = 1;
	}
    }
}

    use lib $uninstalledModulesPath;
    use lib $devtoolsModulesPath;

    use HeaderDoc::Utilities qw(linesFromFile getLangAndSubLangFromFilename dumpCaches stripLeading);
    use HeaderDoc::Utilities qw(processTopLevel);
    use locale;

    # if ($HeaderDoc::twig_available) {
	# require HeaderDoc::Regen;
    # }

    # &getopts("CD@EFHLM:NOPQST:U@Xabc:de:fghijlmno:pqrstuvw:x", \%options);

    Getopt::Long::Configure ("bundling", "no_ignore_case_always");
    my $result = GetOptions(
				"class-as-composite|C" => \$options{C},
				"defined|D=s@" => \$options{D},
				"process-everything|E" => \$options{E},
				"old-style-frames|F" => \$options{F},
				"insert-header|H" => \$options{H},
				"suppress-local-variables|L" => \$options{L},
				"man-section|M=s" => \$options{M},
				"ignore-all-names|N" => \$options{N},
				"outer-names-only|O" => \$options{O},
				"pipe-output|P" => \$options{P},
				"paranoid|Q" => \$options{Q},
				"merge-superclass-docs|S" => \$options{S},
				"test|T=s" => \$options{T},
				"undefined|U=s@" => \$options{U},
				"xml-output|X" => \$options{X},
				"align-columns|a" => \$options{a},
				"basic-processing-only|b" => \$options{b},
				"config-file|c=s" => \$options{c},
				"debugging|d" => \$options{d},
				"exclude-list-file|e=s" => \$options{e},
				"function-list-output|f" => \$options{f},
				"group-right-side|g" => \$options{g},
				# "write-control-file|h" => \$options{h},
				"truncate-function-like-macros|i" => \$options{i},
				"allow-javadoc-syntax|j" => \$options{j},
				"no-link-requests|l" => \$options{l},
				"man-page-output|m" => \$options{m},
				"ignore-apiowner-names|n" => \$options{n},
				"output-directory|o=s" => \$options{o},
				"enable-cpp|p" => \$options{p},
				"quiet|q" => \$options{q},
				# "regenerate|r" => \$options{r},
				"strip|s" => \$options{s},
				"enforce-strict-tagging|t" => \$options{t},
				"unsorted|u" => \$options{u},
				"version|v" => \$options{v},
				"python-tab-width|w=i" => \$options{w},
				"doxytags|x" => \$options{x},
				"tocformat=s" => \$options{tocformat},
				"auto-availability" => \$options{auto_availability},
				"document-internal" => \$HeaderDoc::document_internal,
				"apple" => \$options{apple}
	);

	# print STDERR "-d: \"".$options{d}."\"\n";
	# print STDERR "-D: \"".$options{D}."\"\n";

	if (!$result) {
		die("Invalid options\n");
	}

    # Moved to top so it can be used to get info about other flags..
    if ($options{d}) {
            print STDERR "\tDebugging on...\n\n";
            $debugging = 1;
    }
    if ($options{tocformat}) {
	# print "TF: $options{tocformat}\n";
	$HeaderDoc::explicit_toc_format = $options{tocformat};
    }
    if ($options{apple}) {
	$options{auto_availability} = 1;
	$options{H} = 1;
	$options{j} = 1;
	$options{n} = 1;
	$options{p} = 1;
	$options{O} = 1;
	$options{Q} = 1;

	$HeaderDoc::ExtraAppleWarnings = 1;
    }
    if ($options{auto_availability}) {
	$HeaderDoc::auto_availability = 1;
    }
    if ($options{q}) {
	$quietLevel = "1";
    } else {
	$quietLevel = "0";
    }
    if ($options{Q}) {
	$HeaderDoc::enableParanoidWarnings = 1;
    } else {
	# /*!
	#     @abstract
	#         Storage for the <code>-Q</code> (disquiet) flag.
	#  */
	$HeaderDoc::enableParanoidWarnings = 0;
    }
    if ($options{v}) {
    	# print STDERR "Getting version information for all modules.  Please wait...\n";
	$printVersion = 1;
    }

    if ($options{r}) {
# print STDERR "TWIG? $HeaderDoc::twig_available\n";
	if ($HeaderDoc::twig_available) {
		print STDERR "Regenerating headers.\n";
	} else {
		warn "***********************************************************************\n";
		warn "*    Headerdoc comment regeneration from XML requires XML::Parser     *\n";
		warn "*             and XML::Twig, available from CPAN.  Visit              *\n";
		warn "*                                                                     *\n";
		warn "*                         http://www.cpan.org                         *\n";
		warn "*                                                                     *\n";
		warn "*                        for more information.                        *\n";
		warn "***********************************************************************\n";
		exit -1;
	}
	$regenerate_headers = 1;
    } else {
	$regenerate_headers = 0;
    }

    if ($options{F}) {
	# Use old-style frames.
	$HeaderDoc::use_iframes = 0;
	$HeaderDoc::flagDashF = 1; # Set.
    }

    if ($options{S}) {
	# /*!
	#     @abstract
	#         Storage for the <code>-S</code> flag.
	#  */
	$HeaderDoc::IncludeSuper = 1;
    } else {
	$HeaderDoc::IncludeSuper = 0;
    }
    if ($options{C} || $HeaderDoc::use_iframes) {
	$HeaderDoc::ClassAsComposite = 1;
    } else {
	$HeaderDoc::flagDashC = -1; # Unset.
	$HeaderDoc::ClassAsComposite = 0;
    }
    if ($options{E}) {
	# /*!
	#     @abstract
	#         Storage for the <code>-E</code> flag.
	#  */
	$HeaderDoc::process_everything = 1;
    } else {
	$HeaderDoc::process_everything = 0;
    }

    if ($options{D}) {
	# print STDERR "OPTIONS D: ".$options{D}."\n";
	# /*!
	#     @abstract
	#         Set if any <code>-D</code> or <code>-U</code>
        #         flags are passed on the command line.
        #     @discussion
        #         This enables and disables the C preprocessor
        #         filtering portions.
	#  */
	$HeaderDoc::enable_macro_filter = 1;
	foreach my $symbol (@{$options{D}}) {
		print STDERR "-D $symbol\n" if ($debugging);
		if ($symbol =~ /=/) {
			my @parts = split(/=/, $symbol);
			$HeaderDoc::filter_macro_definition_state{$parts[0]} = 1;
			$HeaderDoc::filter_macro_definition_value{$parts[0]} = $parts[1];
		} else {
			$HeaderDoc::filter_macro_definition_state{$symbol} = 1;
			$HeaderDoc::filter_macro_definition_value{$symbol} = 1;
		}
	}
    }
    if ($options{U}) {
	# print STDERR "OPTIONS U: ".$options{U}."\n";
	$HeaderDoc::enable_macro_filter = 1;
	foreach my $symbol (@{$options{U}}) {
		print STDERR "-U $symbol\n" if ($debugging);
		if ($symbol =~ /=/) {
			my @parts = split(/=/, $symbol);
			$HeaderDoc::filter_macro_definition_state{$parts[0]} = -1;
			$HeaderDoc::filter_macro_definition_value{$symbol} = "";
		} else {
			$HeaderDoc::filter_macro_definition_state{$symbol} = -1;
			$HeaderDoc::filter_macro_definition_value{$symbol} = "";
		}
	}
    }

    if ($options{a}) {
	# Align columns
	# /*!
	#     @abstract
	#         Storage for the <code>-a</code> flag.
	#  */
	$HeaderDoc::align_columns = 1;
    } else {
	$HeaderDoc::align_columns = 0;
    }

    if ($options{b}) {
	# "basic" mode - turn off some smart processing
	$HeaderDoc::dumb_as_dirt = 1;
    } else {
	$HeaderDoc::dumb_as_dirt = 0;
    }

    if ($options{c}) {
	# Use alternate config file.
	$HeaderDoc::specified_config_file = $options{c};
    }

    if ($options{g}) {
	# Group right side content by group.
	$HeaderDoc::groupright = 1;
    }

    if ($options{j}) {
	# Allow JavaDoc syntax in C.
	$HeaderDoc::parse_javadoc = 1;
    }

    if ($options{p}) {
	$HeaderDoc::enable_cpp = 1;
    } else {
	# /*!
	#     @abstract
	#         Storage for the <code>-p</code> or
	#         <code>--enable-cpp</code> flag.
	#  */
	$HeaderDoc::enable_cpp = 0;
    }

    # Ignore names specified in @header, @class, @category, and other
    # API owner tags
    if ($options{N}) {
	$HeaderDoc::ignore_apiowner_names = 2;
    } elsif ($options{n}) {
	$HeaderDoc::ignore_apiowner_names = 1;
    } else {
	# /*!
	#     @abstract
	#         Storage for the <code>-n</code> and <code>-N</code> flags.
	#  */
	$HeaderDoc::ignore_apiowner_names = 0;
    }

    if ($options{l}) {
	# "linkless" mode - don't add link requests
	$HeaderDoc::add_link_requests = 0;
    } else {
	$HeaderDoc::add_link_requests = 1;
    }

    if ($options{L}) {
	# Suppress local variables.
	$HeaderDoc::suppress_local_variables = 1;
    } else {
	$HeaderDoc::suppress_local_variables = 0;
    }

    if ($options{M}) {
	$HeaderDoc::man_section = $options{M};
    } else {
	$HeaderDoc::man_section = 3;
    }

    if ($options{m}) {
	# man page output mode - implies xml
	$man_output = 1;
	$xml_output = 1;
    } else {
	$man_output = 0;
    }

    if ($options{e}) {
	my $exclude_list_file = $options{e};

	print STDERR "EXCLUDE LIST FILE is \"$exclude_list_file\".  CWD is ".cwd()."\n" if (!$quietLevel);
	my ($encoding, $linesref) = linesFromFile($exclude_list_file, 0);
	my @templines = @{$linesref};
	@HeaderDoc::exclude_patterns = ();
	foreach my $line (@templines) {
		$line =~ s/\n//g;
		push(@HeaderDoc::exclude_patterns, $line);
	}
    } else {
	@HeaderDoc::exclude_patterns = ();
    }

    if ($options{s}) {
	$headerdoc_strip = 1;
    } else {
	$headerdoc_strip = 0;
    }

    if ($options{i}) {
	$HeaderDoc::truncate_inline = 0;
    } else {
	$HeaderDoc::truncate_inline = 1;
    }

    # if ($options{h}) {
	# $write_control_file = "1";
    # } else {
	# $write_control_file = "0";
    # }
    if ($options{u}) {
	$HeaderDoc::sort_entries = 0;
    } else {
	$HeaderDoc::sort_entries = 1;
    }
    if ($options{H}) {
	$HeaderDoc::insert_header = 1;
    } else {
	$HeaderDoc::insert_header = 0;
    }
    if ($options{w}) {
	$HeaderDoc::python_tab_spaces = $options{w};
	if (!$quietLevel) {
		print STDERR "Python tab spaces set to ".$HeaderDoc::python_tab_spaces.".\n";
	}
    }
    if ($options{t}) {
	if (!$quietLevel) {
		print STDERR "Forcing strict parameter tagging.\n";
	}
	$HeaderDoc::force_parameter_tagging = 1;
    }
    if ($options{T}) {
	if (!$HeaderDoc::FreezeThaw_available) {
		warn "FreezeThaw Perl module not found in library path.  Please\n";
		warn "install FreezeThaw and try again.\n";
		exit -1;
	}
	$HeaderDoc::testmode = $options{T};
    }
    if ($options{O}) {
	$HeaderDoc::outerNamesOnly = 1;
    } else {
	$HeaderDoc::outerNamesOnly = 0;
    }

    if ($options{o}) {
	if ($use_stdout) {
		die("-o and -P are mutually exclusive.");
	}
        $specifiedOutputDir = $options{o};
        if (! -e $specifiedOutputDir)  {
            unless (mkdir ("$specifiedOutputDir", 0777)) {
                die "Error: $specifiedOutputDir does not exist. Exiting. \n$!\n";
            }
        } elsif (! -d $specifiedOutputDir) {
            die "Error: $specifiedOutputDir is not a directory. Exiting.\n$!\n";
        } elsif (! -w $specifiedOutputDir) {
            die "Error: Output directory $specifiedOutputDir is not writable. Exiting.\n$!\n";
        }
		if ($quietLevel eq "0") {
			print STDERR "\nDocumentation will be written to $specifiedOutputDir\n";
		}
    }
    my $scriptDir = cwd();
    # $lookupTableDir = "$scriptDir$pathSeparator$lookupTableDirName";
    # if (($options{x}) || ($testingExport)) {
        # if ((-e "$lookupTableDir$pathSeparator$functionFilename") && (-e "$lookupTableDir$pathSeparator$typesFilename")) {
                # print STDERR "\nWill write database files to an Export directory within each top-level HTML directory.\n\n";
                # $export = 1;
        # } else {
                # print STDERR "\nLookup table files not available. Cannot export data.\n";
            # $export = 0;
                # $testingExport = 0;
        # }
    # }

    $use_stdout = 0;
    if (!$headerdoc_strip && !$man_output) {
      if ($options{X}) {
	print STDERR "XML output mode.\n" if ($quietLevel eq "0");
	$xml_output = 1;
      } elsif ($options{x}) {
	print STDERR "Doxygen tagfile output mode.\n" if ($quietLevel eq "0");
	$doxytag_output = 1;
	if ($use_stdout) {
		die("-o and -x are mutually exclusive\n");
	}
      } elsif ($options{f}) {
	print STDERR "FUNCTION LIST output mode.\n" if ($quietLevel eq "0");
	$function_list_output = 1;
	$use_stdout = 1;
      } else {
	print STDERR "HTML output mode.\n" if ($quietLevel eq "0");
	$xml_output = 0;
      }
    }
# print STDERR "output mode is $xml_output\n";
    # Pipe mode (single file only)
    if ($options{P} || $use_stdout) {
	$use_stdout = 1;
	if ($doxytag_output) {
		die("-P and -x are mutually exclusive\n");
	}
	if (!$xml_output && !$function_list_output) {
		printf STDERR "XML output (-X) implicitly enabled by -P flag.\n";
		$xml_output = 1;
	}
	if (!$HeaderDoc::ClassAsComposite) {
		printf STDERR "ClassAsComposite (-C) implicitly enabled by -P flag.\n";
		$HeaderDoc::ClassAsComposite = 1;
	}
    }


    if (!$HeaderDoc::testmode && !$printVersion) {
        print STDERR "Will process one or more individual files.\n" if ($debugging);
        foreach my $singleFile (@ARGV) {
	    if (-d $singleFile) {
		print STDERR "DIR $singleFile\n";
        	my $inputDir = $singleFile;
        	if ($inputDir =~ /$pathSeparator$/) {
			$inputDir =~ s|(.*)$pathSeparator$|$1|; # get rid of trailing slash, if any
		}		
		if ( -f $inputDir.$pathSeparator."skiplist") {
			my ($encoding, $arrayref) = linesFromFile($inputDir."/skiplist", 0);
			my @skiplist = @{$arrayref};
			foreach my $skipfile (@skiplist) {
				if ($skipfile !~ /^\s*\#/ && $skipfile =~ /\S/) {
					$skipfile =~ s/^\s+//sg;
					$skipfile =~ s/\s+$//sg;
					$HeaderDoc::skiplist .= $skipfile."\n";
					print STDERR "Will skip $skipfile\n" if ($debugging);
				}
			}
			# $HeaderDoc::skiplist =~ s/\s/\@/g;
		}
		if ($^O =~ /MacOS/io) {
			find(\&getHeaders, $inputDir);
		} else {
			&find({wanted => \&getHeaders, follow => 1, follow_skip => 2}, $inputDir);
		}
            } elsif (-f $singleFile) {
		if ($singleFile =~ /\.(cpp|c|C|h|m|M|i|hdoc|php|php\d|class|pas|p|java|j|jav|jsp|js|jscript|html|shtml|dhtml|htm|shtm|dhtm|pl|pm|bsh|csh|ksh|sh|defs|idl|conf|rb|rbx|rhtml|ruby|py|pyw|applescript|scpt|tcl)$/o) {
                    push(@inputFiles, $singleFile);
		} else {
		    warn "File $singleFile is not of a known header or source code file type\n";
		}
            } else {
		    warn "HeaderDoc: file/directory not found: $singleFile\n";
	    }
      }
      if ($debugging) {
	foreach my $if (@inputFiles) {
		print STDERR "FILE: $if\n";
	}
      }
      unless (@inputFiles) {
        print STDERR "No valid input files specified. \n\n";
        if ($isMacOS) {
            die "\tTo use HeaderDoc, drop a header file or folder of header files on this application.\n\n";
            } else {
                    die "\tUsage: headerdoc2html [-dq] [-o <output directory>] <input file(s) or directory>.\n\n";
            }
      }
    }

    # /*!
    #     @abstract
    #         Search helper for Doxygen-style tag files.
    #     @discussion
    #         During processing, each source file results in a
    #         corresponding Doxygen-style tag file (if the -x
    #         flag is specified).  This search helper is used
    #         in tracking those files down for merging at the
    #         end of processing.
    #   */
    sub getDoxyTagFiles {
        my $filePath = $File::Find::name;
        my $fileName = $_;

        
	if ($fileName =~ /\.doxytagtemp$/o) {
		push(@doxyTagFiles, $filePath);
	}
    }

    # /*!
    #     @abstract
    #         Search helper for header files.
    #     @discussion
    #         This is used for comparing names against the
    #         list of valid file extensions to see if they
    #         should be processed by HeaderDoc.
    #  */
    sub getHeaders {
        my $filePath = $File::Find::name;
        my $fileName = $_;

        
	if ($fileName =~ /\.(cpp|c|C|h|m|M|i|hdoc|php|php\d|class|pas|p|java|j|jav|jsp|js|jscript|html|shtml|dhtml|htm|shtm|dhtm|pl|pm|bsh|csh|ksh|sh|defs|idl|conf|rb|rbx|rhtml|ruby|py|pyw|applescript|scpt|tcl)$/o) {
	    # Skip lists use exact filename matches and must be in the
	    # the base directory being processed.  Exclude list is
	    # preferred, uses regular expressions, and can live in
	    # any file.  The filename of the exclude list is specified
	    # with the -e command-line flag.
	    if ($HeaderDoc::skiplist =~ /^\s*\Q$fileName\E\s*$/m) {
		print STDERR "skipped $filePath\n";
	    } elsif (in_exclude_list($filePath)) {
		print STDERR "skipped $filePath (found in exclude list)\n";
	    } else {
        	push(@inputFiles, $filePath);
		# print STDERR "will process $filePath ($fileName)\n";
		# print STDERR "SKIPLIST: ".$HeaderDoc::skiplist."\n";
	    }
        }
    }

    # /*!
    #     @abstract
    #         Checks the exclude list for filenames.
    #     @discussion
    #         When you specify an exclude list (the -e flag),
    #         HeaderDoc reads that file for a list of expressions
    #         to match.  Every time HeaderDoc opens a header file,
    #         source file, or other file to process, it checks it
    #         against that list by calling this function.
    #  */
    sub in_exclude_list($)
    {
	my $filepath = shift;
	foreach my $pattern (@HeaderDoc::exclude_patterns) {
		if ($pattern =~ /\S/) {
			# print STDERR "Checking $filepath against pattern \"$pattern\".\n";
			if ($filepath =~ $pattern) {
				return 1;
			}
		}
	}
	return 0;
    }

# $HeaderDoc::curParserState = undef; # No longer used.

use strict;
use File::Copy;
use File::Basename;
use lib $uninstalledModulesPath;

# use Devel::Peek;

# Classes and other modules specific to HeaderDoc
# use HeaderDoc::DBLookup;
use HeaderDoc::Utilities qw(linesFromFile emptyHDok addAvailabilityMacro);
use HeaderDoc::Utilities qw(findRelativePath safeName
                            printArray linesFromFile printHash
                            updateHashFromConfigFiles getHashFromConfigFile
                            parseTokens
                            stringToFields warnHDComment validTag
                            filterHeaderDocComment processHeaderComment
                            getLineArrays resolveLink objectForUID getAbsPath
                            allow_everything getAvailabilityMacros);
use HeaderDoc::BlockParse qw(blockParseOutside getAndClearCPPHash cpp_add_cl);
use HeaderDoc::Header;
use HeaderDoc::CPPClass;
use HeaderDoc::ObjCClass;
use HeaderDoc::ObjCProtocol;
use HeaderDoc::ObjCCategory;
use HeaderDoc::Function;
use HeaderDoc::Method;
use HeaderDoc::Typedef;
use HeaderDoc::Struct;
use HeaderDoc::Constant;
use HeaderDoc::Var;
use HeaderDoc::PDefine;
use HeaderDoc::Enum;
use HeaderDoc::Group;
use HeaderDoc::MinorAPIElement;
use HeaderDoc::HashObject;
use HeaderDoc::ParseTree;
use HeaderDoc::ParserState;
use HeaderDoc::IncludeHash;
use HeaderDoc::Dependency;
use HeaderDoc::LineRange;
use HeaderDoc::AvailHelper;
use HeaderDoc::Test;
use HeaderDoc::MacroFilter;


# Determine where the modules really came from.
# /*! 
#     @abstract
#         The location from which the HeaderDoc modules
#         were loaded.
#     @discussion
#         This variable is populated automatically.
#  */
$HeaderDoc::modulesPath = $INC{'HeaderDoc/ParseTree.pm'};
$HeaderDoc::modulesPath =~ s/ParseTree.pm$//so;

# Determine the location for test suite files.
# If we're not in /System/Library/Perl or similar, then
# we're loading from the source folder itself.

# /*!
#     @abstract
#         The HeaderDoc test suite location.
#     @discussion
#         If HeaderDoc is being run out of a checked out copy.
#         this is the testsuite directory in that checked out
#         copy.  Otherwise, this uses the installed path,
#         <code>/usr/share/headerdoc/testsuite</code>
#  */
$HeaderDoc::testdir = $HeaderDoc::modulesPath."/../../testsuite";
if ( ! -d $HeaderDoc::testdir ) {
	$HeaderDoc::testdir = "/usr/share/headerdoc/testsuite";
}

# print STDERR "Module path is ".$HeaderDoc::modulesPath."\n";
# foreach my $key (%INC) {
	# print STDERR "KEY: $key\nVALUE: ".$INC{$key}."\n";
# }

# -v flag.
if ($printVersion) {
	################ Version Info ##############################
	&printVersionInfo();
	exit $HeaderDoc::exitstatus;
}

# -T flag.
if ($HeaderDoc::testmode) {
	print STDERR "Running tests.\n";
	if ($HeaderDoc::testmode eq "create") {
		newtest();
	} else {
		runtests($HeaderDoc::testmode, \@ARGV);
	}
	exit $HeaderDoc::exitstatus;
}


################ Setup from Configuration File #######################
my $localConfigFileName = "headerDoc2HTML.config";
my $preferencesConfigFileName = "com.apple.headerDoc2HTML.config";

my $homeDir;
my $usersPreferencesPath;
my $systemPreferencesPath;
my $usersAppSupportPath;
my $systemAppSupportPath;

# /*!
#     @abstract
#         A reference to a hash of non-standard tags to allow.
#     @discussion
#         Normally, HeaderDoc converts unknown tags to text.
#         You can add custom tags to the list of allowed tags
#         by listing them in the <code>customTags</code> field
#         in the HeaderDoc config file.  The hash reference
#         in this variable lists those tags.
#  */
$HeaderDoc::custom_tags = undef;

#added WD-rpw 07/30/01 to support running on MacPerl
#modified WD-rpw 07/01/02 to support the MacPerl 5.8.0
if ($^O =~ /MacOS/io) {
	# Legacy support for MacPerl in Mac OS 9
	eval 
	{
		require "FindFolder.pl";
		$homeDir = MacPerl::FindFolder("D");	#D = Desktop. Arbitrary place to put things
		$usersPreferencesPath = MacPerl::FindFolder("P");	#P = Preferences
		$usersAppSupportPath = MacPerl::FindFolder("P");	#P = Preferences
	};
	if ($@) {
		import Mac::Files;
		$homeDir = Mac::Files::FindFolder(kOnSystemDisk(), kDesktopFolderType());
		$usersPreferencesPath = Mac::Files::FindFolder(kOnSystemDisk(), kPreferencesFolderType());
		$usersAppSupportPath = Mac::Files::FindFolder(kOnSystemDisk(), kPreferencesFolderType());
	}
	$systemPreferencesPath = $usersPreferencesPath;
	$systemAppSupportPath = $usersAppSupportPath;
} else {
	$homeDir = (getpwuid($<))[7];
	$usersPreferencesPath = $homeDir.$pathSeparator."Library".$pathSeparator."Preferences";
	$usersAppSupportPath = $homeDir.$pathSeparator."Library".$pathSeparator."Application Support".$pathSeparator."Apple".$pathSeparator."HeaderDoc";
	$systemPreferencesPath = "/Library/Preferences";
	$systemAppSupportPath = "/Library/Application Support/Apple/HeaderDoc";
}
my $devtoolsPreferencesPath = "$FindBin::Bin"."$pathSeparator".".."."$pathSeparator"."share"."$pathSeparator"."headerdoc"."$pathSeparator"."conf";

# The order of files in this array determines the order that the config files will be read
# If there are multiple config files that declare a value for the same key, the last one read wins
my $CWD = cwd();
my @configFiles = ($devtoolsPreferencesPath.$pathSeparator.$preferencesConfigFileName, $systemPreferencesPath.$pathSeparator.$preferencesConfigFileName, $usersPreferencesPath.$pathSeparator.$preferencesConfigFileName, $Bin.$pathSeparator.$localConfigFileName, $CWD.$pathSeparator.$localConfigFileName);

if (length($HeaderDoc::specified_config_file)) {
	@configFiles = ();
	push(@configFiles, $HeaderDoc::specified_config_file);
}

# default configuration, which will be modified by assignments found in config files.
my %config = (
    ignorePrefixes => "",
    externalStyleSheets => "",
    externalTOCStyleSheets => "",
    tocStyleImports => "",
    styleSheetExtrasFile => "",
    styleImports => "",
    TOCFormat => "default",
    # appleTOC intentionally not defined.
    classAsComposite => $HeaderDoc::ClassAsComposite,
    copyrightOwner => "",
    defaultFrameName => "index.html",
    compositePageName => "CompositePage.html",
    masterTOCName => "MasterTOC.html",
    apiUIDPrefix => "apple_ref",
    htmlHeader => "",
    htmlFooter => "",
    htmlHeaderFile => "",
    htmlFooterFile => "",
    dateFormat => "",
    textStyle => "",
    commentStyle => "",
    preprocessorStyle => "",
    funcNameStyle => "",
    stringStyle => "",
    charStyle => "",
    numberStyle => "",
    keywordStyle => "",
    typeStyle => "",
    paramStyle => "",
    varStyle => "",
    templateStyle => "",
    wrapAtColumn => "",
    introductionName => "Introduction",
    superclassName => "Superclass",
    IDLLanguage => "idl",
    cCompiler => "/usr/bin/gcc"
);

# print "CONFIG FILES: @{[ @configFiles ]}\n";
%config = &updateHashFromConfigFiles(\%config,\@configFiles);

# Read the static availability macro text from the modules folder.
if ( -f $HeaderDoc::modulesPath."../../Availability.list") {
	getAvailabilityMacros($HeaderDoc::modulesPath."../../Availability.list", 1);
} else {
	getAvailabilityMacros($HeaderDoc::modulesPath."Availability.list", $quietLevel);
}

if ($config{"ignorePrefixes"}) {
    my $localDebug = 0;
    my @prefixlist = split(/\|/, $config{"ignorePrefixes"});
    foreach my $prefix (@prefixlist) {
	print STDERR "ignoring $prefix\n" if ($localDebug);
	# push(@HeaderDoc::ignorePrefixes, $prefix);
	$prefix =~ s/^\s*//so;
	$prefix =~ s/\s*$//so;
	$HeaderDoc::ignorePrefixes{$prefix} = $prefix;
    }
}

if ($config{"customTags"}) {
    my %arr = ();
    foreach my $tag (split(/\s+/, $config{"customTags"})) {
	if (length($tag)) {
		$arr{$tag} = 1;
	}
    }
    $HeaderDoc::custom_tags = \%arr;
}


if (defined $config{bareNamesFromAPIRefs}) {
    $HeaderDoc::nameFromAPIRefReturnsOnlyName = $config{bareNamesFromAPIRefs};
}

if ($config{"wrapAtColumn"}) {
	$HeaderDoc::maxDecLen = $config{"wrapAtColumn"};
}

if ($config{"externalStyleSheets"}) {
    $HeaderDoc::externalStyleSheets = $config{"externalStyleSheets"};
    $HeaderDoc::externalStyleSheets =~ s/[\n\r]/ /sgo;
    $HeaderDoc::use_styles = 1;
}
if ($config{"externalTOCStyleSheets"}) {
    $HeaderDoc::externalTOCStyleSheets = $config{"externalTOCStyleSheets"};
    $HeaderDoc::externalTOCStyleSheets =~ s/[\n\r]/ /sgo;
    $HeaderDoc::use_styles = 1;
}
if ($config{"tocStyleImports"}) {
    $HeaderDoc::tocStyleImports = $config{"tocStyleImports"};
    $HeaderDoc::tocStyleImports =~ s/[\n\r]/ /sgo;
    $HeaderDoc::use_styles = 1;
}

# 0, 1, true, false.
if (defined $config{"suppressDefaultStyles"}) {
    if ($config{"suppressDefaultStyles"} eq "1" || 
        $config{"suppressDefaultStyles"} eq "true") {
		$HeaderDoc::suppressDefaultStyles = 1;
    } else {
		$HeaderDoc::suppressDefaultStyles = 0;
    }
}

# 0, 1, true, false.
if (defined $config{"suppressDefaultJavaScript"}) {
    if ($config{"suppressDefaultJavaScript"} eq "1" || 
        $config{"suppressDefaultJavaScript"} eq "true") {
		$HeaderDoc::suppressDefaultJavaScript = 1;
    } else {
		$HeaderDoc::suppressDefaultJavaScript = 0;
    }
}

if ($config{"idlLanguage"}) {
    $HeaderDoc::idl_language = $config{"idlLanguage"};
} elsif ($config{"IDLLanguage"}) {
    $HeaderDoc::idl_language = $config{"IDLLanguage"};
}

if ($config{"cCompiler"}) {
    $HeaderDoc::c_compiler = $config{"cCompiler"};
}

if ($config{"styleSheetExtrasFile"} ne "") {
    my $found = 0;
    my $basename = $config{"styleSheetExtrasFile"};
    my $oldRS = $/;
    $/ = undef;
    # my @extrasFiles = ($Bin.$pathSeparator.$basename, $usersPreferencesPath.$pathSeparator.$basename, $basename);
    my @extrasFiles = ($devtoolsPreferencesPath.$pathSeparator.$basename, $systemPreferencesPath.$pathSeparator.$basename, $usersPreferencesPath.$pathSeparator.$basename, $Bin.$pathSeparator.$basename, $CWD.$pathSeparator.$basename, $usersAppSupportPath.$pathSeparator.$basename, $systemAppSupportPath.$pathSeparator.$basename);
    foreach my $filename (@extrasFiles) {
	if (open(READFILE, "<$filename")) {
		$HeaderDoc::styleSheetExtras = <READFILE>;
		close(READFILE);
		$found = 1;
	}
    }
    $/ = $oldRS;
    if (!$found) {
	die("Could not find file $basename in expected locations.\n");
    }

    $HeaderDoc::styleSheetExtras =~ s/[\n\r]/ /sgo;
    $HeaderDoc::use_styles = 1;
}

if ($config{"styleImports"}) {
    $HeaderDoc::styleImports = $config{"styleImports"};
    $HeaderDoc::styleImports =~ s/[\n\r]/ /sgo;
    $HeaderDoc::use_styles = 1;
}

# printHash(%config);


if (defined $config{"appleTOC"}) {
	$HeaderDoc::newTOC = $config{"appleTOC"};
	$HeaderDoc::newTOC =~ s/\s*//;
	# print STDERR "SET NEWTOC (appleTOC) TO ".$HeaderDoc::newTOC."\n";
} else {
	if (defined $config{"TOCFormat"}) {
		setTOCFormat($config{"TOCFormat"});
		# print STDERR "SET NEWTOC (TF=".$config{"TOCFormat"}.") TO ".$HeaderDoc::newTOC."\n";
	} else {
		$HeaderDoc::newTOC = 0;
		# print STDERR "SET NEWTOC (NoTF) TO 0\n";
	}
}
if ($HeaderDoc::explicit_toc_format) {
	setTOCFormat($HeaderDoc::explicit_toc_format);
}

if ($config{"classAsComposite"}) {
	$HeaderDoc::ClassAsComposite = $config{"classAsComposite"};
	$HeaderDoc::ClassAsComposite =~ s/\s*//;
} else {
	$HeaderDoc::ClassAsComposite = 0;
}

if ($config{"copyrightOwner"}) {
    HeaderDoc::APIOwner->copyrightOwner($config{"copyrightOwner"});
}
if ($config{"defaultFrameName"}) {
    HeaderDoc::APIOwner->defaultFrameName($config{"defaultFrameName"});
}
if ($config{"compositePageName"}) {
    HeaderDoc::APIOwner->compositePageName($config{"compositePageName"});
}
if ($config{"apiUIDPrefix"}) {
    HeaderDoc::APIOwner->apiUIDPrefix($config{"apiUIDPrefix"});
}
if ($config{"htmlHeader"}) {
    HeaderDoc::APIOwner->htmlHeader($config{"htmlHeader"});
}
if ($config{"htmlFooter"}) {
    HeaderDoc::APIOwner->htmlFooter($config{"htmlFooter"});
}
my $oldRecSep = $/;
undef $/;

if ($config{"htmlHeaderFile"}) {
    my $basename = $config{"htmlHeaderFile"};
    my @htmlHeaderFiles = ($Bin.$pathSeparator.$basename, $usersPreferencesPath.$pathSeparator.$basename, $basename);
    foreach my $filename (@htmlHeaderFiles) {
	if (open(HTMLHEADERFILE, "<$filename")) {
	    my $headerString = <HTMLHEADERFILE>;
	    close(HTMLHEADERFILE);
	    # print STDERR "HEADER: $headerString";
	    HeaderDoc::APIOwner->htmlHeader($headerString);
	}
    }
}
if ($config{"htmlFooterFile"}) {
    my $basename = $config{"htmlFooterFile"};
    my @htmlFooterFiles = ($Bin.$pathSeparator.$basename, $usersPreferencesPath.$pathSeparator.$basename, $basename);
    foreach my $filename (@htmlFooterFiles) {
	if (open(HTMLFOOTERFILE, "<$filename")) {
	    my $headerString = <HTMLFOOTERFILE>;
	    close(HTMLFOOTERFILE);
	    # print STDERR "FOOTER: $headerString";
	    HeaderDoc::APIOwner->htmlFooter($headerString);
	}
    }
}
$/ = $oldRecSep;

if ($config{"dateFormat"}) {
    # /*!
    #     @abstract
    #         The date format used for date stamps.
    #     @discussion
    #         Value comes from the <code>dateFormat</code>
    #         field in the config file.
    #  */
    $HeaderDoc::datefmt = $config{"dateFormat"};
    if ($HeaderDoc::datefmt !~ /\S/) {
	$HeaderDoc::datefmt = "%B %d, %Y";
    }
} else {
    $HeaderDoc::datefmt = "%B %d, %Y";
}
HeaderDoc::APIOwner::fix_date("UTF-8");

if ($config{"textStyle"}) {
	HeaderDoc::APIOwner->setStyle("text", $config{"textStyle"});
}

if ($config{"commentStyle"}) {
	HeaderDoc::APIOwner->setStyle("comment", $config{"commentStyle"});
}

if ($config{"preprocessorStyle"}) {
	HeaderDoc::APIOwner->setStyle("preprocessor", $config{"preprocessorStyle"});
}

if ($config{"funcNameStyle"}) {
	HeaderDoc::APIOwner->setStyle("function", $config{"funcNameStyle"});
}

if ($config{"stringStyle"}) {
	HeaderDoc::APIOwner->setStyle("string", $config{"stringStyle"});
}

if ($config{"charStyle"}) {
	HeaderDoc::APIOwner->setStyle("char", $config{"charStyle"});
}

if ($config{"numberStyle"}) {
	HeaderDoc::APIOwner->setStyle("number", $config{"numberStyle"});
}

if ($config{"keywordStyle"}) {
	HeaderDoc::APIOwner->setStyle("keyword", $config{"keywordStyle"});
}

if ($config{"typeStyle"}) {
	HeaderDoc::APIOwner->setStyle("type", $config{"typeStyle"});
}

if ($config{"paramStyle"}) {
	HeaderDoc::APIOwner->setStyle("param", $config{"paramStyle"});
}

if ($config{"varStyle"}) {
	HeaderDoc::APIOwner->setStyle("var", $config{"varStyle"});
}

if ($config{"templateStyle"}) {
	HeaderDoc::APIOwner->setStyle("template", $config{"templateStyle"});
}

if ($config{"addToCustomReferenceStyle"}) {
	HeaderDoc::APIOwner->setStyle("addToCustomReference", $config{"addToCustomReferenceStyle"});
}

if ($config{"addToCustomReferenceLinkStyle"}) {
	HeaderDoc::APIOwner->setStyle("addToCustomReferenceLink", $config{"addToCustomReferenceLinkStyle"});
}

if ($config{"introductionName"}) {
	$HeaderDoc::introductionName=$config{"introductionName"};
}

if ($config{"superclassName"}) {
	$HeaderDoc::superclassName=$config{"superclassName"};
}


# ################ Exporting ##############################
# if ($export || $testingExport) {
	# HeaderDoc::DBLookup->loadUsingFolderAndFiles($lookupTableDir, $functionFilename, $typesFilename, $enumsFilename);
# }

################### States ###########################################
my $inHeader        = 0;
my $inJavaSource    = 0;
my $inShellScript   = 0;
my $inPerlScript    = 0;
my $inPHPScript     = 0;
my $inCPPHeader     = 0;
my $inOCCHeader     = 0;
my $inClass         = 0; #includes CPPClass, ObjCClass ObjCProtocol
my $inInterface     = 0;
my $inFunction      = 0;
my $inAvailabilityMacro = 0;
my $inFunctionGroup = 0;
my $inGroup         = 0;
my $inTypedef       = 0;
my $inUnknown       = 0;
my $inStruct        = 0;
my $inUnion         = 0;
my $inConstant      = 0;
my $inVar           = 0;
my $inPDefine       = 0;
my $inEnum          = 0;
my $inMethod        = 0;

################ Processing starts here ##############################
my $rootFileName;

# my %HeaderFileProcessedThisRound = ();

# /*!
#     @abstract
#         Hash of C preprocessor token hashes for files processed to date.
#
#     @discussion
#         This hash is a copy of one of the C preprocessor
#         internal hashes.  It is returned to the top-level
#         code by a call to getAndClearCPPHash(), and is
#         then merged with the hashes from any headers that
#         the current header includes.
# 
#         In addition to storing the values for future
#         merges, this copy of the hash is used to determine
#         whether a header file has been processed already for
#         the purposes of determining whether or not to merge
#         in C preprocessor macro definitions.
#
#     @see //apple_ref/perl/data/HeaderDoc::BlockParse/CPP_HASH CPP_HASH
# */
%HeaderDoc::HeaderFileCPPHashHash = ();

# /*!
#     @abstract
#         Hash of argument lists for C preprocessor macros.
#
#     @discussion
#         This hash is a copy of one of the C preprocessor
#         internal hashes.  It is returned to the top-level
#         code by a call to getAndClearCPPHash(), and is
#         then merged with the hashes from any headers that
#         the current header includes.
#
#     @see //apple_ref/perl/data/HeaderDoc::BlockParse/CPP_ARG_HASH CPP_ARG_HASH
#  */
%HeaderDoc::HeaderFileCPPArgHashHash = ();

my $includeDebug = 0;

if (!$quietLevel) {
    print STDERR "======= Parsing Input Files =======\n";
}

if ($use_stdout && (scalar(@inputFiles) > 1)) {
	die("-P flag limits you to a single input file.\n");
}

if ($debugging) { print STDERR "Processing includes.\n"; }
foreach my $inputFile (@inputFiles) {
    my $fullpath=getAbsPath($inputFile);

    # Temp object.
    my ($rootFileName, $lang, $sublang) = getLangAndSubLangFromFilename($inputFile);
    my $headerObject = HeaderDoc::Header->new("LANG" => $lang, "SUBLANG" => $sublang);
    $HeaderDoc::headerObject = $headerObject;

    my ($encoding, $arrayref) = linesFromFile($inputFile, 1);
    my @rawInputLines = @{$arrayref};
    if ($debugging) { print STDERR "Checking file $inputFile\n"; }
    # Grab any #include directives.
    processIncludes(\@rawInputLines, $fullpath, $lang, $sublang);
}
if ($debugging) { print STDERR "Done processing includes.  Fixing dependencies.\n"; }

my @fileList = ();

if (1 || $HeaderDoc::enable_cpp) {
	my $deplistref = fix_dependency_order(\@inputFiles);
	if ($deplistref) {
		@fileList = @{$deplistref};
	} else {
		@fileList = @inputFiles;
	}
} else {
	@fileList = @inputFiles
}
if ($debugging) { print STDERR "Done fixing dependencies.  Filling fileList hash.\n"; }

if ($#fileList != $#inputFiles) {
	die("File counts don't match: ".$#fileList." != ".$#inputFiles.".\n");
}

# Remove duplicates.
my %filelisthash = ();
my @oldfileList = @fileList;
@fileList = ();
foreach my $inputFile (@oldfileList) {
	if (!$filelisthash{$inputFile}) {
		$filelisthash{$inputFile} = 1;
		push(@fileList, $inputFile);
	}
}
if ($debugging) { print STDERR "Done filling fileList hash\n"; }

@oldfileList = (); # free memory
%filelisthash = (); # free memory

my $sort_entries = $HeaderDoc::sort_entries;

my $tlhangDebug = 0;

foreach my $inputFile (@fileList) {
	my $headerObject;  # this is the Header object that will own the HeaderElement objects for this file.
	my $cppAccessControlState = "protected:"; # the default in C++
	my $objcAccessControlState = "private:"; # the default in Objective C
	$HeaderDoc::AccessControlState = "";

	my $hashtreecur = undef;
	my $hashtreeroot = undef;

	my @perHeaderClassObjects = ();
	my @perHeaderCategoryObjects = ();
	# $HeaderDoc::perHeaderObjectID = 0;

	# Restore this setting if it got changed on a per-header basis.
	$HeaderDoc::sort_entries = $sort_entries;

    my @path = split (/$pathSeparator/, $inputFile);
    my $filename = pop (@path);
    if ($HeaderDoc::HeaderFileCPPHashHash{$inputFile}) {
	print STDERR "Already procesed $inputFile.  Skipping.\n" if ($includeDebug);
	next;
    }

    if (basename($filename) eq $HeaderDoc::debugFile) {
	$HeaderDoc::fileDebug = 1;
	print STDERR "Enabling debug mode for this file.\n";
    }

    print STDERR "Top Level Point 100\n" if ($tlhangDebug);

    my $sublang = "";
    if ($quietLevel eq "0") {
	if ($headerdoc_strip) {
		print STDERR "\nStripping $inputFile\n";
	} elsif ($regenerate_headers) {
		print STDERR "\nRegenerating $inputFile\n";
	} else {
		print STDERR "\nProcessing $inputFile\n";
	}
    }
    # @@@ DAG WARNING: The next line doesn't do anything anymore. @@@
    # %HeaderDoc::perHeaderIgnoreFuncMacros = ( "OSDeclareDefaultStructors" => "OSDeclareDefaultStructors", "OSDeclareAbstractStructors" => "OSDeclareAbstractStructors" );
    ## if ($filename =~ /\.idl$/) {
	## # print STDERR "IDL FILE\n";
	## # %HeaderDoc::perHeaderIgnoreFuncMacros = ( "cpp_quote" => "cpp_quote" );
	## HeaderDoc::BlockParse::cpp_add_string("#define cpp_quote(a) a", 0);
	## Disabled because the syntax is cpp_quote(" content here ").  Note the quotes.
    ## }
    %HeaderDoc::perHeaderIgnorePrefixes = ();

    foreach my $predefined_token (keys %HeaderDoc::filter_macro_definition_state) {
	if ($HeaderDoc::filter_macro_definition_state{$predefined_token} == 1) {
		cpp_add_cl($predefined_token, $HeaderDoc::filter_macro_definition_value{$predefined_token});
	}
    }

    $HeaderDoc::globalGroup = "";
    $reprocess_input = 0;
    
    my $headerDir = join("$pathSeparator", @path);

    print STDERR "Top Level Point 200\n" if ($tlhangDebug);
    ($rootFileName, $lang, $sublang) = getLangAndSubLangFromFilename($filename);

    my $rootOutputDir;
    if (length ($specifiedOutputDir)) {
    	$rootOutputDir ="$specifiedOutputDir$pathSeparator$rootFileName";
    } elsif (@path) {
    	$rootOutputDir ="$headerDir$pathSeparator$rootFileName";
    } else {
    	$rootOutputDir = $rootFileName;
    }

    # my @cookedInputLines;
    my $localDebug = 0;

    $headerObject = HeaderDoc::Header->new("LANG" => $lang, "SUBLANG" => $sublang);
    $HeaderDoc::headerObject = $headerObject;

    my ($encoding, $arrayref) = linesFromFile($inputFile, 1);
    my @rawInputLines = @{$arrayref};
    print STDERR "ENCODING GUESS: $encoding\n" if ($localDebug);

    # IS THIS STILL NEEDED?
    # foreach my $line (@rawInputLines) {
	# foreach my $prefix (keys %HeaderDoc::ignorePrefixes) {
	    # if ($line =~ s/^\s*$prefix\s*//g) {
		# print STDERR "ignored $prefix\n" if ($localDebug);
	    # }
	# }
	# push(@cookedInputLines, $line);
    # }
    # @rawInputLines = @cookedInputLines;

    # /*!
    #     @abstract
    #         A list of C preprocessor token hashes for the current header.
    #     @discussion
    #         This gets reset for each header.  For more
    #         info, see the documentation for
    #         {@link //apple_ref/perl/data/HeaderDoc::BlockParse/CPP_HASH
    #          HeaderDoc::BlockParse::CPP_HASH}.
    #  */
    @HeaderDoc::cppHashList = ();

    # /*!
    #     @abstract
    #         A list of C preprocessor argument hashes for the current header.
    #     @discussion
    #         This gets reset for each header.
    #         {@link //apple_ref/perl/data/HeaderDoc::BlockParse/CPP_ARG_HASH
    #          HeaderDoc::BlockParse::CPP_ARG_HASH}.
    #  */
    @HeaderDoc::cppArgHashList = ();
	
REDO:
    print STDERR "Top Level Point 300\n" if ($tlhangDebug);
print STDERR "REDO" if ($debugging);
# print STDERR "LANG: $lang\n";
    # check for HeaderDoc comments -- if none, move to next file
    my @headerDocCommentLines = grep(/^\s*\/\*\!/, @rawInputLines);
    if ((!@headerDocCommentLines) && ($lang eq "java" || $HeaderDoc::parse_javadoc)) {
	@headerDocCommentLines = grep(/^\s*\/\*\*[^\*]/, @rawInputLines);
    }
    if ((!@headerDocCommentLines) && ($lang eq "ruby" || $lang eq "python")) {
	@headerDocCommentLines = grep(/^\s*\!headerdoc\!\s*$/i, @rawInputLines);
    }
    if ((!@headerDocCommentLines) && ($lang eq "perl" || $lang eq "shell" ||
	                              $lang eq "tcl")) {
	@headerDocCommentLines = grep(/^\s*\#\s*\/\*\!/, @rawInputLines);
    }
    if ((!@headerDocCommentLines) && ($lang eq "pascal")) {
	@headerDocCommentLines = grep(/^\s*\{\!/, @rawInputLines);
    }
    if ((!@headerDocCommentLines) && ($lang eq "applescript")) {
	@headerDocCommentLines = grep(/^\s*\(\*\!/, @rawInputLines);
    }
    my $skip_header_processing = 0;
    if (!@headerDocCommentLines && ((!$HeaderDoc::process_everything) || (!allow_everything($lang, $sublang)))) {
	if ($quietLevel eq "0") {
            print STDERR "    Skipping. No HeaderDoc comments found.\n";
	    $skip_header_processing = 1;
	}
    }

    my $fullpath=getAbsPath($inputFile);
    my $basefilename = basename($inputFile);

    print STDERR "Top Level Point 400\n" if ($tlhangDebug);
    if (!$headerdoc_strip) {
	# Don't do this if we're stripping.  It wastes memory and
	# creates unnecessary empty directories in the output path.

	$headerObject->encoding($encoding);

	# SDump($headerObject, "point1");
	$headerObject->linenuminblock(0);
	$headerObject->blockoffset(0);
	# $headerObject->linenum(0);
	$headerObject->apiOwner($headerObject);
	$HeaderDoc::headerObject = $headerObject;
	# SDump($headerObject, "point2");

	# if ($quietLevel eq "0") {
	# print STDERR "output mode is $xml_output\n";
	# }
	if ($use_stdout) {
		$headerObject->use_stdout(1);
	} else {
		$headerObject->use_stdout(0);
	}
	if ($xml_output) {
		$headerObject->outputformat("hdxml");
	} elsif ($function_list_output) { 
		$headerObject->outputformat("functions");
	} else { 
		$headerObject->outputformat("html");
	}
	$headerObject->outputDir($rootOutputDir);
	$headerObject->name($filename);
	$headerObject->filename($filename);
	$headerObject->fullpath($fullpath);
    } else {
	$HeaderDoc::headerObject = $headerObject;
	if ($use_stdout) {
		$headerObject->use_stdout(1);
	} else {
		$headerObject->use_stdout(0);
	}
	$headerObject->filename($filename);
	$headerObject->linenuminblock(0);
	$headerObject->blockoffset(0);
	# $headerObject->linenum(0);
    }
	# SDump($headerObject, "point3");
	
    print STDERR "Top Level Point 500\n" if ($tlhangDebug);
    # scan input lines for class declarations
    # return an array of array refs, the first array being the header-wide lines
    # the others (if any) being the class-specific lines
	my @lineArrays = &getLineArrays(\@rawInputLines, $lang, $sublang);

    # print STDERR "NLA: " . scalar(@lineArrays) . "\n";
    
    my $processEverythingDebug = 0;
    my $localDebug = 0 || $debugging;
    my $linenumdebug = 0;

    print STDERR "Top Level Point 600\n" if ($tlhangDebug);
    if ($headerdoc_strip) {
	# print STDERR "input file is $filename, output dir is $rootOutputDir\n";
	my $outdir = "";
	if (length ($specifiedOutputDir)) {
        	$outdir ="$specifiedOutputDir";
	} elsif (@path) {
        	$outdir ="$headerDir";
	} else {
        	$outdir = "strip_output";
	}
	strip($filename, $outdir, $rootOutputDir, $inputFile, \@rawInputLines);
	print STDERR "done.\n" if ($quietLevel eq "0");
	next;
    }
    if ($regenerate_headers) {
	HeaderDoc::Regen->regenerate($inputFile, $rootOutputDir);
	print STDERR "done.\n" if ($quietLevel eq "0");
	next;
    }

    print STDERR "Top Level Point 700\n" if ($tlhangDebug);
	# SDump($headerObject, "point4");
    my $retainheader = 0;
    if (!$skip_header_processing) {
      foreach my $arrayRef (@lineArrays) {
        my $blockOffset = 0;
        my @inputLines = @$arrayRef;
	# $HeaderDoc::nodec = 0;

	print STDERR "Top Level Point 705\n" if ($tlhangDebug);

	    # look for /*! comments and collect all comment fields into the appropriate objects

	my $parseTokensRef = parseTokens($lang, $sublang);

        my $apiOwner = $headerObject;  # switches to a class/protocol/category object, when within a those declarations
	my ($case_sensitive, $keywordhashref) = $apiOwner->keywords();
	$HeaderDoc::currentClass = $apiOwner;
	print STDERR "Top Level Point 710\n" if ($tlhangDebug);
	    print STDERR "inHeader\n" if ($localDebug);
	    my $inputCounter = 0;
	    my $ctdebug = 0;
	    my $classType = "unknown";
	    print STDERR "CLASS TYPE CHANGED TO $classType\n" if ($ctdebug);
	    my $nlines = $#inputLines;
	    print STDERR "PROCESSING LINE ARRAY\n" if ($HeaderDoc::inputCounterDebug);
	    my $inMLC = 0;
	    print STDERR "Top Level Point 715\n" if ($tlhangDebug);
	    while ($inputCounter <= $nlines) {
			my $line = "";           

			# print STDERR "inMLC: $inMLC\n";
			print STDERR "LINE: \"".$inputLines[$inputCounter]."\"\n" if ($localDebug);
	        
			if ($inputLines[$inputCounter] =~ /^\s*#include[ \t]+(.*)$/) {
				my $rest = $1;
				$rest =~ s/^\s*//s;
				$rest =~ s/\s*$//s;
				if ($rest !~ s/^\<(.*)\>$/$1/s) {
					$rest =~ s/^\"(.*)\"$/$1/s;
				}
				my $filename = basename($rest);
				if ($HeaderDoc::HeaderFileCPPHashHash{$filename}) {
					my $includehash = HeaderDoc::IncludeHash->new();
					$includehash->{FILENAME} = $filename;
					$includehash->{LINENUM} = $inputCounter + $blockOffset;
					$includehash->{HASHREF} = $HeaderDoc::HeaderFileCPPHashHash{$filename};
					push(@HeaderDoc::cppHashList, $includehash);
# print STDERR "PUSH HASH\n";
					push(@HeaderDoc::cppArgHashList, $HeaderDoc::HeaderFileCPPArgHashHash{$filename});
				}
			}
	        	print STDERR "Input line number[1]: $inputCounter\n" if ($localDebug);
			print STDERR "last line ".$inputLines[$inputCounter-1]."\n" if ($localDebug);
			print STDERR "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
	        	if ($inputLines[$inputCounter] =~ /^\s*(public|private|protected)/o) {
				$cppAccessControlState = $&;
	        		if ($inputLines[$inputCounter] =~ /^\s*(public|private|protected)\s*:/o) {
					# trim leading whitespace and tabulation
					$cppAccessControlState =~ s/^\s+//o;
					# trim ending ':' and whitespace
					$cppAccessControlState =~ s/\s*:\s*$/$1/so;
					# set back the ':'
					$cppAccessControlState = "$cppAccessControlState:";
				}
			}
	        	if ($inputLines[$inputCounter] =~ /^\s*(\@public|\@private|\@protected)/o) {
				$objcAccessControlState = $&;
	        		if ($inputLines[$inputCounter] =~ /^\s*(\@public|\@private|\@protected)\s+/o) {
					# trim leading whitespace and tabulation
					$objcAccessControlState =~ s/^\s+//o;
					# trim ending ':' and whitespace
					$objcAccessControlState =~ s/\s*:\s*$/$1/so;
					# set back the ':'
					$objcAccessControlState = "$objcAccessControlState:";
				}
			}

	    print STDERR "Top Level Point 750\n" if ($tlhangDebug);

			my @fields = ();

			# /*!
			#     @abstract
			#         Determines whether to treat commented
                        #         <code>#if/#ifdef</code> blocks
                        #         as blocks of related functions.
			#     @discussion
                        #         Set to 1 by default.
                        #         Set to 0 if the <code>-E</code>
                        #         flag is passed (unless the language
                        #         does not support that flag).
			#  */
			$HeaderDoc::allow_multi = 0;

	        	if (($lang ne "pascal" && $lang ne "applescript" && $lang ne "ruby" && $lang ne "python" && (
			     ($lang ne "perl" && $lang ne "shell" && $lang ne "tcl" && $inputLines[$inputCounter] =~ /^\s*\/\*\!/o) ||
			     (($lang eq "perl" || $lang eq "shell" || $lang eq "tcl") && ($inputLines[$inputCounter] =~ /^\s*\#\s*\/\*\!/o)) ||
			     (($lang eq "java" || $HeaderDoc::parse_javadoc) && ($inputLines[$inputCounter] =~ /^\s*\/\*\*[^*]/o)))) ||
			    (($lang eq "applescript") && ($inputLines[$inputCounter] =~ s/^\s*\(\*!/\/\*!/so)) || 
			    (($lang eq "pascal") && ($inputLines[$inputCounter] =~ s/^\s*\{!/\/\*!/so)) || 
			    (($lang eq "ruby" || $lang eq "python") && $inMLC && ($inputLines[$inputCounter] =~ s/\s*\!headerdoc\!\s*$/\/\*\!/iso))) {  # entering headerDoc comment
				my $newlinecount = 0;
				# slurp up comment as line

				print STDERR "Top Level Point 755\n" if ($tlhangDebug);


				if ($lang ne "ruby" &&
				    (($lang ne "pascal" && $lang ne "python" && $lang ne "applescript" && ($inputLines[$inputCounter] =~ /\s*\*\//o)) ||
				     ($lang eq "python" && ($inputLines[$inputCounter] =~ /\"\"\".*\"\"\"/)) ||
				     ($lang eq "applescript" && ($inputLines[$inputCounter] =~ s/\s*\*\)/\*\//so)) ||
				     ($lang eq "pascal" && ($inputLines[$inputCounter] =~ s/\s*\}/\*\//so)))) { # closing comment marker on same line

					# print STDERR "SINGLE-LINE\n";
					my $linecopy = $inputLines[$inputCounter];
					# print STDERR "LINE IS \"$linecopy\".\n" if ($linenumdebug);
					$newlinecount = ($linecopy =~ tr/\n//);
					$blockOffset += $newlinecount - 1;
					print STDERR "NEWLINECOUNT: $newlinecount\n" if ($linenumdebug);
					print STDERR "BLOCKOFFSET: $blockOffset\n" if ($linenumdebug);

					my $newline = $inputLines[$inputCounter++];
					# print STDERR "PRE NEWLINE: $newline\n";
					if ($lang eq "perl" || $lang eq "shell" || $lang eq "tcl") {
						# $newline =~ s/^#//;
						# print STDERR "POINT A: $newline\n";
						$newline = stripLeading($newline, "#"); # s/^#//; # Strip off the leading '#' added by getLineArrays()
					}
					if ($lang eq "python") {
						$newline =~ s/\"\"\"/\/\*/s;
						$newline =~ s/\"\"\"/\*\//s;
					}
					$line .= $newline;
					print STDERR "INCREMENTED INPUTCOUNTER [M1]\n" if ($HeaderDoc::inputCounterDebug);
					# This is perfectly legal.  Don't warn
					# necessarily.
					if (!emptyHDok($line)) {
						warnHDComment(\@inputLines, $inputCounter, $blockOffset, $lang, "HeaderDoc comment", "1", $parseTokensRef, $line);
					}
	        			print STDERR "Input line number[2]: $inputCounter\n" if ($localDebug);
					print STDERR "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
				} else {                                       # multi-line comment
					# my $in_textblock = 0; my $in_pre = 0;
					# print STDERR "MULTI-LINE\n";
					my $nInputLines = $nlines;
					print STDERR "MULTI-LINE LOOP START\n" if ($tlhangDebug);
					do {
						my $templine = $inputLines[$inputCounter];
						# print STDERR "HERE: $templine\n";
						# while ($templine =~ s/\@textblock//io) { $in_textblock++; }  
						# while ($templine =~ s/\@\/textblock//io) { $in_textblock--; }
						# while ($templine =~ s/<pre>//io) { $in_pre++; print STDERR "IN PRE\n" if ($localDebug);}
						# while ($templine =~ s/<\/pre>//io) { $in_pre--; print STDERR "OUT OF PRE\n" if ($localDebug);}
						# if (!$in_textblock && !$in_pre) {
							# $inputLines[$inputCounter] =~ s/^[\t ]*[*]?[\t ]+(.*)$/$1/o; # remove leading whitespace, and any leading asterisks
							# if ($line !~ /\S/) {
								# $line = "<br><br>\n";
							# } 
						# }
						my $newline = $inputLines[$inputCounter++];
						print STDERR "INCREMENTED INPUTCOUNTER [M2]\n" if ($HeaderDoc::inputCounterDebug);
						warnHDComment(\@inputLines, $inputCounter, $blockOffset, $lang, "HeaderDoc comment", "2", $parseTokensRef);
						$newline =~ s/^ \*//o;
						print STDERR "NEWLINE [A] IS $newline\n" if ($localDebug);
						if ($lang eq "perl" || $lang eq "shell" || $lang eq "tcl") {
							# $newline =~ s/^#//;
						# print STDERR "POINT B: $newline\n";
						    $newline = stripLeading($newline, "#"); # s/^#//; # Strip off the leading '#' added by getLineArrays()
						    # $newline =~ s/^\s*\#//o;
						}
						$line .= $newline;
	        				print STDERR "Input line number[3]: $inputCounter\n" if ($localDebug);
						print STDERR "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
					} while ((($lang eq "pascal" && ($inputLines[$inputCounter] !~ /\}/o)) ||
					          ($lang eq "applescript" && ($inputLines[$inputCounter] !~ /\*\)/o)) ||
					          ($lang eq "python" && ($inputLines[$inputCounter] !~ s/\"\"\"$/\*\//so)) ||
					          ($lang eq "ruby" && ($inputLines[$inputCounter] !~ s/^=end\s*$/\*\//so))  ||
					          ($lang ne "pascal" && $lang ne "ruby" && $lang ne "python" && $lang ne "applescript" && ($inputLines[$inputCounter] !~ s/\*\//\*\//so))) &&
					         ($inputCounter <= $nInputLines));
					print STDERR "MULTI-LINE LOOP END\n" if ($tlhangDebug);
					$inMLC = 0;
					my $newline = $inputLines[$inputCounter++];
					print STDERR "INCREMENTED INPUTCOUNTER [M3]\n" if ($HeaderDoc::inputCounterDebug);
					# This is not inherently wrong.
					# print "NEWLINE: $newline\n";
					if (!emptyHDok($line)) {
# print STDERR "LINE WAS $line\n";
						my $dectype = "HeaderDoc comment";
						if ($line =~ /^\s*\/\*\!\s*\@define(d)?block\s+/s) {
							$dectype = "defineblock";
						}
						warnHDComment(\@inputLines, $inputCounter, $blockOffset, $lang, $dectype, "3", $parseTokensRef);
					}
					if ($lang eq "perl" || $lang eq "shell" || $lang eq "tcl") {
					    print STDERR "NEWLINE [B] IS $newline\n" if ($localDebug);
					    # $newline =~ s/^\s*\#//o;
					    # $newline =~ s/^#//;
						# print STDERR "POINT C: $newline\n";
					    $newline = stripLeading($newline, "#"); # s/^#//; # Strip off the leading '#' added by getLineArrays()
					}
					if ($newline !~ /^ \*\//o) {
						$newline =~ s/^ \*//o;
					}
					$line .= $newline;              # get the closing comment marker
	        		print STDERR "Input line number[4]: $inputCounter\n" if ($localDebug);
				print STDERR "last line ".$inputLines[$inputCounter-1]."\n" if ($localDebug);
				print STDERR "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
			    } # end of multi-line comment

				# print STDERR "ic=$inputCounter\n" if ($localDebug);
			    # print STDERR "After slurp, comment was \"$line\"\n" if ($localDebug || 1);

			# warn("LINE: $line\n");

			    # HeaderDoc-ize JavaDoc/PerlDoc comments
			    # This code never runs anyway because those have been stripped by now.
			    # if (($lang eq "perl" || $lang eq "shell" || $lang eq "tcl") && ($line =~ /^\s*\#\s*\/\*\!/o)) {
				# $line =~ s/^\s*\#\s*\/\*\!/\/\*\!/o;
			    # }

			    if (($lang eq "java" || $HeaderDoc::parse_javadoc) && ($line =~ /^\s*\/\*\*[^*]/o)) {
				$line =~ s/^\s*\/\*\*/\/\*\!/o;
			    }
			    $line =~ s/^\s+//o;              # trim leading whitespace
			    $line =~ s/^(.*)\*\/\s*$/$1/so;  # remove closing comment marker

			    print STDERR "CURRENT line \"$line\"\n" if ($localDebug);

			    ($inHeader, $inClass, $inInterface, $inCPPHeader, $inOCCHeader, $inPerlScript, $inShellScript, $inPHPScript, $inJavaSource, $inFunctionGroup, $inGroup, $inFunction, $inPDefine, $inTypedef, $inUnion, $inStruct, $inConstant, $inVar, $inEnum, $inMethod, $inAvailabilityMacro, $inUnknown, $classType, $line, $inputCounter, $blockOffset, $filename, $linenumdebug, $localDebug) = processTopLevel($inHeader, $inClass, $inInterface, $inCPPHeader, $inOCCHeader, $inPerlScript, $inShellScript, $inPHPScript, $inJavaSource, $inFunctionGroup, $inGroup, $inFunction, $inPDefine, $inTypedef, $inUnion, $inStruct, $inConstant, $inVar, $inEnum, $inMethod, $inAvailabilityMacro, $inUnknown, $classType, $line, $inputCounter, $blockOffset, $inputFile, $linenumdebug, $localDebug);

				# $inputCounter--; # inputCounter is current line.
				my $linenum = $inputCounter - 1;
				# $line =~ s/\n\n/\n<br><br>\n/go; # change newline pairs into HTML breaks, for para formatting
				my $fieldref = stringToFields($line, $fullpath, $linenum, $xml_output, $lang, $sublang);
				@fields = @{$fieldref};
				$HeaderDoc::allow_multi = 1; # Treat any #if/#ifdef blocks we find as being blocks of similar functions.
			} elsif ($HeaderDoc::process_everything && allow_everything($lang, $sublang)) {
				# print STDERR "POINT\n";

				print STDERR "Top Level Point 760\n" if ($tlhangDebug);

				# print STDERR "IC: $inputCounter\n";
				my ($tempInputCounter, $dec, $type, $name, $pt, $value, $pplref, $returntype, $pridec,
				    $parseTree, $simpleTDcontents, $bpavail) = &HeaderDoc::BlockParse::blockParse($fullpath, $blockOffset, \@inputLines,
				    $inputCounter, 0, \%HeaderDoc::ignorePrefixes, \%HeaderDoc::perHeaderIgnorePrefixes,
				    \%HeaderDoc::perHeaderIgnoreFuncMacros, $keywordhashref, $case_sensitive, $lang, $sublang);

				print STDERR "Top Level Point 765\n" if ($tlhangDebug);

				if ($dec !~ /^(\/\*.*?\*\/|\/\/.*?(\n|\r)|\n|\r)*(\/\*\!)/) {
					print STDERR "DECLARATION WITH NO MARKUP ENCOUNTERED.\n" if ($processEverythingDebug);
					$inUnknown = 1; # Only process declaration if we don't encounter a HeaderDoc comment on the way.
				} else {
					print STDERR "DECLARATION WITH MARKUP ENCOUNTERED.\n" if ($processEverythingDebug);
				}
				$HeaderDoc::allow_multi = 0; # Drop any #if/#ifdef blocks or partial blocks on the floor for safety.
				@fields = ();
			} elsif ($lang eq "python" && ($inputLines[$inputCounter] =~ /\"\"\"/o) && !$inMLC) {
				$inMLC = 1;
			} elsif ($lang eq "ruby" && ($inputLines[$inputCounter] =~ /^=begin\s*$/o)) {
				$inMLC = 1;
			} elsif ($lang eq "ruby" && ($inputLines[$inputCounter] =~ /^=end\s*$/o)) {
				$inMLC = 0;
			} # end slurping up
			print STDERR "Top Level Point 770\n" if ($tlhangDebug);
			# print "CHECKPOINT: INUNKNOWN: $inUnknown\n";

				my $preAtPart = "";


				if ($inCPPHeader) {print STDERR "inCPPHeader\n" if ($debugging); $sublang="cpp"; };
				if ($inOCCHeader) {print STDERR "inCPPHeader\n" if ($debugging); $sublang="occ"; };
				if ($inPerlScript) {print STDERR "inPerlScript\n" if ($debugging); $lang="php";};
				if ($inPHPScript) {print STDERR "inPHPScript\n" if ($debugging); $lang="php";};
				if ($inJavaSource) {print STDERR "inJavaSource\n" if ($debugging); $lang="java";};
				if ($inHeader) {
					print STDERR "inHeader\n" if ($debugging); 
					$functionGroup = "";
					$HeaderDoc::globalGroup = "";
					($lang, $sublang) = processHeaderComment($apiOwner, $rootOutputDir, \@fields, $debugging, \$reprocess_input, $lang, $sublang);
					$HeaderDoc::currentClass = $apiOwner;
					$inputCounter--;
					print STDERR "DECREMENTED INPUTCOUNTER [M5]\n" if ($HeaderDoc::inputCounterDebug);
					if ($reprocess_input == 1) {
					    # my @cookedInputLines;
					    my $localDebug = 0;

					    # foreach my $line (@rawInputLines) {
						# foreach my $prefix (keys %HeaderDoc::perHeaderIgnorePrefixes) {
						    # if ($line =~ s/^\s*$prefix\s*//g) {
							# print STDERR "ignored $prefix\n" if ($localDebug);
						    # }
						# }
						# push(@cookedInputLines, $line);
					    # }
					    # @rawInputLines = @cookedInputLines;
					    $reprocess_input = 2;
					    goto REDO;
					}
				};
				if ($inGroup) {
					print STDERR "inGroup\n" if ($debugging); 
					# my $rawname = $line;
					# $rawname =~ s/.*\/\*!\s*\@(group|name)\s+//sio;
					# $rawname =~ s/\s*\*\/.*//o;
					# my ($name, $desc, $is_nameline_disc) = getAPINameAndDisc($rawname);
					# $name =~ s/^\s+//smgo;
					# $name =~ s/\s+$//smgo;

					# if ($is_nameline_disc) { $name .= " ".$desc; $desc = ""; }

					# print STDERR "group name is $name\n" if ($debugging);
					my $group = HeaderDoc::Group->new("LANG" => $lang, "SUBLANG" => $sublang);
					$group->fullpath($fullpath);
					$group->filename($filename);
					$group->linenuminblock($inputCounter - 1);
					$group->blockoffset(0);
					$group->apiOwner($apiOwner);
					$group = $group->processComment(\@fields);

					$apiOwner->addGroup($group, 1); #(, $desc);

					$HeaderDoc::globalGroup = $group->name();
					$inputCounter--;
					print STDERR "DECREMENTED INPUTCOUNTER [M6]\n" if ($HeaderDoc::inputCounterDebug);
				};
				if ($inFunctionGroup) {
					print STDERR "inFunctionGroup\n" if ($debugging); 
					# my $rawname = $line;
					# if (!($rawname =~ s/.*\/\*!\s+\@functiongroup\s+//io)) {
						# $rawname =~ s/.*\/\*!\s+\@methodgroup\s+//io;
						# print STDERR "inMethodGroup\n" if ($debugging);
					# }
					# $rawname =~ s/\s*\*\/.*//o;
					# my ($name, $desc, $is_nameline_disc) = getAPINameAndDisc($rawname);
					# $name =~ s/^\s+//smgo;
					# $name =~ s/\s+$//smgo;

					# if ($is_nameline_disc) { $name .= " ".$desc; $desc = ""; }

					my $group = HeaderDoc::Group->new("LANG" => $lang, "SUBLANG" => $sublang);
					$group->filename($filename);
					$group->linenuminblock($inputCounter - 1);
					$group->blockoffset(0);
					$group->apiOwner($apiOwner);
					$group = $group->processComment(\@fields);

					print STDERR "group name is ".$group->name()."\n" if ($debugging);
					$apiOwner->addGroup($group, 0); #(, $desc);

					# $HeaderDoc::globalGroup = $name;

					$functionGroup = $group->name();
					$inputCounter--;
					print STDERR "DECREMENTED INPUTCOUNTER [M7]\n" if ($HeaderDoc::inputCounterDebug);
				};

			print STDERR "Top Level Point 800\n" if ($tlhangDebug);

    if ($inUnknown || $inTypedef || $inStruct || $inEnum || $inUnion || $inConstant || $inVar || $inFunction || $inMethod || $inPDefine || $inClass || $inAvailabilityMacro) {
	# my $localDebug = 1;
	my $hangDebug  = 0;
	my $parmDebug  = 0;
	my $blockDebug = 0;

# print STDERR "WRAPPER: FIELDS:\n";
# foreach my $field (@fields) {
	# print STDERR "FIELD: $field\n";
# }
# print STDERR "ENDFIELDS\n";
# print STDERR "preAtPart: $preAtPart\n";
    print STDERR "Top Level Point 810\n" if ($tlhangDebug);

	if ($inClass && $debugging) { print STDERR "INCLASS (MAIN)\n";
		print STDERR "line is $line\n";
		print STDERR "IC: $inputCounter\n";
		print STDERR "CUR LINE: ".$inputLines[$inputCounter-1]."\n";
		print STDERR "NEXT LINE: ".$inputLines[$inputCounter]."\n";
	}
	# print STDERR "LINE_0:  ".$inputLines[$inputCounter + 0]."\n";
	# print STDERR "LINE_1:  ".$inputLines[$inputCounter + 1]."\n";
	# print STDERR "LINE_2:  ".$inputLines[$inputCounter + 2]."\n";
	# print STDERR "LINE_3:  ".$inputLines[$inputCounter + 3]."\n";
	# print STDERR "LINE_4:  ".$inputLines[$inputCounter + 4]."\n";

	my $subparse = 0;
	my $subparseTree = undef;
	my $classref = undef;
	my $catref = undef;
	my $newInputCounter;
	print STDERR "CALLING blockParseOutside WITH IC: $inputCounter (".$inputLines[$inputCounter].")\n" if ($debugging);
	my $junk = undef;
	print STDERR "BLOCKOFFSET IN LOOP: $blockOffset\n" if ($linenumdebug);

	my $bpPrintDebug = $localDebug || 0;

	print STDERR "Top Level Point 820\n" if ($tlhangDebug);
	my $nodec = 0; # HeaderDoc::nodec
                print STDERR "my (\$newInputCounter, \$cppAccessControlState, \$classType, \$classref, \$catref, \$blockOffset, \$numcurlybraces, \$foundMatch, \$newlang, \$newsublang, \$hashtreecur, \$hashtreeroot) =
            blockParseOutside($apiOwner, $inFunction, $inUnknown,
                $inTypedef, $inStruct, $inEnum, $inUnion,
                $inConstant, $inVar, $inMethod, $inPDefine,
                $inClass, $inInterface, $blockOffset, \@perHeaderCategoryObjects
,
                \@perHeaderClassObjects, $classType, $cppAccessControlState,
                \@fields, $fullpath, $functionGroup,
                $headerObject, $inputCounter, \@inputLines,
                $lang, $nlines, $preAtPart, $xml_output, $localDebug,
                $hangDebug, $parmDebug, $blockDebug, $subparse,
                $subparseTree, $nodec, $HeaderDoc::allow_multi,
		undef, $sublang, $hashtreecur, $hashtreeroot);\n" if ($bpPrintDebug || $tlhangDebug);
                print STDERR "FIELDS:\n" if ($bpPrintDebug || $tlhangDebug);
                printArray(@fields) if ($bpPrintDebug || $tlhangDebug);
		print "FIRSTLINE: ".$inputLines[$inputCounter]."\n" if ($bpPrintDebug || $tlhangDebug);

	my $foundMatch; my $newlang; my $newsublang;
	($newInputCounter, $cppAccessControlState, $classType, $classref, $catref, $blockOffset, $junk, $foundMatch, $newlang, $newsublang, $hashtreecur, $hashtreeroot) =
	    blockParseOutside($apiOwner, $inFunction, $inUnknown,
		$inTypedef, $inStruct, $inEnum, $inUnion,
		$inConstant, $inVar, $inMethod, $inPDefine,
		$inClass, $inInterface, $blockOffset, \@perHeaderCategoryObjects,
		\@perHeaderClassObjects, $classType, $cppAccessControlState,
		\@fields, $fullpath, $functionGroup,
		$headerObject, $inputCounter, \@inputLines,
		$lang, $nlines, $preAtPart, $xml_output, $localDebug,
		$hangDebug, $parmDebug, $blockDebug, $subparse,
		$subparseTree, $nodec, $HeaderDoc::allow_multi,
		undef, $sublang, $hashtreecur, $hashtreeroot);
	print STDERR "BLOCKOFFSET RETURNED: $blockOffset\n" if ($linenumdebug);

	$lang = $newlang;
	$sublang = $newsublang;

	print STDERR "Top Level Point 830\n" if ($tlhangDebug);
	# $HeaderDoc::nodec = 0;
	@perHeaderClassObjects = @{$classref};
	@perHeaderCategoryObjects = @{$catref};

	# This fix for infinite loops is WRONG.
	# @@@ FIXME DAG @@@
	print "IC: $inputCounter NIC: $newInputCounter\n" if ($HeaderDoc::inputCounterDebug);
        # if ($inputCounter > $newInputCounter) {
                # $inputCounter++;
		# print STDERR "INCREMENTED INPUTCOUNTER [M8]\n" if ($HeaderDoc::inputCounterDebug);
        # } else {                        
        $inputCounter = $newInputCounter;
        # }                
	if ($lang eq "perl" && $HeaderDoc::perlClassChange) {
		print STDERR "CLASS: ".$HeaderDoc::perlClassChange."\n" if ($localDebug);
		print STDERR "OLDAPIO: $apiOwner\n" if ($localDebug);
		$apiOwner = $HeaderDoc::perlClassChange;
		$HeaderDoc::perlClassChange = undef;
	}
    } # end "inUnknown, etc."
    print STDERR "Top Level Point 890\n" if ($tlhangDebug);


			$inCPPHeader = $inOCCHeader = $inPerlScript = $inShellScript = $inPHPScript = $inJavaSource = $inInterface = $inHeader = $inUnknown = $inFunction = $inAvailabilityMacro = $inFunctionGroup = $inGroup = $inTypedef = $inUnion = $inStruct = $inConstant = $inVar = $inPDefine = $inEnum = $inMethod = $inClass = 0;
	        $inputCounter++;
		print STDERR "INCREMENTED INPUTCOUNTER [M9] TO $inputCounter\n" if ($HeaderDoc::inputCounterDebug);
		print STDERR "Input line number[8]: $inputCounter\n" if ($localDebug);
	    } # end processing individual line array
    print STDERR "Top Level Point 895\n" if ($tlhangDebug);
			# Put it back at the end.
			if ($lang eq "perl" && ($apiOwner != $headerObject)) {
				print STDERR "Resetting Header Object\n" if ($localDebug);
				$apiOwner = $headerObject;
			}

	    print STDERR "DONE PROCESSING LINE ARRAY\n" if ($HeaderDoc::inputCounterDebug);
    print STDERR "Top Level Point 900\n" if ($tlhangDebug);

	    if (ref($apiOwner) ne "HeaderDoc::Header") { # if we've been filling a class/protocol/category object, add it to the header
	        my $name = $apiOwner->name();
	        my $refName = ref($apiOwner);

			# print STDERR "$classType : ";
			SWITCH: {
				($classType eq "php" ) && do { 
					push (@perHeaderClassObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "java" ) && do { 
					push (@perHeaderClassObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "cpp" ) && do { 
					push (@perHeaderClassObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "cppt" ) && do { 
					push (@perHeaderClassObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "occ") && do { 
					push (@perHeaderClassObjects, $apiOwner);
					if ($headerIncluded{$basefilename}) {
						$retainheader = 1;
					}
					$headerObject->addToClasses($apiOwner); 
					$objCClassNameToObject{$apiOwner->name()} = $apiOwner;
					last SWITCH; };           
				($classType eq "intf") && do { 
					push (@perHeaderClassObjects, $apiOwner);
					$headerObject->addToProtocols($apiOwner); 
					last SWITCH; 
				};           
				($classType eq "occCat") && do {
					push (@perHeaderCategoryObjects, $apiOwner);
					print STDERR "INSERTED CATEGORY into $headerObject\n" if ($ctdebug);
					$headerObject->addToCategories($apiOwner);
					last SWITCH; 
				};           
				($classType eq "C") && do {
					# $cppAccessControlState = "public:";
					$cppAccessControlState = "";
					push (@perHeaderClassObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner);
					last SWITCH;
				};
			foreach my $testclassref ( $headerObject->classes() ) {
				my $testclass = %{$testclassref};
				bless($testclass, "HeaderDoc::APIOwner");
				bless($testclass, $testclass->class());
				print STDERR $testclass->name() . "\n";
			}
			my $linenum = $inputCounter - 1;
                    	print STDERR $headerObject->fullpath().":$linenum: warning: Unknown class type '$classType' (known: cpp, objC, intf, occCat)\n";		
			}
	    }
      } # end processing array of line arrays
      print STDERR "Top Level Point 1000\n" if ($tlhangDebug);

      $headerObject->reparentModuleMembers();
      my @newobjs = ();
      foreach my $class (@perHeaderClassObjects) {
	if (!$class->isModule()) {
		push(@newobjs, $class);
	}
      }
      @perHeaderClassObjects = @newobjs;

	# SDump($headerObject, "point5");
      if ($retainheader) {
	push (@headerObjects, $headerObject);
	# print STDERR "Retaining header\n";
      }
    } # end !$skip_header_processing

    print STDERR "Top Level Point 1100\n" if ($tlhangDebug);
    my ($headercpphashref, $headercpparghashref) = getAndClearCPPHash();
    my %headercpphash = %{$headercpphashref};
    my %headercpparghash = %{$headercpparghashref};

    my $includeListRef = $HeaderDoc::perHeaderIncludes{$fullpath};
    if ($includeListRef) {
	my @includeList = @{$includeListRef};
	print STDERR "LISTING PER HEADER INCLUDES\n" if ($includeDebug);
	foreach my $include (@includeList) {
		print STDERR "INCLUDE: $include\n" if ($includeDebug);
		my $pathname = $include;
		$pathname =~ s/^\s*//s;
		$pathname =~ s/\s*$//s;
		if ($pathname !~ s/^\<(.*)\>$/$1/s) {
			$pathname =~ s/^\"(.*)\"$/$1/s;
		}

		print STDERR "SANITIZED PATHNAME: $pathname\n" if ($includeDebug);
		my $includedfilename = basename($pathname);
		print STDERR "INCLUDED FILENAME: $includedfilename\n" if ($includeDebug);
		if ($HeaderDoc::HeaderFileCPPHashHash{$includedfilename}) {
			# Merge the hashes.

			print STDERR "FOUND.  MERGING HASHES\n" if ($includeDebug);
			%headercpphash = (%headercpphash, %{$HeaderDoc::HeaderFileCPPHashHash{$includedfilename}});
			%headercpparghash = (%headercpparghash, %{$HeaderDoc::HeaderFileCPPArgHashHash{$includedfilename}});
		}
		print STDERR "\n" if ($includeDebug);
	}
    } else {
	print STDERR "NO PER HEADER INCLUDES (NO REF)\n" if ($includeDebug);
    }
    print STDERR "Top Level Point 1200\n" if ($tlhangDebug);

    # NOTE: These MUST not be modified to use the full filename or path.
    # If you do, C preprocessing interaction between headers will fail.
    $HeaderDoc::HeaderFileCPPHashHash{$basefilename} = \%headercpphash;
    $HeaderDoc::HeaderFileCPPArgHashHash{$basefilename} = \%headercpparghash;

    # This is safe to do on a per-header basis, as we've already forced
    # dependency ordering.
    foreach my $class (@perHeaderClassObjects) {
	if ($headerIncluded{$basefilename}) {
		# print STDERR "Retaining class\n";
		push(@classObjects, $class);
	}
    }
    if (@perHeaderClassObjects && !$xml_output) {
        foreach my $class (@perHeaderClassObjects) {
	    mergeClass($class);
        }
    }
    print STDERR "Top Level Point 1300\n" if ($tlhangDebug);

    # print STDERR "CLASSES: ".scalar(@perHeaderClassObjects)."\n";
    # print STDERR "CATEGORIES: ".scalar(@perHeaderCategoryObjects)."\n";
    # print STDERR "HEADERS: ".scalar(@headerObjects)."\n";
    
    # foreach my $obj (@perHeaderCategoryObjects) {
	# print STDERR "CO: $obj\n";
    # }

    # we merge ObjC methods declared in categories into the owning class,
    # if we've seen it during processing.  Since we do dependency ordering,
    # we should have seen it by now if we're ever going to.

    if (!$skip_header_processing) {
      if (@perHeaderCategoryObjects && !$xml_output) {
        foreach my $obj (@perHeaderCategoryObjects) {
            my $nameOfAssociatedClass = $obj->className();
            my $categoryName = $obj->categoryName();
            my $localDebug = 0;

	    # print STDERR "FOR CATEGORY: \"$categoryName\" CLASS IS \"$nameOfAssociatedClass\"\n";
        
		if (exists $objCClassNameToObject{$nameOfAssociatedClass}) {
			my $associatedClass = $objCClassNameToObject{$nameOfAssociatedClass};
			print STDERR "AC: $associatedClass\n" if ($localDebug);
			print STDERR "OBJ: $obj\n" if ($localDebug);
			my $methods = $obj->methods();
			$associatedClass->addToMethods($obj->methods());

			my $owner = $obj->headerObject();
			
			print STDERR "Found category with name $categoryName and associated class $nameOfAssociatedClass\n" if ($localDebug);
			print STDERR "Associated class exists\n" if ($localDebug);
			print STDERR "Added methods to associated class\n" if ($localDebug);
			if (ref($owner)) {
			    my $numCatsBefore = $owner->categories();
			    # $owner->printObject();
			    $owner->removeFromCategories($obj);
			    my $numCatsAfter = $owner->categories();
				print STDERR "Number of categories before: $numCatsBefore after:$numCatsAfter\n" if ($localDebug);
			    
			} else {
				my $fullpath = $HeaderDoc::headerObject->fullpath();
				my $linenum = $obj->linenum();
                    		print STDERR "$fullpath:$linenum: warning: Couldn't find Header object that owns the category with name $categoryName.\n";
			}
			my $assocapio = $associatedClass->APIOwner();
			$assocapio->resetAppleRefUsed();
			if ($man_output) {
				$assocapio->writeHeaderElementsToManPage();
			} elsif ($function_list_output) {
				$assocapio->writeFunctionListToStdOut();
			} elsif ($xml_output) {
				$assocapio->writeHeaderElementsToXMLPage();
			} else {
				$assocapio->createFramesetFile();
				$assocapio->createTOCFile();
				$assocapio->writeHeaderElements(); 
				$assocapio->writeHeaderElementsToCompositePage();
				$assocapio->createContentFile() if (!$HeaderDoc::ClassAsComposite);
			}
			if ($doxytag_output) {
				$assocapio->writeHeaderElementsToDoxyFile();
			}
		} else {
			print STDERR "Found category with name $categoryName and associated class $nameOfAssociatedClass\n" if ($localDebug);
			print STDERR "Associated class doesn't exist\n" if ($localDebug);
            }
        }
      }
      print STDERR "Top Level Point 1400\n" if ($tlhangDebug);
      # SDump($headerObject, "point5a");
      if ($doxytag_output) {
	$headerObject->writeHeaderElementsToDoxyFile();
      }
      if ($man_output) {
	$headerObject->writeHeaderElementsToManPage();
      } elsif ($function_list_output) {
	$headerObject->writeFunctionListToStdOut();
      } elsif ($xml_output) {
	$headerObject->writeHeaderElementsToXMLPage();
      } else {
	$headerObject->fixupTypeRequests();
	# SDump($headerObject, "point5a1");
	$headerObject->createFramesetFile();
	# SDump($headerObject, "point5a2");
	$headerObject->createTOCFile();
	# SDump($headerObject, "point5a3");
	$headerObject->writeHeaderElements(); 
	# SDump($headerObject, "point5a4");
	$headerObject->writeHeaderElementsToCompositePage();
	# SDump($headerObject, "point5a5");
	$headerObject->createContentFile() if (!$HeaderDoc::ClassAsComposite);
	# SDump($headerObject, "point5a6");
      }
    } # !$skip_header_processing
    # SDump($headerObject, "point5b");
    # if ("$write_control_file" eq "1") {
	# print STDERR "Writing doc server control file... ";
	# $headerObject->createMetaFile();
	# print STDERR "done.\n";
    # }
    # my $old_handle = select (STDOUT); # "select" STDOUT and save
                                  # previously selected handle
    # $| = 1; # perform flush after each write to STDOUT
    # print STDERR "Freeing data\n"; 
	# print STDERR "";
    # sleep(5);
    # SDump($headerObject, "point5c");
    print STDERR "Top Level Point 1500\n" if ($tlhangDebug);
    foreach my $class (@perHeaderClassObjects) {
	if (!$headerIncluded{$basefilename}) {
		$class->free($retainheader ? 2 : 0);
	}
    }
    # SDump($headerObject, "point5d");
    if (!$retainheader) {
	$headerObject->free($headerIncluded{$basefilename});
	$HeaderDoc::headerObject = undef;
	$HeaderDoc::currentClass = undef;
    }
    # SDump($headerObject, "point6");

    print "Object $headerObject should go away.\n" if ($HeaderDoc::debugAllocations);
    $headerObject = undef;
    print "Object should be gone.\n" if ($HeaderDoc::debugAllocations);

	# SDump($headerObject, "point7");
    # select ($old_handle); # restore previously selected handle
    # print STDERR "freed.\n";
    # sleep(5);
    print STDERR "Top Level Point 1600\n" if ($tlhangDebug);
}
    # sleep(5);

# if (!$quietLevel) {
    # print STDERR "======= Beginning post-processing =======\n";
# }
if ($doxytag_output && $specifiedOutputDir) {
    mergeDoxyTags($specifiedOutputDir);
}

dumpCaches() if ($HeaderDoc::debugAllocations);

if ($quietLevel eq "0") {
    print STDERR "...done\n";
}

if ($HeaderDoc::exitstatus != 0) {
    print STDERR "WARNING: One or more input files could not be read.  Be sure to check the\n";
    print STDERR "output to make sure that all desired content was documented.\n";
}

# print STDERR "COUNTER: ".$HeaderDoc::counter."\n";
exit $HeaderDoc::exitstatus;


#############################  Subroutines ###################################


# /*! 
#     @abstract
#         Merges superclass bits into subclass upon request.
#     @discussion
#         The mergeClass function is used for merging bits of
#         a superclass into subclasses when the <code>\@superclass</code>
#         tag is specified.
#
#         It is also always used for C psuedoclass classes
#         because any pseudo-superclass relationship isn't
#         really a superclass.
# */
sub mergeClass
{
	my $class = shift;
	my $superName = $class->checkShortLongAttributes("Superclass");
	my $merge_content = 1;

	my $localDebug = 0;

	if ($class->isMerged()) { return; }

	# If superclass was not explicitly specified in the header and if
	# the 'S' (include all superclass documentation) flag was not
	# specified on the command line, don't include any superclass
	# documentation here.
	if (!$class->explicitSuper() && !$HeaderDoc::IncludeSuper) {
		$merge_content = 0;
	}

	if ($superName) {
	    if (!($superName eq $class->name())) {
		my $super = 0;
		foreach my $mergeclass (@classObjects) {
		    if ($mergeclass->name eq $superName) {
			$super = $mergeclass;
		    }
		}
		if ($super) {
		    if (!$super->isMerged()) {
			mergeClass($super);
		    }
		    my @methods = $super->methods();
		    my @functions = $super->functions();
		    my @vars = $super->vars();
		    my @structs = $super->structs();
		    my @enums = $super->enums();
		    my @pdefines = $super->pDefines();
		    my @typedefs = $super->typedefs();
		    my @constants = $super->constants();
		    my @classes = $super->classes();
		    my $name = $super->name();

		    my $discussion = $super->discussion();

		    $class->inheritDoc($discussion);

		    if ($merge_content) {

		        my @childfunctions = $class->functions();
		        my @childmethods = $class->methods();
		        my @childvars = $class->vars();
		        my @childstructs = $class->structs();
		        my @childenums = $class->enums();
		        my @childpdefines = $class->pDefines();
		        my @childtypedefs = $class->typedefs();
		        my @childconstants = $class->constants();
		        my @childclasses = $class->classes();

		        if (@methods) {
			    foreach my $method (@methods) {
				if ($method->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childmethod (@childmethods) {
				    if ($method->name() eq $childmethod->name()) {
					if ($method->parsedParamCompare($childmethod)) {
						$include = 0; last;
					}
				    }
				}
				if (!$include) { next; }
				my $newobj = $method->clone();
				$class->addToMethods($method);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@functions) {
			    foreach my $function (@functions) {
				if ($function->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childfunction (@childfunctions) {
				    if ($function->name() eq $childfunction->name()) {
					if ($function->parsedParamCompare($childfunction)) {
						$include = 0; last;
					}
				    }
				}
				if (!$include) { next; }
				my $newobj = $function->clone();
				$class->addToFunctions($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@vars) {
			    foreach my $var (@vars) {
				if ($var->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childvar (@childvars) {
				    if ($var->name() eq $childvar->name()) {
					$include = 0; last;
				    }
				}
				if (!$include) { next; }
				my $newobj = $var->clone();
				$class->addToVars($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@structs) {
			    foreach my $struct (@structs) {
				if ($struct->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childstruct (@childstructs) {
				    if ($struct->name() eq $childstruct->name()) {
					$include = 0; last;
				    }
				}
				my $newobj = $struct->clone();
				$class->addToStructs($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@enums) {
			    foreach my $enum (@enums) {
				if ($enum->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childenum (@childenums) {
				    if ($enum->name() eq $childenum->name()) {
					$include = 0; last;
				    }
				}
				my $newobj = $enum->clone();
				$class->addToEnums($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@pdefines) {
			    foreach my $pdefine (@pdefines) {
				if ($pdefine->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childpdefine (@childpdefines) {
				    if ($pdefine->name() eq $childpdefine->name()) {
					$include = 0; last;
				    }
				}
				my $newobj = $pdefine->clone();
				$class->addToPDefines($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@typedefs) {
			    foreach my $typedef (@typedefs) {
				if ($typedef->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childtypedef (@childtypedefs) {
				    if ($typedef->name() eq $childtypedef->name()) {
					$include = 0; last;
				    }
				}
				my $newobj = $typedef->clone();
				$class->addToTypedefs($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@constants) {
			    foreach my $constant (@constants) {
				if ($constant->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childconstant (@childconstants) {
				    if ($constant->name() eq $childconstant->name()) {
					$include = 0; last;
				    }
				}
				my $newobj = $constant->clone();
				$class->addToConstants($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		        if (@classes) {
			    foreach my $classref (@classes) {
				my $class = %{$class};
				bless($class, "HeaderDoc::APIOwner");
				bless($class, $class->class());
				if ($class->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childclassref (@childclasses) {
				    my $childclass = %{$childclassref};
				    bless($class, "HeaderDoc::APIOwner");
				    bless($class, $class->class());
				    
				    if ($class->name() eq $childclass->name()) {
					$include = 0; last;
				    }
				}
				my $newobj = $class->clone();
				$class->addToClasses($newobj);
				$newobj->apiOwner($class);
				if ($newobj->origClass() eq "") {
					$newobj->origClass($name);
				}
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $newobj->apirefSetup(1);
				$HeaderDoc::ignore_apiuid_errors = 0;
			    }
		        }
		    } # if ($merge_content)
		}
	    }
	}

	my $ai = $class->alsoInclude();
	if ($ai) {
		my @aiarray = @{$ai};
		foreach my $entry (@aiarray) {
			my $explicit = 0;
			my $uid = "";
			$entry =~ s/^\s*//s;
			$entry =~ s/\s*$//s;
			if ($entry =~ /^\/\//) {
				$uid = $entry;
				$explicit = 1;
			} else {
				$uid = resolveLink($class, $entry, "included")
			}

			print STDERR "UID IS \"$uid\"\n" if ($localDebug);
			my $obj = objectForUID($uid);
			if (!$obj) {
				warn "Object for \"$uid\" could not be found.\n";
				if (!$explicit) {
					warn "    This should not happen.  Please file a bug.\n";
				}
			} else {
				my $objcl = ref($obj) || $obj;

				print STDERR "OBJ IS $obj\n" if ($localDebug);

				if ($objcl =~ /HeaderDoc::Function/) {
					$class->addToFunctions($obj);
					$obj->apiOwner()->removeFromFunctions($obj);
				} elsif ($objcl =~ /HeaderDoc::PDefine/) {
					$class->addToPDefines($obj);
					$obj->apiOwner()->removeFromPDefines($obj);
				} else {
					warn "Don't know how to add object of type $objcl to pseudoclass\n";
				}
			}
		}
	}
	$class->isMerged(1);
}

# /*!
#     @abstract
#         Merge doxygen tag files and delete the partial files.
#  */
sub mergeDoxyTags
{
    my $outputDir = shift;

    find(\&getDoxyTagFiles, $outputDir);
    my $tagfileoutput = "";
    my $temp = $/;
    $/ = undef;
    foreach my $file (@doxyTagFiles) {
	open(MYFILE, "<$file");
	my $temp = <MYFILE>;
	$temp =~ s/^\s*<tagfile>\n*//s;
	$temp =~ s/\n\s*<\/tagfile>.*$//s;
	$tagfileoutput .= "\n".$temp;
	close(MYFILE);
	if (!$debugging) {
		unlink($file);
	}
    }
    $/ = $temp;
    $tagfileoutput =~ s/^\n//;

    my $tagfile = "$outputDir".$pathSeparator."doxytags.xml";
    open(MYFILE, ">$tagfile");
    print MYFILE "<tagfile>\n";
    print MYFILE $tagfileoutput;
    print MYFILE "\n</tagfile>\n";
    close(MYFILE);
}


# /*!
#     @abstract
#         Creates directories recursively as needed.
#     @discussion
#         This is the Perl equivalent of "mkdir -p"
#         on the command line.
#  */
sub mkdir_recursive
{
    my $path = shift;
    my $mask = shift;

    my @pathparts = split (/$pathSeparator/, $path);
    my $curpath = "";

    my $first = 1;
    foreach my $pathpart (@pathparts) {
	if ($first) {
	    $first = 0;
	    $curpath = $pathpart;
	} elsif (! -e "$curpath$pathSeparator$pathpart")  {
	    if (!mkdir("$curpath$pathSeparator$pathpart", 0777)) {
		return 0;
	    }
	    $curpath .= "$pathSeparator$pathpart";
	} else {
	    $curpath .= "$pathSeparator$pathpart";
	}
    }

    return 1;
}

# /*!
#     @abstract
#         Strips out HeaderDoc comments from a header.
#  */
sub strip
{
    my $filename = shift;
    my $short_output_path = shift;
    my $long_output_path = shift;
    my $input_path_and_filename = shift;
    my $inputRef = shift;
    my @inputLines = @$inputRef;
    my $localDebug = 0;

    # for same layout as HTML files, do this:
    # my $output_file = "$long_output_path$pathSeparator$filename";
    # my $output_path = "$long_output_path";

    # to match the input file layout, do this:
    my $output_file = "$short_output_path$pathSeparator$input_path_and_filename";
    my $output_path = "$short_output_path";

    my @pathparts = split(/($pathSeparator)/, $input_path_and_filename);
    my $junk = pop(@pathparts);

    my $input_path = "";
    foreach my $part (@pathparts) {
	$input_path .= $part;
    }

    if ($localDebug) {
	print STDERR "output path: $output_path\n";
	print STDERR "short output path: $short_output_path\n";
	print STDERR "long output path: $long_output_path\n";
	print STDERR "input path and filename: $input_path_and_filename\n";
	print STDERR "input path: $input_path\n";
	print STDERR "filename: $filename\n";
	print STDERR "output file: $output_file\n";
    }

    if (-e $output_file) {
	# don't risk writing over original header
	$output_file .= "-stripped";
	print STDERR "WARNING: output file exists.  Saving as\n\n";
	print STDERR "        $output_file\n\n";
	print STDERR "instead.\n";
    }

    # mkdir -p $output_path

    if (! -e "$output_path$pathSeparator$input_path")  {
	unless (mkdir_recursive ("$output_path$pathSeparator$input_path", 0777)) {
	    die "Error: $output_path$pathSeparator$input_path does not exist. Exiting. \n$!\n";
	}
    }

    open(OUTFILE, ">$output_file") || die "Can't write $output_file.\n";
    if ($^O =~ /MacOS/io) {MacPerl::SetFileInfo('R*ch', 'TEXT', "$output_file");};

    my $inComment = 0;
    my $text = "";
    my $localDebug = 0;
    foreach my $line (@inputLines) {
	print STDERR "line $line\n" if ($localDebug);
	print STDERR "inComment $inComment\n" if ($localDebug);
        if (($line =~ /^\/\*\!/o) || (($lang eq "java" || $HeaderDoc::parse_javadoc) && ($line =~ /^\s*\/\*\*[^*]/o))) {  # entering headerDoc comment
		# on entering a comment, set state to 1 (in comment)
		$inComment = 1;
	}
	if ($inComment && ($line =~ /\*\//o)) {
		# on leaving a comment, set state to 2 (leaving comment)
		$inComment = 2;
	}

	if (!$inComment) { $text .= $line; }

	if ($inComment == 2) {
		# state change back to 0 (we just skipped the last line of the comment)
		$inComment = 0;
	}
    }

# print STDERR "text is $text\n";
    print OUTFILE $text;

    close OUTFILE;
}

# /*! @abstract
#         Grabs any #include directives.
#  */
sub processIncludes($$$)
{
    my $lineArrayRef = shift;
    my $pathname = shift;
    my $lang = shift;
    my $sublang = shift;

    my @lines = @{$lineArrayRef};
    my $filename = basename($pathname);
    my $ah = HeaderDoc::AvailHelper->new();

    my @includeList = ();

    my $availDebug = 0;

    # The next few lines were a bad idea.  If you have two files
    # with the same name, the include lists got merged....
    # my $includeListRef = $HeaderDoc::perHeaderIncludes{$fullpath};
    # if ($includeListRef) {
	# @includeList = @{$includeListRef};
    # }

    my @ranges = ();
    my @rangestack = ();

    my $linenum = 1;
    my $continuation = 0;
    my $contline = "";
    my $inComment = 0;

    my $parseTokensRef = parseTokens($lang, $sublang);

    foreach my $line (@lines) {
      $inComment = prefilterCommentCheck($line, $parseTokensRef, $inComment);
      # print STDERR "IC: $inComment\n";
      if ($continuation) {
	if ($line =~ /\\\s*$/) {
		$contline .= $line;
	} else {
		my $rangeref = pop(@rangestack);
		my $range = ${$rangeref};

		$contline .= $line;
		$continuation = 0;

		if ($HeaderDoc::auto_availability) {
			$range->text($ah->parseString($contline, $pathname, $linenum));
		}
		push(@rangestack, \$range);
	}
      } else {
	my $hackline = $line;
	if ($hackline =~ s/^\s*#(include|import)\s+//so && !$inComment) {
		my $incfile = "";
		if ($hackline =~ /^(<.*?>)/o) {
			$incfile = $1;
		} elsif ($hackline =~ /^(\".*?\")/o) {
			$incfile = $1;
		} else {
			warn "$pathname:$linenum: warning: Unable to determine include file name for \"$line\".\n";
		}
		if (length($incfile)) {
			push(@includeList, $incfile);
		}
	}
	if ($hackline =~ s/^\s*#ifdef\s+//so && !$inComment) {
		print STDERR "STARTRANGE ifdef: $hackline\n" if ($availDebug);
		my $range = HeaderDoc::LineRange->new();
		$range->start($linenum);
		push(@rangestack, \$range);
	}
	if ($hackline =~ s/^\s*#ifndef\s+//so && !$inComment) {
		print STDERR "STARTRANGE ifndef: $hackline\n" if ($availDebug);
		my $range = HeaderDoc::LineRange->new();
		$range->start($linenum);
		$range->text("");
		push(@rangestack, \$range);
	}
	if ($hackline =~ s/^\s*#if\s+//so && !$inComment) {
		print STDERR "STARTRANGE if: $hackline\n" if ($availDebug);
		my $range = HeaderDoc::LineRange->new();
		$range->start($linenum);

		if ($hackline =~ /\\\s*$/) {
			$continuation = 1;
		} else {
			if ($HeaderDoc::auto_availability) {
				$range->text($ah->parseString($hackline, $pathname, $linenum));
			}
		}

		push(@rangestack, \$range);
	}
	if ($hackline =~ s/^\s*#endif\s+//so && !$inComment) {
		print STDERR "ENDRANGE: $hackline\n" if ($availDebug);
		my $rangeref = pop(@rangestack);
		if ($rangeref) {
			my $range = ${$rangeref};
			bless($range, "HeaderDoc::LineRange");
			$range->end($linenum);
			if (length($range->text())) { push(@ranges, \$range); }
		} else {
			warn "$pathname:$linenum: warning: Unbalanced #endif found in prescan.\n";
		}
	}
	$linenum++;
      }
    }

    if (0) {
	print STDERR "Includes for \"$filename\":\n";
	foreach my $name (@includeList) {
		print STDERR "$name\n";
	}
    }
    if ($availDebug) {
	print STDERR "Ranges for \"$filename\":\n";
	foreach my $rangeref (@ranges) {
		my $range = ${$rangeref};
		bless($range, "HeaderDoc::LineRange");
		print STDERR "-----\n";
		print STDERR "START: ".$range->start()."\n";
		print STDERR "END: ".$range->end()."\n";
		print STDERR "TEXT: ".$range->text()."\n";
	}
    }

    $HeaderDoc::perHeaderIncludes{$pathname} = \@includeList;
    $HeaderDoc::perHeaderRanges{$pathname} = \@ranges;
}

# /*!
#     @abstract
#         Checks for comment characters in a line and adjusts an
#         <code>inComment</code> variable accordingly, returning the new value.
#     @param line
#         The line to parse.
#     @param parseTokensRef
#         A set of parse tokens obtained with a call to {@link //apple_ref/perl/instm/HeaderDoc::Utilities/parseTokens//() parseTokens}.
#     @param inComment
#         The previous value of <code>inComment</code>.
#     @result
#         Returns the new value for <code>inComment</code>.
#  */
sub prefilterCommentCheck
{
    my $line = shift;
    my $parseTokensRef = shift;
    my $inComment = shift;

    my $localDebug = 0;

    my %parseTokens = %{$parseTokensRef};
    my $soc = $parseTokens{soc};
    my $eoc = $parseTokens{eoc};
    my $ilc = $parseTokens{ilc};
    my $ilc_b = $parseTokens{ilc_b};

    my @parts = ();

    if ($soc && $ilc && $ilc_b) {
	@parts = split(/(\Q$soc\E|\Q$eoc\E|\Q$ilc\E|\Q$ilc_b\E|[\r\n])/, $line);
    } elsif ($soc && $ilc) {
	@parts = split(/(\Q$soc\E|\Q$eoc\E|\Q$ilc\E|[\r\n])/, $line);
    } elsif ($ilc && $ilc_b) {
	@parts = split(/(\Q$ilc\E|\Q$ilc_b\E|[\r\n])/, $line);
    } elsif ($ilc) {
	@parts = split(/(\Q$ilc\E|[\r\n])/, $line);
    } else {
	return 0;
    }

    # This is processing a new line, so single-line comments from
    # the previous line are always ignored.
    if ($inComment == 2) { $inComment = 0; }

    foreach my $part (@parts) {
	print STDERR "checking $part (SOC: $soc ILC: $ilc ILC_B: $ilc_b EOC: $eoc)\n" if ($localDebug);
	if (($eoc) && ($part eq $eoc) && ($inComment == 1)) {
		$inComment = 0;
		print STDERR "GOT EOC\n" if ($localDebug);

	} elsif (($part =~ /[\r\n]/) && ($inComment == 2)) {
		# The "line" passed in may contain multiple lines, so we have to
		# do this check.

		print STDERR "GOT NEWLINE IN ILC\n" if ($localDebug);
		$inComment = 0;

	} elsif (!$inComment) {
		if (($soc) && ($part eq $soc)) {
			print STDERR "GOT SOC\n" if ($localDebug);
			$inComment = 1;
		} elsif (($ilc) && ($part eq $ilc)) {
			print STDERR "GOT ILC\n" if ($localDebug);
			$inComment = 2;
		} elsif (($ilc_b) && ($part eq $ilc_b)) {
			print STDERR "GOT ILC_B\n" if ($localDebug);
			$inComment = 2;
		}
	}
    }

    return $inComment;

}

my %pathForInclude;

# /*!
#     @abstract
#         Reorders a list of C headers in dependency order.
#     @discussion
#         The dependency calculation is fairly straightforward.  For 
#         each header, HeaderDoc reads the list of <code>#include</code>
#         and <code>#import</code> directives.  Then, for each input file:
#
#         <ul>
#             <li>HeaderDoc looks to see if a dependency object with that filename exists.  A
#                 preexisting dependency object can occur for two reasons: because another
#                 header has declared a dependency on it previously or because another header
#                 with the same name has already been scanned.</li>
#             <li>If the dependency exists and the <code>EXISTS</code> flag is set on that
#                 object, HeaderDoc knows that it has already processed a header with the
#                 same name, and HeaderDoc emits a warning, then creates a new dependency
#                 object.</li>
#             <li>If the dependency object exists and the <code>EXISTS</code> flag is not set.
#                 HeaderDoc sets the <code>EXISTS</code> flag on the existing dependency object.</li>
#             <li>If the dependency object does not exist, it creates a new node and sets the
#                 <code>EXISTS</code> flag.</li>
#             <li>HeaderDoc creates dependencies for each header that it includes, nested within
#                 the dependency object for this input file.</li>
#         </ul>
#
#         After creating these child dependencies for every header, the result is a graph of
#         dependencies, with cycles.
#
#         Finally, the code performs a depth-first walk of the graph (with cycle detection).
#         Because each object is guaranteed to be lower in the graph for at least one path
#         through the graph than any file on which it depends (ignoring circular dependencies),
#         this is sufficient to ensure that any file is processed prior to any file that it
#         includes.
#
#     @result
#         Returns the result of a depth-first walk of the dependency graph in the form of a
#         dependency-ordered array.
#
#     @var force
#         Set if the dependency object was found, but refers to a different header
#         (<code>EXISTS</code> is set).  This forces a new object to be created in
#         spite of the existence of another object with the same name.
#  */
sub fix_dependency_order
{
    my $inputlistref = shift;
    my @inputfiles = @{$inputlistref};
    my $treetop = undef;
    # my %refhash = ();
    my $localDebug = 0;

    %pathForInclude = ();

    print STDERR "Scanning dependencies.\n" if ($localDebug || $debugging);
    my $foundcount = 0;
    foreach my $rawfilename (@inputfiles) {
	my $filename = basename($rawfilename);
	my $fullpath=getAbsPath($rawfilename);
	$pathForInclude{$filename} = $rawfilename;
	print STDERR "IN FILE: $filename:\n" if ($localDebug);
	# my $dep = HeaderDoc::Dependency->new();
	my $curnoderef = HeaderDoc::Dependency->findname($filename);
	my $curnode = undef;
	my $force = 0;
	if ($curnoderef) {
		print STDERR "Node exists\n" if ($localDebug);
		$curnode = ${$curnoderef};
		bless($curnode, "HeaderDoc::Dependency");
		if ($curnode->{EXISTS}) {
			print STDERR "Node marked with EXISTS.  Setting force -> 1\n" if ($localDebug);
			warn "WARNING: Multiple files named \"$filename\" found in argument\n".
			     "list.  Dependencies may not work as expected.\n";
			$force = 1;
		}
	}
	if (!$curnoderef || $force) {
		print STDERR "CNR: $curnoderef FORCE: $force\n" if ($localDebug);
		$curnode = HeaderDoc::Dependency->new();
		if (!$treetop) {
			$treetop = $curnode;
			$curnode = HeaderDoc::Dependency->new();
		}
		$curnode->name($rawfilename);
		$curnode->depname($filename);
		$curnode->{EXISTS} = 1;
	} else {
		print STDERR "CNR: $curnoderef\n" if ($localDebug);
		$curnode = ${$curnoderef};
		bless($curnode, "HeaderDoc::Dependency");
		print STDERR "    CN: $curnode\n" if ($localDebug);
		$curnode->name($rawfilename);
		$curnode->{EXISTS} = 1;
		$foundcount ++;
	}
        foreach my $include (@{$HeaderDoc::perHeaderIncludes{$fullpath}}) {
                print STDERR "    COMPARE INCLUDE: $include\n" if ($localDebug);
                my $tempname = $include;
		# my @oldlist = ();
                $tempname =~ s/^\s*//s;
                $tempname =~ s/\s*$//s;
                if ($tempname !~ s/^\<(.*)\>$/$1/s) {
                        $tempname =~ s/^\"(.*)\"$/$1/s;
                }
		my $rawincname = $tempname;
                $tempname = basename($tempname);
                print STDERR "    TMPNM: $tempname\n" if ($localDebug);
		# if ($refhash{$tempname}) {
			# @oldlist = @{$refhash{$tempname}};
		# }
		# push(@oldlist, $filename);
		# $refhash{$tempname} = \@oldlist;

		my $noderef = HeaderDoc::Dependency->findname($tempname);
		my $node = undef;
		if (!$noderef) {
			print STDERR "No existing reference found.\n" if ($localDebug);
			$node = HeaderDoc::Dependency->new();
			$node->name($rawincname);
			$node->depname($tempname);
		} else {
			print STDERR "Existing reference found.\n" if ($localDebug);
			$node = HeaderDoc::Dependency->new();
			$node = ${$noderef};
			bless($node, "HeaderDoc::Dependency");
		}
		$curnode->addchild($node);
		# print STDERR "$curnode -> $node\n";
	}
	$treetop->addchild($curnode);
    }
print STDERR "foundcount: $foundcount\n" if ($localDebug);

    # $treetop->dbprint() if ($localDebug);

    print STDERR "doing depth-first traversal.\n" if ($localDebug || $debugging);
    my $ret = depthfirst($treetop);
    if ($localDebug) {
	foreach my $entry (@{$ret}) {
		print STDERR "$entry ";
	}
    }
    $treetop = undef;
    print STDERR "\ndone.\n" if ($localDebug || $debugging);
    return $ret;
}

my @deplevels = ();
# /*!
#     @abstract
#         Sets node depth information in the tree structure
#         as part of the depth-first tree walk code.
#  */
sub set_node_depths
{
    my $node = shift;
    my $depth = shift;
    my $localDebug = 0;

    if ($depth <= 1) { print STDERR "Generating depth for ".$node->{NAME}."\n" if ($localDebug); }

    if ($node->{MARKED}) {
	# Avoid infinite recursion or reparenting nodes to deeper depth than things they include.
	return;
    }
    $node->{MARKED} = 1;

    if ($node->{DEPTH} <= $depth || !$node->{DEPTH}) {
	# print STDERR "NODE DEPTH NOW $depth\n" if ($localDebug);
	$node->{DEPTH} = $depth;
    } else {
	# Nothing to do.
	$node->{MARKED} = 0;
	return;
    }

    foreach my $childref (@{$node->{CHILDREN}}) {
	my $child = ${$childref};
	bless($child, "HeaderDoc::Dependency");
	set_node_depths($child, $depth + 1);
    }

    $node->{MARKED} = 0;
}

my $maxdependencydepth = 0;

# /*!
#     @abstract
#         Lays out dependencies in a tree structure.
#  */
sub generate_depth_levels
{
    my $node = shift;
    my $depth = shift;
    my $localDebug = 0;

    if ($node->{MARKED}) {
	# Avoid infinite recursion or reparenting nodes to deeper depth than things they include.
	return;
    }
    $node->{MARKED} = 1;

    print STDERR "NODE DEPTH: ".$node->{DEPTH}."\n" if ($localDebug);;

    my @levelarr = ();
    if ($deplevels[$node->{DEPTH}]) {
	@levelarr = @{$deplevels[$node->{DEPTH}]};
    }
    push(@levelarr, \$node);
    $deplevels[$node->{DEPTH}] = \@levelarr;
    if ($node->{DEPTH} > $maxdependencydepth) {
	print STDERR "MAX DEPTH: $maxdependencydepth -> " if ($localDebug);
	$maxdependencydepth = $node->{DEPTH};
	print STDERR "$maxdependencydepth\n" if ($localDebug);
    }

    foreach my $childref (@{$node->{CHILDREN}}) {
	my $child = ${$childref};
	bless($child, "HeaderDoc::Dependency");
	generate_depth_levels($child, $depth + 1);
    }
}

# /*!
#     @abstract
#         Depth-first tree walk used in determining dependency order.
#  */
sub depthfirst
{
	my @rawfiles = ();
	my $treetop = shift;
	# my $debugging = 1;

	print STDERR "Doing recursive sort by depth\n" if ($debugging);
	# my $depth = depthfirst_rec(\$treetop, 0);

	set_node_depths($treetop, 0);
	print STDERR "Generating depth levels\n" if ($debugging);
	generate_depth_levels($treetop);
	my $depth = $maxdependencydepth;

	$treetop->dbprint() if ($debugging);

	print STDERR "Sweeping levels from depth $maxdependencydepth:\n" if ($debugging);

	my $level = $depth;
	while ($level >= 0) {
		print STDERR "Level $level\n" if ($debugging);
		my @array = ();
		if ($deplevels[$level]) {
			@array = @{$deplevels[$level]};
		} else {
			print STDERR "No entries at level $level.  How peculiar.\n" if ($debugging);
		}
		foreach my $dep (@array) {
			$dep = ${$dep};
			bless($dep, "HeaderDoc::Dependency");
			print STDERR "Adding ".$dep->name()."\n" if ($debugging);
			# if ($pathForInclude{$dep->depname}) {
			if ($dep->{EXISTS}) {
				# push(@rawfiles, $pathForInclude{$dep->depname});
				push(@rawfiles, $dep->name());
			}
			# } else {
				# warn("DNE: ".$dep->name()."\n");
			# }
		}
		$level--;
	}
	print STDERR "done sweeping.\n" if ($debugging);

	my @files = ();
	my %namehash = ();
	my $filename;
	foreach $filename (@inputFiles) {
		# my $bn = basename($filename);
		print STDERR "File: $filename\n" if ($debugging);
		$namehash{$filename} = 1;
	}
	foreach my $filename (@rawfiles) {
		if (length($filename)) {
			# my $bn = basename($filename);
			if ($namehash{$filename}) {
				print STDERR "pushing $filename\n" if ($debugging);
				push(@files, $filename);
				$namehash{$filename} = 0; # include once.
			} else {
				print STDERR "skipping $filename\n" if ($debugging);
			}
		}
	}

	return \@files;
}

my %pathparts = ();
# /*!
#     @abstract
#         Recursive portion of depth-first tree walk used
#         in determining dependency order.
#  */
sub depthfirst_rec
{
	my $noderef = shift;
	my $level = shift;
	my $maxlevel = $level;
	my $norecurse = 0;
	# print STDERR "Depth: $level\n";

	if (!$noderef) { return; }
	# print STDERR "NODEREF: $noderef\n";

	my $node = ${$noderef};
	bless($node, "HeaderDoc::Dependency");
	# print STDERR "NAME: ".$node->name()."\n";

	if ($node->{MARKED}) {
		$norecurse = 1;
	}
	if ($pathparts{$node->depname()}) {
		return;
	}

	if ($node->{MARKED} < $level+1) {
		$node->{MARKED} = $level + 1;
	}

	# print STDERR "NODE: $node\n";
	if (!$norecurse && $node->{CHILDREN}) {
		my $opp = $pathparts{$node->depname()};
		if ($opp == undef) { $opp = 0; }
		$pathparts{$node->depname()} = 1;
		foreach my $child (@{$node->{CHILDREN}}) {
			my $templevel = depthfirst_rec($child, $level + 1);
			if ($templevel > $maxlevel) { $maxlevel = $templevel; }
		}
		$pathparts{$node->depname()} = $opp;
	}
	my @oldarr = ();
	if ($deplevels[$level]) {
		@oldarr = @{$deplevels[$level]};
	}
	push(@oldarr, \$node);
	$deplevels[$level] = \@oldarr;

	return $maxlevel;
}

# /*!
#     @abstract
#         Collects version info from HeaderDoc modules and prints.
#  */
sub printVersionInfo {
    my $bp = $HeaderDoc::BlockParse::VERSION;
    my $av = $HeaderDoc::APIOwner::VERSION;
    my $hev = $HeaderDoc::HeaderElement::VERSION;
    my $hv = $HeaderDoc::Header::VERSION;
    my $cppv = $HeaderDoc::CPPClass::VERSION;
    my $objcclassv = $HeaderDoc::ObjCClass::VERSION;
    my $objccnv = $HeaderDoc::ObjCContainer::VERSION;
    my $objccatv = $HeaderDoc::ObjCCategory::VERSION;
    my $objcprotocolv = $HeaderDoc::ObjCProtocol::VERSION;
    my $fv = $HeaderDoc::Function::VERSION;
    my $mv = $HeaderDoc::Method::VERSION;
    my $depv = $HeaderDoc::Dependency::VERSION;
    my $lr = $HeaderDoc::LineRange::VERSION;
    my $ah = $HeaderDoc::AvailHelper::VERSION;
    my $tv = $HeaderDoc::Typedef::VERSION;
    my $sv = $HeaderDoc::Struct::VERSION;
    my $cv = $HeaderDoc::Constant::VERSION;
    my $vv = $HeaderDoc::Var::VERSION;
    my $ev = $HeaderDoc::Enum::VERSION;
    my $uv = $HeaderDoc::Utilities::VERSION;
    my $me = $HeaderDoc::MinorAPIElement::VERSION;
    my $pd = $HeaderDoc::PDefine::VERSION;
    my $pt = $HeaderDoc::ParseTree::VERSION;
    my $ps = $HeaderDoc::ParserState::VERSION;
    my $ih = $HeaderDoc::IncludeHash::VERSION;
    my $rg = $HeaderDoc::Regen::VERSION;
    
	print STDERR "---------------------------------------------------------------------\n";
	print STDERR "\tHeaderDoc Version: ".$HeaderDoc_Version."\n\n";

	print STDERR "\theaderDoc2HTML - $VERSION\n";
	print STDERR "\tModules:\n";
	print STDERR "\t\tAPIOwner - $av\n";
	print STDERR "\t\tAvailHelper - $ah\n";
	print STDERR "\t\tBlockParse - $bp\n";
	print STDERR "\t\tCPPClass - $cppv\n";
	print STDERR "\t\tConstant - $cv\n";
	print STDERR "\t\tDependency - $depv\n";
	print STDERR "\t\tEnum - $ev\n";
	print STDERR "\t\tFunction - $fv\n";
	print STDERR "\t\tHeader - $hv\n";
	print STDERR "\t\tHeaderElement - $hev\n";
	print STDERR "\t\tIncludeHash - $ih\n";
	print STDERR "\t\tLineRange - $lr\n";
	print STDERR "\t\tMethod - $mv\n";
	print STDERR "\t\tMinorAPIElement - $me\n";
	print STDERR "\t\tObjCCategory - $objccatv\n";
	print STDERR "\t\tObjCClass - $objcclassv\n";
	print STDERR "\t\tObjCContainer - $objccnv\n";
	print STDERR "\t\tObjCProtocol - $objcprotocolv\n";
	print STDERR "\t\tPDefine - $pd\n";
	print STDERR "\t\tParseTree - $pt\n";
	print STDERR "\t\tParserState - $ps\n";
	print STDERR "\t\tStruct - $sv\n";
	print STDERR "\t\tTypedef - $tv\n";
	print STDERR "\t\tUtilities - $uv\n";
	print STDERR "\t\tVar - $vv\n";
	print STDERR "---------------------------------------------------------------------\n";
}

# /*!
#     @abstract
#         Test code for dumping notes in dependency tree.
#  */
sub SDump
{
    my $arg = shift;
    my $text = shift;

    print STDERR "At position $text:\n";
    Dump($arg);
    print STDERR "End dump\n";

}

# /*!
#     @abstract
#         Creates a new test for the test framework.
#     @discussion See
#         {@linkdoc //apple_ref/doc/uid/TP40001215 HeaderDoc User Guide}
#         for info about creating tests.
#  */
sub newtest
{
    $/ = "\n";
    print STDERR "Enter name of test\n";
    my $name = <STDIN>;
    $name =~ s/\n$//s;

    my $lang = "";
    my $sublang = "";
    while ($lang !~ /^(C|java|javascript|pascal|php|perl|Csource|shell|csh|IDL|MIG|ruby|python|applescript|tcl)$/) {
	print STDERR "Enter language (C|java|javascript|pascal|php|perl|Csource|shell|csh|IDL|MIG|ruby|python|applescript|tcl)\n";
	$lang = <STDIN>;
	$lang =~ s/\n$//s;
	if ($lang eq "IDL") {
		$lang = "C";
		$sublang = "IDL";
	} elsif ($lang eq "MIG") {
		$lang = "C";
		$sublang = "MIG";
	} elsif ($lang eq "csh") {
		$lang = "shell";
		$sublang = "csh";
	} elsif ($lang eq "javascript") {
		$lang = "java";
		$sublang = "javascript";
	} else {
		$sublang = $lang;
	}
    }
    $HeaderDoc::lang = $lang;
    $HeaderDoc::sublang = $sublang;

    my $type = "";
    if ($lang eq "C" || $lang eq "Csource") {
	while ($type !~ /(parser|cpp)/) {
		print STDERR "Enter type of test (parser|cpp)\n";
		$type = <STDIN>;
		$type =~ s/\n$//s;
	}
    } else  {
	$type = "parser";
    }

    $/ = undef;
    my $cppcode = "";
    my $comment = "";

    if ($type eq "parser") {
	print STDERR "Paste in HeaderDoc comment block.\nPress control-d on a new line when done.\n";
	$comment = <STDIN>;
	seek(STDIN,0,0);

	print STDERR "Paste in block of code.\nPress control-d on a new line when done.\n";
    } else {
	print STDERR "Paste in initial macros.\nPress control-d on a new line when done.\n";
	$cppcode = <STDIN>;
	seek(STDIN,0,0);

	print STDERR "Paste in block of code to permute with this macro.\nPress control-d on a new line when done.\n";
    }
    my $code = <STDIN>;
    seek(STDIN,0,0);

    print STDERR "Optionally paste or type in a message to be displayed if the test fails.\nPress control-d on a new line when done.\n";
    my $failmsg = <STDIN>;
    seek(STDIN,0,0);

    my $test = HeaderDoc::Test->new( "NAME" => $name, "COMMENT" => $comment, "CODE" => $code, "LANG" => $lang, "SUBLANG" => $sublang, "TYPE" => $type, "CPPCODE" => $cppcode, "FAILMSG" => $failmsg );

    # Don't check return value here.  The "utilities" test will always fail
    # because the file has not yet been written to disk.
    $test->runTest();

    $test->{EXPECTED_RESULT} = $test->{RESULT};
    $test->{EXPECTED_RESULT_ALLDECS} = $test->{RESULT_ALLDECS};
    my $filename = $test->{FILENAME};
    # $filename =~ s/[^a-zA-Z0-9_.,-]/_/sg;

    my $testdir = $HeaderDoc::testdir;
    if (-d "$testdir") {
	if ($type eq "parser") {
    		$filename = "$testdir/parser_tests/$filename";
	} else {
    		$filename = "$testdir/c_preprocessor_tests/$filename";
	}
    } else {
    	$filename = "/tmp/$filename.test";
    }

    if (-f $filename) {
	print "You are about to overwrite an existing test case.  Continue? (yes|no)\n";
	$/ = "\n";
	my $reply = <STDIN>;
	$reply =~ s/\n$//s;
	if ($reply ne "yes") {
		print "Cancelled.\n";
		exit(-1);
	}
    }
    $test->writeToFile($filename);
    $test->writeToPlist($filename);
    print "Wrote test data to \"$filename\"\n";
    $test->dbprint();
}


# /*!
#     @abstract
#         Runs a test using the test framework.
#     @discussion See
#         {@linkdoc //apple_ref/doc/uid/TP40001215 HeaderDoc User Guide}
#         for info about running tests.
#  */
sub runtests
{
    my $mode = shift;
    my $argref = shift;
    my @args = @{$argref};

    # my $testdir = $HeaderDoc::testdir;
    # my $filename = "$testdir/parser_tests/test.test";
    my $ok_count = 0;
    my $fail_count = 0;
    my @testlist = undef;

    my $update = 0;
    if ($mode eq "update") {
	$update = 1;
    }
    my $force = 0;
    if ($mode eq "forceupdate") {
	$update = 1;
	$force = 1;
    }


    my %config = (
	cCompiler => "/usr/bin/gcc"
    );

    my $localConfigFileName = "headerDoc2HTML.config";
    my $preferencesConfigFileName = "com.apple.headerDoc2HTML.config";

    my $CWD = cwd();
    my @configFiles = ($devtoolsPreferencesPath.$pathSeparator.$preferencesConfigFileName, $systemPreferencesPath.$pathSeparator.$preferencesConfigFileName, $usersPreferencesPath.$pathSeparator.$preferencesConfigFileName, $Bin.$pathSeparator.$localConfigFileName, $CWD.$pathSeparator.$localConfigFileName);

    %config = &updateHashFromConfigFiles(\%config,\@configFiles);

    $HeaderDoc::c_compiler = $config{cCompiler};

    print STDERR "Using C compiler: ".$HeaderDoc::c_compiler."\n";

    if ($#args == -1) {
	my ($pyok, $pybad) = HeaderDoc::PythonParse::runPythonSpaceTests();
	my ($macrook, $macrobad) = HeaderDoc::MacroFilter::run_macro_filter_tests();
	my ($resolvelinksok, $resolvelinksbad) = runResolveLinksTests();

	$ok_count += ($pyok + $macrook + $resolvelinksok);
	$fail_count += ($pybad + $macrobad + $resolvelinksbad);

	my $testdir = $HeaderDoc::testdir;

	print "-= Running parser tests =-\n\n";

	# @testlist = <$testdir/parser_tests/*.test>;
	opendir(DIR, "$testdir/parser_tests");
	@testlist = grep(/\.test$/,readdir(DIR));
	closedir(DIR);

	map(s/^/$testdir\/parser_tests\//, @testlist);

	my $dump;
	if ($mode eq "dump" || $mode eq "dump_parser") {
		$dump = 1;
	} else {
		$dump = 0;
	}
	my ($newok, $newfail) = runtestlist(\@testlist, $dump, $update, $force);
	$ok_count += $newok;
	$fail_count += $newfail;

	print "-= Running C preprocessor tests =-\n\n";

	# @testlist = <$testdir/c_preprocessor_tests/*.test>;
	opendir(DIR, "$testdir/c_preprocessor_tests");
	@testlist = grep(/\.test$/,readdir(DIR));
	closedir(DIR);

	map(s/^/$testdir\/c_preprocessor_tests\//, @testlist);

	if ($mode eq "dump" || $mode eq "dump_cpp") {
		$dump = 1;
	} else {
		$dump = 0;
	}
	($newok, $newfail) = runtestlist(\@testlist, $dump, $update, $force);
	$ok_count += $newok;
	$fail_count += $newfail;

    } else {
	my $dump;
	if ($mode eq "dump") {
		$dump = 1;
	} else {
		$dump = 0;
	}
	my ($newok, $newfail) = runtestlist($argref, $dump, $update, $force);
	$ok_count += $newok;
	$fail_count += $newfail;
    }

    print "\n\n-= SUMMARY =-\n\n";
    print "Tests passed: $ok_count\n";
    print "Tests failed: $fail_count\n";

    print "Percent passed: ";
    if ($fail_count != 0) {
	print "\e[31m";
    } else {
	print "\e[32m";
    }

    if ($ok_count || $fail_count) {
    	print "".(($ok_count / ($fail_count + $ok_count)) * 100)."\%\n";
    } else {
	print "NaN\n";
    }

    print "\e[39m\n";

    if ($fail_count) { $HeaderDoc::exitstatus = -1; }
}

# /*!
#     @abstract
#         Runs multiple tests using the test framework.
#     @discussion See
#         {@linkdoc //apple_ref/doc/uid/TP40001215 HeaderDoc User Guide}
#         for info about running tests.
#  */
sub runtestlist
{
	my $testlistref = shift;
	my @testlist = @{$testlistref};
	my $dump = shift;
	my $update = shift;
	my $force = shift;

	my $ok_count = 0;
	my $fail_count = 0;

	my @ignore_re = ();
	foreach my $filename (sort {uc($a) cmp uc($b)} @testlist) {
		if ($filename !~ /\.test$/) {
			print STDERR "$filename does not appear to be a test.  Skipping.\n";
			next;
		}
		my $test = HeaderDoc::Test->new();
		$test->readFromFile($filename);

		my $plist = $filename;
		$plist =~ s/\.test$/\.plist/g;
		if (! -f $plist) {
			$test->writeToPlist($filename);
		}
		print "Test \"".$test->{NAME}."\": ";

		my $coretestfail = $test->runTest(\@ignore_re);
		if ($coretestfail) {
			die("\nTest suite aborted.  Utilities tests failed.\n");
		}

		if ($dump) {
			print "RESULTS DUMP:\n".$test->{RESULT}."\n";
		}
		if ((($test->{RESULT} ne $test->{EXPECTED_RESULT}) ||
		     ($test->{RESULT_ALLDECS} ne $test->{EXPECTED_RESULT_ALLDECS})) &&
		    ($test->{FILTERED_RESULT} eq $test->{EXPECTED_FILTERED_RESULT}) &&
		    ($test->{FILTERED_RESULT_ALLDECS} eq $test->{EXPECTED_FILTERED_RESULT_ALLDECS})) {
			# Expected change caught by the filter.

			print STDERR "Passed after filtering.  Updating test automatically.\n";
			$test->{EXPECTED_RESULT} = $test->{RESULT};
			$test->{EXPECTED_RESULT_ALLDECS} = $test->{RESULT_ALLDECS};
			$test->writeToFile($filename);
			$test->writeToPlist($filename);
			$ok_count++;
		} elsif (($test->{FILTERED_RESULT} eq $test->{EXPECTED_FILTERED_RESULT}) &&
		    ($test->{FILTERED_RESULT_ALLDECS} eq $test->{EXPECTED_FILTERED_RESULT_ALLDECS})) {
				print "\e[32mOK\e[39m\n";
				# if ($dump) {
					# $test->showresults(); 
					# $test->dbprint();
				# }
				$ok_count++;

			if ($force) {
				$test->writeToFile($filename);
				$test->writeToPlist($filename);
			}

			# $test->showresults();
		} else {
			my $adonly = 0;
			if ($test->{FILTERED_RESULT} eq $test->{EXPECTED_FILTERED_RESULT}) {
				print "\e[31mFAILED (ALLDECS ONLY)\e[39m\n";
				$adonly = 1;
				if ($debugging || 1) {
					if ($test->{RESULT_ALLDECS} eq $test->{EXPECTED_RESULT}) {
						print STDERR "Results same as with alldecs off\n";
					} else {
						print STDERR "\@\@\@ ALLDECS RESULT:\@\@\@\n".$test->{RESULT_ALLDECS}."\n\n\@\@\@EXPECTED NON-ALLDECS RESULT:\@\@\@\n".$test->{EXPECTED_RESULT}."\n\n\@\@\@END OF RESULTS\@\@\@\n\n";
					}
				}
			} else {
				print "\e[31mFAILED\e[39m\n";
			}
			if ($dump || $update) { $test->showresults(); }

			if ($update) {
				my $continue_update = 1;
				while ($continue_update) {
					print "If these changes are expected, please type 'confirm' now.\n";
					print "For more information, type 'more' now.\n";
					print "To run 'diff' on the named objects, type 'less' now.\n";
					print "To skip, type 'skip' now.\n";
					print "To ignore a regexp, type 'ignore <expression>' now.\n";
					$/ = "\n";
					my $temp = <STDIN>;
					if ($temp =~ /^\s*less\s*$/) {
						my $addata = "";
						my $adexpdata = "";
						print "\nTest \"".$test->{NAME}."\":\n";
						if ($adonly) {
							print "\e[31m";
							print STDERR "******** DUMPING ALLDECS RESULT ********";
							print "\e[39m\n";
							$adexpdata = $test->{EXPECTED_RESULT};
							$addata = $test->{RESULT};
 							$test->{EXPECTED_RESULT} = $test->{EXPECTED_RESULT_ALLDECS};
 							$test->{RESULT} = $test->{RESULT_ALLDECS};
						}
						$test->showresults(-1);
						if ($adonly) {
 							$test->{EXPECTED_RESULT} = $adexpdata;
 							$test->{RESULT} = $addata;
						}
					} elsif ($temp =~ /^\s*more\s*$/) {
						print "\nTest \"".$test->{NAME}."\":\n";
						$test->showresults(1);
						$test->dbprint();
					} elsif ($temp =~ /^\s*confirm\s*$/) {
						$test->{EXPECTED_RESULT} = $test->{RESULT};
						$test->{EXPECTED_RESULT_ALLDECS} = $test->{RESULT_ALLDECS};
						$test->writeToFile($filename);
						$test->writeToPlist($filename);
						$ok_count++; $continue_update = 0;
					} elsif ($temp =~ /^\s*skip\s*$/) {
						$fail_count++; $continue_update = 0;
					} elsif ($temp =~ s/^\s*ignore\s*//s) {
						$temp =~ s/[\n\r]*$//s;
						push(@ignore_re, $temp);

						# FIXME DAG: Make this work.  (Requires rolling back
						# the apple_ref lookups and stuff.)
						# my $coretestfail = $test->runTest(\@ignore_re);

						if (($test->{FILTERED_RESULT} eq $test->{EXPECTED_FILTERED_RESULT}) &&
		    					($test->{FILTERED_RESULT_ALLDECS} eq $test->{EXPECTED_FILTERED_RESULT_ALLDECS})) {
							print STDERR "It passes now.\n";

							$test->{EXPECTED_RESULT} = $test->{RESULT};
							$test->{EXPECTED_RESULT_ALLDECS} = $test->{RESULT_ALLDECS};
							$test->writeToFile($filename);
							$test->writeToPlist($filename);
							$ok_count++; $continue_update = 0;
						} else {
							print STDERR "Still failed.  (At some point, re-running a test will work, but not yet.)\n";
							# print STDERR "EXPECTED: \n";
							# print STDERR $test->{EXPECTED_FILTERED_RESULT}."\n";
							# print STDERR "GOT: \n";
							# print STDERR $test->{FILTERED_RESULT}."\n";
						}
					} else {
						$temp =~ s/\n$//s;
						print "Unknown response \"$temp\"\n";
					}
				}
			} else {
				$fail_count++;
			}
		}
	}

	return ($ok_count, $fail_count);
}

# /*!
#     @abstract
#         Sets the TOC format value based on its name.
#     @discussion
#
#         Returns values via <code>$HeaderDoc::newTOC</code>.  Possible values are:
#
#         0 Old TOC style (ugly).
#         1 Apple old-style TOC.
#         2 Apple interim TOC.
#         3 Apple new-style TOC.
#         4 Unused.
#         5 Public new-style TOC.
# */
sub setTOCFormat
{
	my $format = shift;

	$format =~ s/\s*//sg;

	if ($HeaderDoc::flagDashF) {
		# Don't change anything; format specified on command line.
		return;
	}

	if ($format =~ /default/i || $format =~ /div/i) {
		$HeaderDoc::newTOC = 5;
		# print STDERR "DEFAULT\n";
	} elsif ($format =~ /iframes/i) {
		$HeaderDoc::newTOC = 0;
		$HeaderDoc::use_iframes = 1;
		# print STDERR "IFRAMES\n";
	} elsif ($format =~ /frames/i) {
		$HeaderDoc::newTOC = 0;
		$HeaderDoc::use_iframes = 0;
		# print STDERR "OLD-STYLE FRAMES\n";
	} else {
		print STDERR "Unknown TOC format \"$format\"\n";
	}

	if ($HeaderDoc::use_iframes || $HeaderDoc::newTOC) {
        	$HeaderDoc::ClassAsComposite = 1;
	} elsif ($HeaderDoc::flagDashC == -1) {
        	$HeaderDoc::ClassAsComposite = 0;
	} else {
        	$HeaderDoc::ClassAsComposite = 1;
	}

	# $HeaderDoc::newTOC = 0;
}

# /*!
#     @abstract
#         Runs the resolveLinks test suite.
#  */
sub runResolveLinksTests
{
	my $rltestdir = $HeaderDoc::testdir."/resolvelinks";
	my $curdir = cwd();
	my $okcount = 0;
	my $failcount = 0;

	print "-= Running resolveLinks tests =-\n\n";

	chdir($rltestdir) || die("Could not change directories into resolveLinks test directory.\n");;

	# print "RLT: $rltestdir\n";

	open(TESTRESULTS, "./runtests.sh --fromperl|") || die("Could not run resolveLinks tests.\n");

	my $temp = $/;
	$/ = "\n";

	while (<TESTRESULTS>) {
		my $line = $_;
		if ($line =~ s/^PERLSTAT RESOLVELINKS:\s+//) {
			my @parts = split(/\s/, $line);
			$okcount = $parts[0];
			$failcount = $parts[1];
		} else {
			print $line;
		}
	}
	$/ = $temp;

	close(TESTRESULTS);

	chdir($curdir);

	print "\n";

	return ($okcount, $failcount);
}



################################################################################
# Version Notes
# 1.61 (02/24/2000) Fixed getLineArrays to respect paragraph breaks in comments that 
#                   have an asterisk before each line.
################################################################################

