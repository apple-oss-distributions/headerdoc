#!/usr/bin/perl
#
# Script name: headerDoc2HTML
# Synopsis: Scans a file for headerDoc comments and generates an HTML
#           file from the comments it finds.
#
# Author: Matt Morse (matt@apple.com)
# Last Updated: $Date: 2004/06/13 02:09:00 $
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
# $Revision: 1.28.2.16.2.125 $
#####################################################################

my $VERSION = 2.1;
################ General Constants ###################################
my $isMacOS;
my $pathSeparator;
my $specifiedOutputDir;
my $export;
my $debugging;
my $testingExport = 0;
my $printVersion;
my $quietLevel;
my $xml_output;
my $man_output;
my $headerdoc_strip;
my $regenerate_headers;
my $write_control_file;
#################### Locations #####################################
# Look-up tables are used when exporting API and doc to tab-delimited
# data files, which can be used for import to a database.  
# The look-up tables supply uniqueID-to-APIName mappings.

my $lang = "C";
my $scriptDir;
my $lookupTableDirName;
my $lookupTableDir;
my $dbLookupTables;
my $functionFilename;
my $typesFilename;
my $enumsFilename;
my $masterTOCName;
my @inputFiles;
# @HeaderDoc::ignorePrefixes = ();
# @HeaderDoc::perHeaderIgnorePrefixes = ();
# %HeaderDoc::perHeaderIncludes = ();
my $reprocess_input = 0;
my $functionGroup = "";
# $HeaderDoc::outerNamesOnly = 0;
$HeaderDoc::globalGroup = "";
my @headerObjects;	# holds finished objects, ready for printing
					# we defer printing until all header objects are ready
					# so that we can merge ObjC category methods into the 
					# headerObject that holds the class, if it exists.
my @categoryObjects;	    # holds finished objects that represent ObjC categories
my %objCClassNameToObject;	# makes it easy to find the class object to add category methods to

%HeaderDoc::appleRefUsed = ();
%HeaderDoc::availability_defs = ();

my @classObjects;
					
# Turn on autoflushing of 'print' output.  This is useful
# when HeaderDoc is operating in support of a GUI front-end
# which needs to get each line of log output as it is printed. 
$| = 1;

# Check options in BEGIN block to avoid overhead of loading supporting 
# modules in error cases.
my $uninstalledModulesPath;
BEGIN {
    use FindBin qw ($Bin);
    use Cwd;
    use Getopt::Std;
    use File::Find;

    %HeaderDoc::ignorePrefixes = ();
    %HeaderDoc::perHeaderIgnorePrefixes = ();
    %HeaderDoc::perHeaderIncludes = ();
    $HeaderDoc::outerNamesOnly = 0;
    %HeaderDoc::namerefs = ();
    $HeaderDoc::uniquenumber = 0;
    $HeaderDoc::counter = 0;

    use lib '/Library/Perl/TechPubs'; # Apple configuration workaround
    use lib '/AppleInternal/Library/Perl'; # Apple configuration workaround

    my %options = ();
    $lookupTableDirName = "LookupTables";
    $functionFilename = "functions.tab";;
    $typesFilename = "types.tab";
    $enumsFilename = "enumConstants.tab";

    $scriptDir = cwd();
    $HeaderDoc::force_parameter_tagging = 0;
    $HeaderDoc::truncate_inline = 0;
    $HeaderDoc::dumb_as_dirt = 1;
    $HeaderDoc::add_link_requests = 1;
    $HeaderDoc::use_styles = 0;
    $HeaderDoc::ignore_apiuid_errors = 0;
    $HeaderDoc::maxDecLen = 60; # Wrap functions, etc. if declaration longer than this length

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
	
	foreach (qw(Mac::Files)) {
	    $MOD_AVAIL{$_} = eval "use $_; 1";
    }

    $HeaderDoc::twig_available = 0;
    foreach my $path (@INC) {
	# print "$path\n";
	my $name = $path.$pathSeparator."XML".$pathSeparator."Twig.pm";
	# print "NAME: $name\n";
	if (-f $name) {
		$HeaderDoc::twig_available = 1;
	}
    }
    if ($HeaderDoc::twig_available) {
	# This doesn't work!  Need alternate solution.
	# use HeaderDoc::Regen;
    }

    &getopts("CHOSXbdlhimo:qrstuvx", \%options);
    if ($options{v}) {
    	print "Getting version information for all modules.  Please wait...\n";
		$printVersion = 1;
		return;
    }

    if ($options{r}) {
# print "TWIG? $HeaderDoc::twig_available\n";
	if ($HeaderDoc::twig_available) {
		print "Regenerating headers.\n";
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

    if ($options{S}) {
	$HeaderDoc::IncludeSuper = 1;
    } else {
	$HeaderDoc::IncludeSuper = 0;
    }
    if ($options{C}) {
	$HeaderDoc::ClassAsComposite = 1;
    } else {
	$HeaderDoc::ClassAsComposite = 0;
    }

    if ($options{b}) {
	# "basic" mode - turn off some smart processing
	$HeaderDoc::dumb_as_dirt = 1;
    } else {
	$HeaderDoc::dumb_as_dirt = 0;
    }

    if ($options{l}) {
	# "linkless" mode - don't add link requests
	$HeaderDoc::add_link_requests = 0;
    } else {
	$HeaderDoc::add_link_requests = 1;
    }

    if ($options{m}) {
	# man page output mode - don't add link requests
	$man_output = 1;
	$xml_output = 1;
    } else {
	$man_output = 0;
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

    if ($options{h}) {
	$write_control_file = "1";
    } else {
	$write_control_file = "0";
    }
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
    if ($options{q}) {
	$quietLevel = "1";
    } else {
	$quietLevel = "0";
    }
    if ($options{t}) {
	if (!$quietLevel) {
		print "Forcing strict parameter tagging.\n";
	}
	$HeaderDoc::force_parameter_tagging = 1;
    }
    if ($options{O}) {
	$HeaderDoc::outerNamesOnly = 1;
    } else {
	$HeaderDoc::outerNamesOnly = 0;
    }
    if ($options{d}) {
            print "\tDebugging on...\n\n";
            $debugging = 1;
    }

    if ($options{o}) {
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
			print "\nDocumentation will be written to $specifiedOutputDir\n";
		}
    }
    $lookupTableDir = "$scriptDir$pathSeparator$lookupTableDirName";
    if (($options{x}) || ($testingExport)) {
        if ((-e "$lookupTableDir$pathSeparator$functionFilename") && (-e "$lookupTableDir$pathSeparator$typesFilename")) {
                print "\nWill write database files to an Export directory within each top-level HTML directory.\n\n";
                $export = 1;
        } else {
                print "\nLookup table files not available. Cannot export data.\n";
            $export = 0;
                $testingExport = 0;
        }
    }
    if (($quietLevel eq "0") && !$headerdoc_strip && !$man_output) {
      if ($options{X}) {
	print "XML output mode.\n";
	$xml_output = 1;
      } else {
	print "HTML output mode.\n";
	$xml_output = 0;
      }
    }
# print "output mode is $xml_output\n";

    if (($#ARGV == 0) && (-d $ARGV[0])) {
        my $inputDir = $ARGV[0];
        if ($inputDir =~ /$pathSeparator$/) {
			$inputDir =~ s|(.*)$pathSeparator$|$1|; # get rid of trailing slash, if any
		}		
		if ($^O =~ /MacOS/io) {
			find(\&getHeaders, $inputDir);
		} else {
			&find({wanted => \&getHeaders, follow => 1, follow_skip => 2}, $inputDir);
		}
    } else {
        print "Will process one or more individual files.\n" if ($debugging);
        foreach my $singleFile (@ARGV) {
            if (-f $singleFile) {
                    push(@inputFiles, $singleFile);
            } else {
		    warn "HeaderDoc: file/directory not found: $singleFile\n";
	    }
        }
    }
    unless (@inputFiles) {
        print "No valid input files specified. \n\n";
        if ($isMacOS) {
            die "\tTo use HeaderDoc, drop a header file or folder of header files on this application.\n\n";
            } else {
                    die "\tUsage: headerdoc2html [-dq] [-o <output directory>] <input file(s) or directory>.\n\n";
            }
    }
    
# /*! @function getHeaders
#   */
    sub getHeaders {
        my $filePath = $File::Find::name;
        my $fileName = $_;

        
        if ($fileName =~ /\.(c|h|i|hdoc|php|php\d|class|pas|p|java|jsp|js|jscript|html|shtml|dhtml|htm|shtm|dhtm|pl|bsh|csh|ksh|sh|defs)$/o) {
            push(@inputFiles, $filePath);
        }
    }
}


use strict;
use File::Copy;
use File::Basename;
use lib $uninstalledModulesPath;

# Classes and other modules specific to HeaderDoc
use HeaderDoc::DBLookup;
use HeaderDoc::Utilities qw(findRelativePath safeName getAPINameAndDisc printArray linesFromFile
                            printHash updateHashFromConfigFiles getHashFromConfigFile quote parseTokens
                            stringToFields);
use HeaderDoc::BlockParse qw(blockParse);
use HeaderDoc::Header;
use HeaderDoc::ClassArray;
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
use HeaderDoc::MinorAPIElement;
use HeaderDoc::ParseTree;

$HeaderDoc::modulesPath = $INC{'HeaderDoc/ParseTree.pm'};
$HeaderDoc::modulesPath =~ s/ParseTree.pm$//so;
# print "Module path is ".$HeaderDoc::modulesPath."\n";
# foreach my $key (%INC) {
	# print "KEY: $key\nVALUE: ".$INC{$key}."\n";
# }


################ Setup from Configuration File #######################
my $localConfigFileName = "headerDoc2HTML.config";
my $preferencesConfigFileName = "com.apple.headerDoc2HTML.config";
my $homeDir;
my $usersPreferencesPath;
#added WD-rpw 07/30/01 to support running on MacPerl
#modified WD-rpw 07/01/02 to support the MacPerl 5.8.0
if ($^O =~ /MacOS/io) {
	eval 
	{
		require "FindFolder.pl";
		$homeDir = MacPerl::FindFolder("D");	#D = Desktop. Arbitrary place to put things
		$usersPreferencesPath = MacPerl::FindFolder("P");	#P = Preferences
	};
	if ($@) {
		import Mac::Files;
		$homeDir = Mac::Files::FindFolder(kOnSystemDisk(), kDesktopFolderType());
		$usersPreferencesPath = Mac::Files::FindFolder(kOnSystemDisk(), kPreferencesFolderType());
	}
} else {
	$homeDir = (getpwuid($<))[7];
	$usersPreferencesPath = $homeDir.$pathSeparator."Library".$pathSeparator."Preferences";
}

# The order of files in this array determines the order that the config files will be read
# If there are multiple config files that declare a value for the same key, the last one read wins
my @configFiles = ($usersPreferencesPath.$pathSeparator.$preferencesConfigFileName, $Bin.$pathSeparator.$localConfigFileName);

# default configuration, which will be modified by assignments found in config files.
my %config = (
    copyrightOwner => "",
    defaultFrameName => "index.html",
    compositePageName => "CompositePage.html",
    masterTOCName => "MasterTOC.html",
    apiUIDPrefix => "apple_ref",
    ignorePrefixes => "",
    htmlHeader => "",
    dateFormat => "",
    styleImports => "",
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
    templateStyle => ""
);

%config = &updateHashFromConfigFiles(\%config,\@configFiles);

getAvailabilityMacros($HeaderDoc::modulesPath."Availability.list");

if (defined $config{"ignorePrefixes"}) {
    my $localDebug = 0;
    my @prefixlist = split(/\|/, $config{"ignorePrefixes"});
    foreach my $prefix (@prefixlist) {
	print "ignoring $prefix\n" if ($localDebug);
	# push(@HeaderDoc::ignorePrefixes, $prefix);
	$prefix =~ s/^\s*//so;
	$prefix =~ s/\s*$//so;
	$HeaderDoc::ignorePrefixes{$prefix} = $prefix;
    }
}

if (defined $config{"styleImports"}) {
    $HeaderDoc::styleImports = $config{"styleImports"};
    $HeaderDoc::styleImports =~ s/[\n\r]/ /sgo;
}

if (defined $config{"copyrightOwner"}) {
    HeaderDoc::APIOwner->copyrightOwner($config{"copyrightOwner"});
}
if (defined $config{"defaultFrameName"}) {
    HeaderDoc::APIOwner->defaultFrameName($config{"defaultFrameName"});
}
if (defined $config{"compositePageName"}) {
    HeaderDoc::APIOwner->compositePageName($config{"compositePageName"});
}
if (defined $config{"apiUIDPrefix"}) {
    HeaderDoc::APIOwner->apiUIDPrefix($config{"apiUIDPrefix"});
}
if (defined $config{"htmlHeader"}) {
    HeaderDoc::APIOwner->htmlHeader($config{"htmlHeader"});
}
my $oldRecSep = $/;
undef $/;

if (defined $config{"htmlHeaderFile"}) {
    my $basename = $config{"htmlHeaderFile"};
    my @htmlHeaderFiles = ($Bin.$pathSeparator.$basename, $usersPreferencesPath.$pathSeparator.$basename, $basename);
    foreach my $filename (@htmlHeaderFiles) {
	if (open(HTMLHEADERFILE, "<$filename")) {
	    my $headerString = <HTMLHEADERFILE>;
	    close(HTMLHEADERFILE);
	    # print "HEADER: $headerString";
	    HeaderDoc::APIOwner->htmlHeader($headerString);
	}
    }
}
$/ = $oldRecSep;

if (defined $config{"dateFormat"}) {
    $HeaderDoc::datefmt = $config{"dateFormat"};
}
HeaderDoc::APIOwner->fix_date();

if (defined $config{"textStyle"}) {
	HeaderDoc::APIOwner->setStyle("text", $config{"textStyle"});
}

if (defined $config{"commentStyle"}) {
	HeaderDoc::APIOwner->setStyle("comment", $config{"commentStyle"});
}

if (defined $config{"preprocessorStyle"}) {
	HeaderDoc::APIOwner->setStyle("preprocessor", $config{"preprocessorStyle"});
}

if (defined $config{"funcNameStyle"}) {
	HeaderDoc::APIOwner->setStyle("function", $config{"funcNameStyle"});
}

if (defined $config{"stringStyle"}) {
	HeaderDoc::APIOwner->setStyle("string", $config{"stringStyle"});
}

if (defined $config{"charStyle"}) {
	HeaderDoc::APIOwner->setStyle("char", $config{"charStyle"});
}

if (defined $config{"numberStyle"}) {
	HeaderDoc::APIOwner->setStyle("number", $config{"numberStyle"});
}

if (defined $config{"keywordStyle"}) {
	HeaderDoc::APIOwner->setStyle("keyword", $config{"keywordStyle"});
}

if (defined $config{"typeStyle"}) {
	HeaderDoc::APIOwner->setStyle("type", $config{"typeStyle"});
}

if (defined $config{"paramStyle"}) {
	HeaderDoc::APIOwner->setStyle("param", $config{"paramStyle"});
}

if (defined $config{"varStyle"}) {
	HeaderDoc::APIOwner->setStyle("var", $config{"varStyle"});
}

if (defined $config{"templateStyle"}) {
	HeaderDoc::APIOwner->setStyle("template", $config{"templateStyle"});
}


################ Version Info ##############################
if ($printVersion) {
    &printVersionInfo();
    exit;
} 

################ Exporting ##############################
if ($export || $testingExport) {
	HeaderDoc::DBLookup->loadUsingFolderAndFiles($lookupTableDir, $functionFilename, $typesFilename, $enumsFilename);
}

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
my $headerObject;  # this is the Header object that will own the HeaderElement objects for this file.
my $rootFileName;

if (!$quietLevel) {
    print "======= Parsing Input Files =======\n";
}

my $methods_with_new_parser = 1;

foreach my $inputFile (@inputFiles) {
    my @rawInputLines = &linesFromFile($inputFile);
    # Grab any #include directives.
    processIncludes(\@rawInputLines, $inputFile);
}

foreach my $inputFile (@inputFiles) {
	my $constantObj;
	my $enumObj;
	my $funcObj;
        my $methObj;
	my $pDefineObj;
	my $structObj;
	my $curObj;
	my $varObj;
	my $cppAccessControlState = "protected:"; # the default in C++
	my $objcAccessControlState = "private:"; # the default in Objective C
	
    my @path = split (/$pathSeparator/, $inputFile);
    my $filename = pop (@path);
    my $sublang = "";
    if ($quietLevel eq "0") {
	if ($headerdoc_strip) {
		print "\nStripping $inputFile\n";
	} elsif ($regenerate_headers) {
		print "\nRegenerating $inputFile\n";
	} else {
		print "\nProcessing $inputFile\n";
	}
    }
    %HeaderDoc::perHeaderIgnorePrefixes = ();
    $HeaderDoc::globalGroup = "";
    $reprocess_input = 0;
    
    my $headerDir = join("$pathSeparator", @path);
    ($rootFileName = $filename) =~ s/\.(c|h|i|hdoc|php|php\d|class|pas|p|java|jsp|js|jscript|html|shtml|dhtml|htm|shtm|dhtm|pl|bsh|csh|ksh|sh|defs)$//o;
    if ($filename =~ /\.(php|php\d|class)$/o) {
	$lang = "php";
	$sublang = "php";
    } elsif ($filename =~ /\.(c|C|cpp)$/o) {
	# treat a C program similar to PHP, since it could contain k&r-style declarations
	$lang = "Csource";
	$sublang = "Csource";
    } elsif ($filename =~ /\.(s|d|)htm(l?)$/o) {
	$lang = "java";
	$sublang = "javascript";
    } elsif ($filename =~ /\.j(ava|s|sp|script)$/o) {
	$lang = "java";
	$sublang = "javascript";
    } elsif ($filename =~ /\.p(as|)$/o) {
	$lang = "pascal";
	$sublang = "pascal";
    } elsif ($filename =~ /\.pl$/o) {
	$lang = "perl";
	$sublang = "perl";
    } elsif ($filename =~ /\.(c|b|k|)sh$/o) {
	$lang = "shell";
	$sublang = "shell";
    } else {
	$lang = "C";
	$sublang = "C";
    }

    $HeaderDoc::lang = $lang;
    $HeaderDoc::sublang = $sublang;

    if ($filename =~ /\.defs/o) { 
	$HeaderDoc::sublang = "MIG";
    }

    my $rootOutputDir;
    if (length ($specifiedOutputDir)) {
    	$rootOutputDir ="$specifiedOutputDir$pathSeparator$rootFileName";
    } elsif (@path) {
    	$rootOutputDir ="$headerDir$pathSeparator$rootFileName";
    } else {
    	$rootOutputDir = $rootFileName;
    }
    
	my @rawInputLines = &linesFromFile($inputFile);

    # my @cookedInputLines;
    my $localDebug = 0;

    # IS THIS STILL NEEDED?
    # foreach my $line (@rawInputLines) {
	# foreach my $prefix (keys %HeaderDoc::ignorePrefixes) {
	    # if ($line =~ s/^\s*$prefix\s*//g) {
		# print "ignored $prefix\n" if ($localDebug);
	    # }
	# }
	# push(@cookedInputLines, $line);
    # }
    # @rawInputLines = @cookedInputLines;
	
REDO:
print "REDO" if ($debugging);
    # check for HeaderDoc comments -- if none, move to next file
    my @headerDocCommentLines = grep(/^\s*\/\*\!/, @rawInputLines);
    if ((!@headerDocCommentLines) && ($lang eq "java")) {
	@headerDocCommentLines = grep(/^\s*\/\*\*/, @rawInputLines);
    }
    if ((!@headerDocCommentLines) && ($lang eq "perl" || $lang eq "shell")) {
	@headerDocCommentLines = grep(/^\s*\#\s*\/\*\!/, @rawInputLines);
    }
    if ((!@headerDocCommentLines) && ($lang eq "pascal")) {
	@headerDocCommentLines = grep(/^\s*\{\!/, @rawInputLines);
    }
    if (!@headerDocCommentLines) {
	if ($quietLevel eq "0") {
            print "    Skipping. No HeaderDoc comments found.\n";
	}
        next;
    }
    
    if (!$headerdoc_strip) {
	# Don't do this if we're stripping.  It wastes memory and
	# creates unnecessary empty directories in the output path.

	$headerObject = HeaderDoc::Header->new();
	$headerObject->linenum(0);
	$headerObject->apiOwner($headerObject);
	$HeaderDoc::headerObject = $headerObject;

	# print "output mode is $xml_output\n";

	if ($quietLevel eq "0") {
		if ($xml_output) {
			$headerObject->outputformat("hdxml");
		} else { 
			$headerObject->outputformat("html");
		}
	}
	$headerObject->outputDir($rootOutputDir);
	$headerObject->name($filename);
	$headerObject->filename($filename);
	my $fullpath=cwd()."/$inputFile";
	$headerObject->fullpath($fullpath);
    } else {
	$headerObject = HeaderDoc::Header->new();
	$HeaderDoc::headerObject = $headerObject;
	$headerObject->filename($filename);
	$headerObject->linenum(0);
    }
	
    # scan input lines for class declarations
    # return an array of array refs, the first array being the header-wide lines
    # the others (if any) being the class-specific lines
	my @lineArrays = &getLineArrays(\@rawInputLines);

# print "NLA: " . scalar(@lineArrays) . "\n";
    
    my $localDebug = 0 || $debugging;
    my $linenumdebug = 0;

    if ($headerdoc_strip) {
	# print "input file is $filename, output dir is $rootOutputDir\n";
	my $outdir = "";
	if (length ($specifiedOutputDir)) {
        	$outdir ="$specifiedOutputDir";
	} elsif (@path) {
        	$outdir ="$headerDir";
	} else {
        	$outdir = "strip_output";
	}
	strip($filename, $outdir, $rootOutputDir, $inputFile, \@rawInputLines);
	print "done.\n" if ($quietLevel eq "0");
	next;
    }
    if ($regenerate_headers) {
	HeaderDoc::Regen->regenerate($inputFile, $rootOutputDir);
	print "done.\n" if ($quietLevel eq "0");
	next;
    }

    foreach my $arrayRef (@lineArrays) {
        my $blockOffset = 0;
        my @inputLines = @$arrayRef;


	    # look for /*! comments and collect all comment fields into the appropriate objects
        my $apiOwner = $headerObject;  # switches to a class/protocol/category object, when within a those declarations
	$HeaderDoc::currentClass = $apiOwner;
	    print "inHeader\n" if ($localDebug);
	    my $inputCounter = 0;
	    my $ctdebug = 0;
	    my $classType = "unknown";
	    print "CLASS TYPE CHANGED TO $classType\n" if ($ctdebug);
	    my $nlines = $#inputLines;
	    while ($inputCounter <= $nlines) {
			my $line = "";           
	        
	        	print "Input line number[1]: $inputCounter\n" if ($localDebug);
			print "last line ".$inputLines[$inputCounter-1]."\n" if ($localDebug);
			print "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
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


	        	if (($lang ne "pascal" && (
			     ($inputLines[$inputCounter] =~ /^\s*\/\*\!/o) ||
			     (($lang eq "perl" || $lang eq "shell") && ($inputLines[$inputCounter] =~ /^\s*\#\s*\/\*\!/o)) ||
			     (($lang eq "java") && ($inputLines[$inputCounter] =~ /^\s*\/\*\*/o)))) ||
			    (($lang eq "pascal") && ($inputLines[$inputCounter] =~ s/^\s*\{!/\/\*!/so))) {  # entering headerDoc comment
				my $newlinecount = 0;
				# slurp up comment as line
				if (($lang ne "pascal" && ($inputLines[$inputCounter] =~ /\s*\*\//o)) ||
				    ($lang eq "pascal" && ($inputLines[$inputCounter] =~ s/\s*\}/\*\//so))) { # closing comment marker on same line

					my $linecopy = $inputLines[$inputCounter];
					# print "LINE IS \"$linecopy\".\n" if ($linenumdebug);
					$newlinecount = ($linecopy =~ tr/\n//);
					$blockOffset += $newlinecount - 1;
					print "NEWLINECOUNT: $newlinecount\n" if ($linenumdebug);
					print "BLOCKOFFSET: $blockOffset\n" if ($linenumdebug);

					$line .= $inputLines[$inputCounter++];
					# This is perfectly legal.  Don't warn
					# necessarily.
					if (!emptyHDok($line)) {
						warnHDComment(\@inputLines, $inputCounter, $blockOffset, "HeaderDoc comment", "1");
					}
	        			print "Input line number[2]: $inputCounter\n" if ($localDebug);
					print "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
				} else {                                       # multi-line comment
					my $in_textblock = 0; my $in_pre = 0;
					my $nInputLines = $nlines;
					do {
						my $templine = $inputLines[$inputCounter];
						while ($templine =~ s/\@textblock//io) { $in_textblock++; }  
						while ($templine =~ s/\@\/textblock//io) { $in_textblock--; }
						while ($templine =~ s/<pre>//io) { $in_pre++; print "IN PRE\n" if ($localDebug);}
						while ($templine =~ s/<\/pre>//io) { $in_pre--; print "OUT OF PRE\n" if ($localDebug);}
						if (!$in_textblock && !$in_pre) {
							$inputLines[$inputCounter] =~ s/^[\t ]*[*]?[\t ]+(.*)$/$1/o; # remove leading whitespace, and any leading asterisks
						}
						my $newline = $inputLines[$inputCounter++];
						warnHDComment(\@inputLines, $inputCounter, $blockOffset, "HeaderDoc comment", "2");
						$newline =~ s/^ \*//o;
						if ($lang eq "perl" || $lang eq "shell") {
						    $newline =~ s/^\s*\#\s*//o;
						}
						$line .= $newline;
	        				print "Input line number[3]: $inputCounter\n" if ($localDebug);
						print "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
					} while ((($lang eq "pascal" && ($inputLines[$inputCounter] !~ /\}/o)) ||($lang ne "pascal" && ($inputLines[$inputCounter] !~ s/\*\//\*\//so))) && ($inputCounter <= $nInputLines));
					my $newline = $inputLines[$inputCounter++];
					# This is not inherently wrong.
					if (!emptyHDok($line)) {
				 		warnHDComment(\@inputLines, $inputCounter, $blockOffset, "HeaderDoc comment", "3");
					}
					if ($lang eq "perl" || $lang eq "shell") {
					    $newline =~ s/^\s*\#\s*//o;
					}
					if ($newline !~ /^ \*\//o) {
						$newline =~ s/^ \*//o;
					}
					$line .= $newline;              # get the closing comment marker
	        		print "Input line number[4]: $inputCounter\n" if ($localDebug);
				print "last line ".$inputLines[$inputCounter-1]."\n" if ($localDebug);
				print "next line ".$inputLines[$inputCounter]."\n" if ($localDebug);
			    }
				# print "ic=$inputCounter\n" if ($localDebug);
			    # HeaderDoc-ize JavaDoc/PerlDoc comments
			    if (($lang eq "perl" || $lang eq "shell") && ($line =~ /^\s*\#\s*\/\*\!/o)) {
				$line =~ s/^\s*\#\s*\/\*\!/\/\*\!/o;
			    }
			    if (($lang eq "java") && ($line =~ /^\s*\/\*\*/o)) {
				$line =~ s/^\s*\/\*\*/\/\*\!/o;
			    }
			    $line =~ s/^\s+//o;              # trim leading whitespace
			    $line =~ s/^(.*)\*\/\s*$/$1/so;  # remove closing comment marker

			    # print "line \"$line\"\n" if ($localDebug);
	           
				SWITCH: { # determine which type of comment we're in
					($line =~ /^\/\*!\s+\@header\s*/io) && do {$inHeader = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@framework\s*/io) && do {$inHeader = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@template\s*/io) && do {$inClass = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@interface\s*/io) && do {$inClass = 1; $inInterface = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@class\s*/io) && do {$inClass = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@protocol\s*/io) && do {$inClass = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@category\s*/io) && do {$inClass = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@language\s+.*c\+\+\s*/io) && do {$inCPPHeader = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@language\s+.*objc\s*/io) && do {$inOCCHeader = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@language\s+.*perl\s*/io) && do {$inPerlScript = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@language\s+.*shell\s*/io) && do {$inShellScript = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@language\s+.*php\s*/io) && do {$inPHPScript = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@language\s+.*java\s*/io) && do {$inJavaSource = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@language\s+.*javascript\s*/io) && do {$inJavaSource = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@functiongroup\s*/io) && do {$inFunctionGroup = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@group\s*/io) && do {$inGroup = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@function\s*/io) && do {$inFunction = 1;last SWITCH;};
					($line =~ s/^\/\*!\s+\@availabilitymacro(\s+)/$1/io) && do { $inAvailabilityMacro = 1; last SWITCH;};
					($line =~ /^\/\*!\s+\@methodgroup\s*/io) && do {$inFunctionGroup = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@method\s*/io) && do {
						    if ($classType eq "occ" ||
							$classType eq "intf" ||
							$classType eq "occCat") {
							    $inMethod = 1;last SWITCH;
						    } else {
							    $inFunction = 1;last SWITCH;
						    }
					};
					($line =~ /^\/\*!\s+\@typedef\s*/io) && do {$inTypedef = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@union\s*/io) && do {$inUnion = 1;$inStruct = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@struct\s*/io) && do {$inStruct = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@const(ant)?\s*/io) && do {$inConstant = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@var\s*/io) && do {$inVar = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@define(d)?block\s*/io) && do {$inPDefine = 2;last SWITCH;};
					($line =~ /^\/\*!\s+\@\/define(d)?block\s*/io) && do {$inPDefine = 0;last SWITCH;};
					($line =~ /^\/\*!\s+\@define(d)?\s*/io) && do {$inPDefine = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@lineref\s+(\d+)/io) && do {$blockOffset = $1 - $inputCounter; $inputCounter--; print "BLOCKOFFSET SET TO $blockOffset\n" if ($linenumdebug); last SWITCH;};
					($line =~ /^\/\*!\s+\@enum\s*/io) && do {$inEnum = 1;last SWITCH;};
					($line =~ /^\/\*!\s+\@serial(Data|Field|)\s+/io) && do {$inUnknown = 2;last SWITCH;};
					($line =~ /^\/\*!\s*\w/io) && do {$inUnknown = 1;last SWITCH;};
					my $linenum = $inputCounter - 1 + $blockOffset; # @@@
					warn "$filename:$linenum:HeaderDoc comment is not of known type. Comment text is:\n";
					print "    $line\n";
				}
				# $inputCounter--; # inputCounter is current line.
				my $linenum = $inputCounter - 1;
				my $preAtPart = "";
				$line =~ s/\n\n/\n<br><br>\n/go; # change newline pairs into HTML breaks, for para formatting
				if ($inUnknown == 1) {
					if ($line =~ s/^\s*\/\*!\s*(\w.*?)\@/\/\*! \@/sio) {
						$preAtPart = $1;
					} elsif ($line !~ /^\s*\/\*!\s*.*\@/o) {
						$preAtPart = $line;
						$preAtPart =~ s/^\s*\/\*!\s*//sio;
						$preAtPart =~ s/\s*\*\/\s*$//sio;
						$line = "/*! */";
					}
					print "preAtPart: \"$preAtPart\"\n" if ($localDebug);
					print "line: \"$line\"\n" if ($localDebug);
				}
				my $fieldref = stringToFields($line, $filename, $linenum);
				my @fields = @{$fieldref};

				if ($inCPPHeader) {print "inCPPHeader\n" if ($debugging); $HeaderDoc::sublang="cpp"; &processCPPHeaderComment();};
				if ($inOCCHeader) {print "inCPPHeader\n" if ($debugging); $HeaderDoc::sublang="occ"; &processCPPHeaderComment();};
				if ($inPerlScript) {print "inPerlScript\n" if ($debugging); &processCPPHeaderComment(); $lang="php";};
				if ($inPHPScript) {print "inPHPScript\n" if ($debugging); &processCPPHeaderComment(); $lang="php";};
				if ($inJavaSource) {print "inJavaSource\n" if ($debugging); &processCPPHeaderComment(); $lang="java";};
				if ($inClass) {
					$functionGroup = "";
					$HeaderDoc::globalGroup = "";
					my $classdec = "";
					my $pos=$inputCounter;
					do {
						$classdec .= $inputLines[$pos];
					} while (($pos <= $nlines) && ($inputLines[$pos++] !~ /(\{|\@interface|\@class)/o));
					$classType = &determineClassType($inputCounter, $apiOwner, \@inputLines);
					print "CLASS TYPE CHANGED TO $classType\n" if ($ctdebug);
					if ($classType eq "C") {
					    # $cppAccessControlState = "public:";
					    $cppAccessControlState = "";
					}
					print "inClass 1 - $classType \n" if ($debugging); 
					$apiOwner = &processClassComment($apiOwner, $rootOutputDir, \@fields, $classType, $inputCounter + $blockOffset);
					if ($inInterface) {
						$inInterface = 0;
						$apiOwner->isCOMInterface(1);
						$apiOwner->tocTitlePrefix('COM Interface:');
					}
					my $superclass = &get_super($classType, $classdec);
					if (length($superclass) && (!($apiOwner->checkShortLongAttributes("Superclass")))) {
					    $apiOwner->attribute("Superclass", $superclass, 0);
					}
					print "inClass 2\n" if ($debugging); 
				};
				if ($inHeader) {
					print "inHeader\n" if ($debugging); 
					$functionGroup = "";
					$HeaderDoc::globalGroup = "";
					$apiOwner = &processHeaderComment($apiOwner, $rootOutputDir, \@fields);
					$HeaderDoc::currentClass = $apiOwner;
					if ($reprocess_input == 1) {
					    # my @cookedInputLines;
					    my $localDebug = 0;

					    # foreach my $line (@rawInputLines) {
						# foreach my $prefix (keys %HeaderDoc::perHeaderIgnorePrefixes) {
						    # if ($line =~ s/^\s*$prefix\s*//g) {
							# print "ignored $prefix\n" if ($localDebug);
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
					print "inGroup\n" if ($debugging); 
					my $name = $line;
					$name =~ s/.*\/\*!\s+\@group\s*//io;
					$name =~ s/\s*\*\/.*//o;
					$name =~ s/\n//smgo;
					$name =~ s/^\s+//smgo;
					$name =~ s/\s+$//smgo;
					print "group name is $name\n" if ($debugging);
					$HeaderDoc::globalGroup = $name;
					$inputCounter--;
				};
				if ($inAvailabilityMacro) {
					print "inAvailabilityMacro\n" if ($debugging); 
					my $name = $line;
					$name =~ s/\s*\*\/.*//o;
					$name =~ s/\n//smgo;
					$name =~ s/^\s+//smgo;
					$name =~ s/\s+$//smgo;

					addAvailabilityMacro($name);
					$inputCounter--;
				};
				if ($inFunctionGroup) {
					print "inFunctionGroup\n" if ($debugging); 
					my $name = $line;
					if (!($name =~ s/.*\/\*!\s+\@functiongroup\s*//io)) {
						$name =~ s/.*\/\*!\s+\@methodgroup\s*//io;
						print "inMethodGroup\n" if ($debugging);
					}
					$name =~ s/\s*\*\/.*//o;
					$name =~ s/\n//smgo;
					$name =~ s/^\s+//smgo;
					$name =~ s/\s+$//smgo;
					print "group name is $name\n" if ($debugging);
					$functionGroup = $name;
					$inputCounter--;
				};

				if ($inMethod && !$methods_with_new_parser) {
				    my $methodDebug = 0;
					print "inMethod $line\n" if ($methodDebug);
					$methObj = HeaderDoc::Method->new;
					$methObj->linenum($inputCounter+$blockOffset);
					$methObj->apiOwner($apiOwner);
					if ($xml_output) {
					    $methObj->outputformat("hdxml");
					} else { 
					    $methObj->outputformat("html");
					}
					if (length($functionGroup)) {
						$methObj->group($functionGroup);
					} else {
						$methObj->group($HeaderDoc::globalGroup);
					}
                                        $methObj->filename($filename);
					$methObj->linenum($inputCounter+$blockOffset);
					$methObj->processComment(\@fields);
	 				while (($inputLines[$inputCounter] !~ /\w/o)  && ($inputCounter <= $nlines)){ 
	 					$inputCounter++;
						warnHDComment(\@inputLines, $inputCounter, $blockOffset, "method", "9");
	 					print "Input line number[5]: $inputCounter\n" if ($localDebug);
					}; # move beyond blank lines

					my $declaration = $inputLines[$inputCounter];
					if ($declaration !~ /;[^;]*$/o) { # search for semicolon end, even with trailing comment
						do { 
							warnHDComment(\@inputLines, $inputCounter, $blockOffset, "method", "10");
							$inputCounter++;
							print "Input line number[6]: $inputCounter\n" if ($localDebug);
							$declaration .= $inputLines[$inputCounter];
						} while (($declaration !~ /;[^;]*$/o)  && ($inputCounter <= $nlines))
					}
					$declaration =~ s/^\s+//go;				# trim leading spaces.
					$declaration =~ s/([^;]*;).*$/$1/so;		# trim anything following the final semicolon, 
															# including comments.
					$declaration =~ s/\s+;/;/o;		        # trim spaces before semicolon.
					
					print " --> setting method declaration: $declaration\n" if ($methodDebug);
					$methObj->setMethodDeclaration($declaration, $classType);

					if (length($methObj->name())) {
						if (ref($apiOwner) ne "HeaderDoc::Header") {
						    if ($classType eq "occ" ||
							$classType eq "intf" ||
							$classType eq "occCat") {
							    $methObj->accessControl($objcAccessControlState);
						    } else {
							    $methObj->accessControl($cppAccessControlState);
						    }
						}
						$apiOwner->addToMethods($methObj);
						$methObj->apiOwner($apiOwner); # methods need to know the class/protocol they belong to
						print "added method $declaration\n" if ($localDebug);
					}
				}

				if ($inUnknown || $inTypedef || $inStruct || $inEnum || $inUnion || $inConstant || $inVar || $inFunction || ($inMethod && $methods_with_new_parser) || $inPDefine) {
				    my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
					$soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
					$typedefname, $varname, $constname, $structisbrace, $macronameref)
					= parseTokens($lang, $HeaderDoc::sublang);
				    my $varIsConstant = 0;
				    my $blockmode = 0;
				    my $curtype = "";
				    my $warntype = "";
				    my $blockDebug = 0;
				    my $parmDebug = 0;
				    my $localDebug = 0;

				    if ($inPDefine == 2) { $blockmode = 1; }
				    if ($inFunction || $inMethod) {
					if ($localDebug) {
						if ($inMethod) {
							print "inMethod\n";
						} else {
							print "inFunction\n";
						}
					}
					# @@@ FIXME DAG (OBJC)
					my $method = 0;
					if ($classType eq "occ" ||
						$classType eq "intf" ||
						$classType eq "occCat") {
							$method = 1;
					}
					if ($method) {
						$curObj = HeaderDoc::Method->new;
						$curtype = "method";
					} else {
						$curObj = HeaderDoc::Function->new;
						$curtype = "function";
					}
					$curObj->apiOwner($apiOwner);
					if ($xml_output) {
					    $curObj->outputformat("hdxml");
					} else { 
					    $curObj->outputformat("html");
					}
					if (length($functionGroup)) {
						$curObj->group($functionGroup);
					} else {
						$curObj->group($HeaderDoc::globalGroup);
					}
                                        $curObj->filename($filename);
					$curObj->linenum($inputCounter+$blockOffset);
					if ($method) {
						$curObj->processComment(\@fields);
					} else {
						$curObj->processComment(\@fields);
					}
				    } elsif ($inPDefine) {
					print "inPDefine\n" if ($localDebug);
					$curtype = "#define";
					if ($blockmode) { $warntype = "defineblock"; }
					$curObj = HeaderDoc::PDefine->new;
					$curObj->group($HeaderDoc::globalGroup);
					$curObj->apiOwner($apiOwner);
					if ($xml_output) {
					    $curObj->outputformat("hdxml");
					} else { 
					    $curObj->outputformat("html");
					}
                                        $curObj->filename($filename);
					$curObj->linenum($inputCounter+$blockOffset);
					$curObj->processComment(\@fields);
				    } elsif ($inVar) {
# print "inVar!!\n";
					print "inVar\n" if ($localDebug);
					$curtype = "constant";
					$varIsConstant = 0;
					$curObj = HeaderDoc::Var->new;
					$curObj->group($HeaderDoc::globalGroup);
					$curObj->apiOwner($apiOwner);
					if ($xml_output) {
					    $curObj->outputformat("hdxml");
					} else { 
					    $curObj->outputformat("html");
					}
                                        $curObj->filename($filename);
					$curObj->linenum($inputCounter+$blockOffset);
					$curObj->processComment(\@fields);
				    } elsif ($inConstant) {
					print "inConstant\n" if ($localDebug);
					$curtype = "constant";
					$varIsConstant = 1;
					$curObj = HeaderDoc::Constant->new;
					$curObj->group($HeaderDoc::globalGroup);
					$curObj->apiOwner($apiOwner);
					if ($xml_output) {
					    $curObj->outputformat("hdxml");
					} else { 
					    $curObj->outputformat("html");
					}
                                        $curObj->filename($filename);
					$curObj->linenum($inputCounter+$blockOffset);
					$curObj->processComment(\@fields);
				    } elsif ($inUnknown) {
					print "inUnknown\n" if ($localDebug);
					$curtype = "UNKNOWN";
					$curObj = HeaderDoc::HeaderElement->new;
					$curObj->group($HeaderDoc::globalGroup);
					if ($xml_output) {
					    $curObj->outputformat("hdxml");
					} else { 
					    $curObj->outputformat("html");
					}
					warnHDComment(\@inputLines, $inputCounter, $blockOffset, "unknown", "11");
				    } elsif ($inTypedef) {
# print "inTypedef\n"; $localDebug = 1;
					print "inTypedef\n" if ($localDebug);
					$curtype = $typedefname;
					# if ($lang eq "pascal") {
						# $curtype = "type";
					# } else {
						# $curtype = "typedef";
					# }
					$curObj = HeaderDoc::Typedef->new;
					$curObj->group($HeaderDoc::globalGroup);
					$curObj->apiOwner($apiOwner);
					if ($xml_output) {
					    $curObj->outputformat("hdxml");
					} else { 
					    $curObj->outputformat("html");
					}
                                        $curObj->filename($filename);
					$curObj->linenum($inputCounter+$blockOffset);
					$curObj->processComment(\@fields);
					$curObj->masterEnum(0);
					
					warnHDComment(\@inputLines, $inputCounter, $blockOffset, "enum", "11a");
					# if a struct declaration precedes the typedef, suck it up
				} elsif ($inStruct || $inUnion) {
					if ($localDebug) {
						if ($inUnion) {
							print "inUnion\n";
						} else {
							print "inStruct\n";
						}
					}
					if ($inUnion) {
						$curtype = "union";
					} else {
						$curtype = "struct";
					}
                                        $curObj = HeaderDoc::Struct->new;
					$curObj->group($HeaderDoc::globalGroup);
                                        $curObj->apiOwner($apiOwner);
                                        if ($inUnion) {     
                                            $curObj->isUnion(1);
                                        } else {
                                            $curObj->isUnion(0);
                                        }
                                        if ($xml_output) {
                                            $curObj->outputformat("hdxml");
                                        } else {
                                            $curObj->outputformat("html");
                                        }
                                        $curObj->filename($filename);
					$curObj->linenum($inputCounter+$blockOffset);
                                        $curObj->processComment(\@fields);
					warnHDComment(\@inputLines, $inputCounter, $blockOffset, "$curtype", "11b");
				} elsif ($inEnum) {
					print "inEnum\n" if ($localDebug);
					$curtype = "enum";
                                        $curObj = HeaderDoc::Enum->new;
					$curObj->masterEnum(1);
					$curObj->group($HeaderDoc::globalGroup);
                                        $curObj->apiOwner($apiOwner);
                                        if ($xml_output) {
                                            $curObj->outputformat("hdxml");
                                        } else {
                                            $curObj->outputformat("html");
                                        }
                                        $curObj->filename($filename);
					$curObj->linenum($inputCounter+$blockOffset);
                                        $curObj->processComment(\@fields);
					warnHDComment(\@inputLines, $inputCounter, $blockOffset, "$curtype", "11c");
				}
				if (!length($warntype)) { $warntype = $curtype; }
                                while (($inputLines[$inputCounter] !~ /\w/o)  && ($inputCounter <= $nlines)){
                                	# print "BLANKLINE IS $inputLines[$inputCounter]\n";
                                	$inputCounter++;
# print "warntype is $warntype\n";
                                	warnHDComment(\@inputLines, $inputCounter, $blockOffset, "$warntype", "12");
                                	print "Input line number[7]: $inputCounter\n" if ($localDebug);
                                };
                                # my  $declaration = $inputLines[$inputCounter];

print "NEXT LINE is ".$inputLines[$inputCounter].".\n" if ($localDebug);

	my $outertype = ""; my $newcount = 0; my $declaration = ""; my $namelist = "";

	my ($case_sensitive, $keywordhashref) = $curObj->keywords();
	my $typelist = ""; my $innertype = ""; my $posstypes = "";
	print "PTCT: $posstypes =? $curtype\n" if ($localDebug || $blockDebug);
	my $blockDec = "";
	my $hangDebug = 0;
	while (($blockmode || ($outertype ne $curtype && $innertype ne $curtype && $posstypes !~ /$curtype/)) && ($inputCounter <= $nlines)) { # ($typestring !~ /$typedefname/)

		if ($hangDebug) { print "In Block Loop\n"; }

		# while ($inputLines[$inputCounter] !~ /\S/o && ($inputCounter <= $nlines)) { $inputCounter++; }
		# if (warnHDComment(\@inputLines, $inputCounter, 0, "blockParse:$outertype", "18b")) {
			# last;
		# } else { print "OK\n"; }
		print "DOING SOMETHING\n" if ($localDebug);
		$HeaderDoc::ignore_apiuid_errors = 1;
		my $junk = $curObj->apirefSetup();
		$HeaderDoc::ignore_apiuid_errors = 0;
		# the value of a constant
		my $value = "";
		my $pplref = undef;
		my $returntype = undef;
		my $pridec = "";
		my $parseTree = undef;
		my $simpleTDcontents = "";
		my $bpavail = "";
		print "Entering blockParse\n" if ($hangDebug);
		($newcount, $declaration, $typelist, $namelist, $posstypes, $value, $pplref, $returntype, $pridec, $parseTree, $simpleTDcontents, $bpavail) = &blockParse($filename, $blockOffset, \@inputLines, $inputCounter, 0, \%HeaderDoc::ignorePrefixes, \%HeaderDoc::perHeaderIgnorePrefixes, $keywordhashref, $case_sensitive);

		if ($bpavail && length($bpavail)) { $curObj->availability($bpavail); }
		# print "BPAVAIL ($namelist): $bpavail\n";

		print "Left blockParse\n" if ($hangDebug);

		if ($outertype eq $curtype || $innertype eq $curtype || $posstypes =~ /$curtype/) {
			# Make sure we have the right UID for methods
			$curObj->declaration($declaration);
			$HeaderDoc::ignore_apiuid_errors = 1;
			my $junk = $curObj->apirefSetup(1);
			$HeaderDoc::ignore_apiuid_errors = 0;
		}
		$curObj->privateDeclaration($pridec);
		$parseTree->addAPIOwner($curObj);
		$curObj->parseTree(\$parseTree);
		# print "PT IS A $parseTree\n";
		# $parseTree->htmlTree();
		# $parseTree->processEmbeddedTags();

		my @parsedParamList = @{$pplref};
		print "VALUE IS $value\n" if ($localDebug);
		# warn("nc: $newcount.  ts: $typestring.  nl: $namelist\nBEGIN:\n$declaration\nEND.\n");

		my $method = 0;
		if ($classType eq "occ" ||
			$classType eq "intf" ||
			$classType eq "occCat") {
				$method = 1;
		}

		$declaration =~ s/^\s*//so;
		# if (!length($declaration)) { next; }

	print "obtained declaration\n" if ($localDebug);

		$inputCounter = $newcount;

		my @oldnames = split(/[,;]/, $namelist);
		my @oldtypes = split(/ /, $typelist);

		$outertype = $oldtypes[0];
		if ($outertype eq "") {
			$outertype = $curtype;
			my $linenum = $inputCounter + $blockOffset;
			warn("$filename:$linenum:Parser bug: empty outer type\n");
			warn("IC: $inputCounter\n");
			warn("DC: \"$declaration\"\n");
			warn("TL: \"$typelist\"\n");
			warn("DC: \"$namelist\"\n");
			warn("DC: \"$posstypes\"\n");
		}
		$innertype = $oldtypes[scalar(@oldtypes)-1];

		if ($localDebug) {
			foreach my $ot (@oldtypes) {
				print "TYPE: \"$ot\"\n";
			}
		}

		my $explicit_name = 1;
		my $curname = $curObj->name();
		$curname =~ s/^\s*//o;
		$curname =~ s/\s*$//o;
		my @names = ( ); #$curname
		my @types = ( ); #$outertype

		my $nameDebug = 0;
		print "names:\n" if ($nameDebug);
		if ($curname !~ /:$/o) {
		    foreach my $name (@oldnames) {
			my $NCname = $name;
			my $NCcurname = $curname;
			$NCname =~ s/:$//so;
			$NCcurname =~ s/:$//so;
			print "NM \"$name\" CN: \"$curname\"\n" if ($nameDebug);
			if ($NCname eq $NCcurname && $name ne $curname) {
			    $curname .= ":";
			    $curObj->name($curname);
			    $curObj->rawname($curname);
			}
		    }
		}
		print "endnames\n" if ($nameDebug);

		if (length($curname) && length($curtype)) {
			push(@names, $curname);
			push(@types, $outertype);
		}
		my $count = 0;
		my $operator = 0;
		if ($typelist eq "operator") {
			$operator = 1;
		}
		foreach my $name (@oldnames) {
			if ($operator) {
				$name =~ s/^\s*operator\s*//so;
				$name = "operator $name";
				$curname =~ s/^operator(\s*)(\S+)/operator $2/so;
			}
# print "NAME \"$name\"\nCURNAME \"$curname\"\n";
			if (($name eq $curname) && ($oldtypes[$count] eq $outertype)) {
				$explicit_name = 0;
				$count++;
			} else {
				push(@names, $name);
				push(@types, $oldtypes[$count++]);
			}
		}
		# foreach my $xname (@names) { print "XNAME: $xname\n"; }
		if ($hangDebug) { print "Point A\n"; }
		# $explicit_name = 0;
		my $count = 0;
		foreach my $name (@names) {
		    my $localDebug = 0;
		    my $typestring = $types[$count++];

		    print "NAME IS $name\n" if ($localDebug);
		    print "CURNAME IS $curname\n" if ($localDebug);
		    print "TYPESTRING IS $typestring\n" if ($localDebug);
		    print "CURTYPE IS $curtype\n" if ($localDebug);
			print "MATCH: $name IS A $typestring.\n" if ($localDebug);

print "DEC ($name / $typestring): $declaration\n" if ($localDebug);

		    $name =~ s/\s*$//go;
		    $name =~ s/^\s*//go;
		    my $cmpname = $name;
		    my $cmpcurname = $curname;
		    $cmpname =~ s/:$//so;
		    $cmpcurname =~ s/:$//so;
		    if (!length($name)) { next; }
			print "Got $name ($curname)\n" if ($localDebug);

			my $extra = undef;

			if ($typestring eq $curtype && ($cmpname eq $cmpcurname || !length($curname))) {
				print "$curtype = $typestring\n" if ($localDebug);
				$extra = $curObj;
# print "E=C\n$extra\n$curObj\n";
				if ($blockmode) {
					$blockDec .= $declaration;
					print "SPDF[1]\n" if ($hangDebug);
					$curObj->isBlock(1);
					# $curObj->setPDefineDeclaration($blockDec);
					print "END SPDF[1]\n" if ($hangDebug);
					# $declaration = $curObj->declaration() . $declaration;
				}
			} else {
				print "NAME IS $name\n" if ($localDebug);
			    if ($curtype eq "function" && $posstypes =~ /function/o) {
				$curtype = "UNKNOWN";
print "setting curtype to UNKNOWN\n" if ($localDebug);
			    }
			    if ($typestring eq $outertype || !$HeaderDoc::outerNamesOnly) {
				if ($typestring =~ /^$typedefname/ && length($typedefname)) {
					print "blockParse returned $typedefname\n" if ($localDebug);
					$extra = HeaderDoc::Typedef->new;
					$extra->group($HeaderDoc::globalGroup);
                                        $extra->filename($filename);
					$extra->linenum($inputCounter+$blockOffset);
					$curObj->masterEnum(1);
					if ($curtype eq "UNKNOWN") {
						$extra->processComment(\@fields);
					}
				} elsif ($typestring =~ /^struct/o || $typestring =~ /^union/o || ($lang eq "pascal" && $typestring =~ /^record/o)) {
					print "blockParse returned struct or union ($typestring)\n" if ($localDebug);
					$extra = HeaderDoc::Struct->new;
					$extra->group($HeaderDoc::globalGroup);
                                        $extra->filename($filename);
					$extra->linenum($inputCounter+$blockOffset);
					if ($typestring =~ /union/o) {
						$extra->isUnion(1);
					}
					if ($curtype eq "UNKNOWN") {
						$extra->processComment(\@fields);
					}
				} elsif ($typestring =~ /^enum/o) {
					print "blockParse returned enum\n" if ($localDebug);
					$extra = HeaderDoc::Enum->new;
					$extra->group($HeaderDoc::globalGroup);
                                        $extra->filename($filename);
					$extra->linenum($inputCounter+$blockOffset);
					if ($curtype eq "UNKNOWN") {
						$extra->processComment(\@fields);
					}
					if ($curtype eq "enum" || $curtype eq "typedef") {
						$extra->masterEnum(0);
					} else {
						$extra->masterEnum(1);
					}
				} elsif ($typestring =~ /^MACRO/o) {
					print "blockParse returned MACRO\n" if ($localDebug);
					# silently ignore this noise.
				} elsif ($typestring =~ /^\#define/o) {
					print "blockParse returned #define\n" if ($localDebug);
					$extra = HeaderDoc::PDefine->new;
					$extra->group($HeaderDoc::globalGroup);
                                        $extra->filename($filename);
					$extra->linenum($inputCounter+$blockOffset);
					if ($curtype eq "UNKNOWN") {
						$extra->processComment(\@fields);
					}
				} elsif ($typestring =~ /^constant/o) {
					if ($declaration =~ /\s+const\s+/o) {
						$varIsConstant = 1;
						print "blockParse returned constant\n" if ($localDebug);
						$extra = HeaderDoc::Constant->new;
						$extra->group($HeaderDoc::globalGroup);
                                        	$extra->filename($filename);
						$extra->linenum($inputCounter+$blockOffset);
						if ($curtype eq "UNKNOWN") {
							$extra->processComment(\@fields);
						}
					} else {
						$varIsConstant = 0;
						print "blockParse returned variable\n" if ($localDebug);
						$extra = HeaderDoc::Var->new;
						$extra->group($HeaderDoc::globalGroup);
                                        	$extra->filename($filename);
						$extra->linenum($inputCounter+$blockOffset);
						if ($curtype eq "UNKNOWN") {
							$extra->processComment(\@fields);
						}
					}
				} elsif ($typestring =~ /^(function|method|operator|ftmplt)/o) {
					print "blockParse returned function or method\n" if ($localDebug);
					if ($method) {
						$extra = HeaderDoc::Method->new;
						if (length($functionGroup)) {
							$extra->group($functionGroup);
						} else {
							$extra->group($HeaderDoc::globalGroup);
						}
                                        	$extra->filename($filename);
						$extra->linenum($inputCounter+$blockOffset);
						if ($curtype eq "UNKNOWN") {
							$extra->processComment(\@fields);
						}
					} else {
						$extra = HeaderDoc::Function->new;
						if (length($functionGroup)) {
							$extra->group($functionGroup);
						} else {
							$extra->group($HeaderDoc::globalGroup);
						}
                                        	$extra->filename($filename);
						$extra->linenum($inputCounter+$blockOffset);
						if ($curtype eq "UNKNOWN") {
							$extra->processComment(\@fields);
						}
					}
					if ($typestring eq "ftmplt") {
						$extra->isTemplate(1);
					}
				} else {
					my $linenum = $inputCounter + $blockOffset;
					warn("$filename:$linenum:Unknown keyword $typestring in block-parsed declaration\n");
				}
			    } else {
				print "Dropping alternate name\n" if ($localDebug);
			    }
			}
			if ($hangDebug) { print "Point B\n"; }
			if ($curtype eq "UNKNOWN" && $extra) {
				$curObj = $extra;
				$curObj->parseTree(\$parseTree);
			}
			if ($extra) {
				print "Processing \"extra\".\n" if ($localDebug);
				if ($bpavail && length($bpavail)) {
					$extra->availability($bpavail);
				}
				my $cleantypename = "$typestring $name";
				$cleantypename =~ s/\s+/ /sgo;
				$cleantypename =~ s/^\s*//so;
				$cleantypename =~ s/\s*$//so;
				if (length($cleantypename)) {
					$HeaderDoc::namerefs{$cleantypename} = $extra;
				}
				my $extraclass = ref($extra) || $extra;
				my $abstract = $curObj->abstract();
				my $discussion = $curObj->discussion();
				my $pridec = $curObj->privateDeclaration();
				$extra->privateDeclaration($pridec);

				if ($curObj != $extra) {
					my $orig_parsetree_ref = $curObj->parseTree();
					my $orig_parsetree = ${$orig_parsetree_ref};
					bless($orig_parsetree, "HeaderDoc::ParseTree");
					$extra->parseTree($orig_parsetree_ref); # ->clone());
					# my $new_parsetree = $extra->parseTree();
					# bless($new_parsetree, "HeaderDoc::ParseTree");
					# $new_parsetree->addAPIOwner($extra);
					$orig_parsetree->addAPIOwner($extra);
					# $new_parsetree->processEmbeddedTags();
				}
				# print "PROCESSING CO $curObj EX $extra\n";
				# print "PT: ".$curObj->parseTree()."\n";

				if ($blockmode) {
					my $altDiscussionRef = $curObj->checkAttributeLists("Included Defines");
					my $discussionParam = $curObj->taggedParamMatching($name);
					# print "got $discussionParam\n";
	# print "DP: $discussionParam ADP: $altDiscussionRef\n";
					if ($discussionParam) {
						$discussion = $discussionParam->discussion;
					} elsif ($altDiscussionRef) {
						my @altDiscEntries = @{$altDiscussionRef};
						foreach my $field (@altDiscEntries) {
						    my ($dname, $ddisc) = &getAPINameAndDisc($field);
						    if ($name eq $dname) {
						    	$discussion = $ddisc;
						    }
						}
					}
					if ($curObj != $extra) {
						# we use the parsed parms to
						# hold subdefines.
						$curObj->addParsedParameter($extra);
					}
				}

				print "Point B1\n" if ($hangDebug);
				if ($extraclass ne "HeaderDoc::Method") {
					print "Point B2\n" if ($hangDebug);
					my $paramName = "";
					my $position = 0;
					my $type = "";
					if ($extraclass eq "HeaderDoc::Function") {
						$extra->returntype($returntype);
					}
					my @tempPPL = @parsedParamList;
					foreach my $parsedParam (@tempPPL) {
					    if (0) {
						# temp code
						print "PARSED PARAM: \"$parsedParam\"\n" if ($parmDebug);
						if ($parsedParam =~ s/(\w+\)*)$//so) {
							$paramName = $1;
						} else {
							$paramName = "";
						}

						$parsedParam =~ s/\s*$//so;
						if (!length($parsedParam)) {
							$type = $paramName;
							$paramName = "";
						} else {
							$type = $parsedParam;
						}
						print "NAME: $paramName\nType: $type\n" if ($parmDebug);

						my $param = HeaderDoc::MinorAPIElement->new();
						$param->linenum($inputCounter+$blockOffset);
						$param->outputformat($extra->outputformat);
						$param->name($paramName);
						$param->position($position++);
						$param->type($type);
						$extra->addParsedParameter($param);
					    } else {
						# the real code
						my $ppDebug = 0 || $parmDebug;

						print "PARSED PARAM: \"$parsedParam\"\n" if ($ppDebug);

						my $ppstring = $parsedParam;
						$ppstring =~ s/^\s*//sgo;
						$ppstring =~ s/\s*$//sgo;

						my $foo;
						my $dec;
						my $pridec;
						my $type;
						my $name;
						my $pt;
						my $value;
						my $pplref;
						my $returntype;
						if ($ppstring eq "...") {
							$name = $ppstring;
							$type = "";
							$pt = "";
						} else {
							$ppstring .= ";";
							my @array = ( $ppstring );

							my $parseTree = undef;
							my $simpleTDcontents = "";
							my $bpavail = "";
							($foo, $dec, $type, $name, $pt, $value, $pplref, $returntype, $pridec, $parseTree, $simpleTDcontents, $bpavail) = &blockParse($filename, $extra->linenum(), \@array, 0, 1, \%HeaderDoc::ignorePrefixes, \%HeaderDoc::perHeaderIgnorePrefixes, $keywordhashref, $case_sensitive);
						}
						if ($ppDebug) {
							print "NAME: $name\n";
							print "TYPE: $type\n";
							print "PT:   $pt\n";
							print "RT:   $returntype\n";
						}
						
						my $param = HeaderDoc::MinorAPIElement->new();
						$param->linenum($inputCounter+$blockOffset);
						$param->outputformat($extra->outputformat);
						$returntype =~ s/^\s*//s;
						$returntype =~ s/\s*$//s;
						if ($returntype =~ /(struct|union|enum|record|typedef)$/) {
							$returntype .= " $name";
							$name = "";
						} elsif (!length($returntype)) {
							$returntype .= " $name";
							if ($name !~ /\.\.\./) {
								$name = "anonymous$name";
							}
						}
						print "NM: $name RT $returntype\n" if ($ppDebug);
						$param->name($name);
						$param->position($position++);
						$param->type($returntype);
						$extra->addParsedParameter($param);
					    }
					}
				} else {
					# we're a method
					$extra->returntype($returntype);
					my @newpps = $parseTree->objCparsedParams();
					foreach my $newpp (@newpps) {
						$extra->addParsedParameter($newpp);
					}
				}
				my $extradirty = 0;
				if (length($simpleTDcontents)) {
					$extra->typedefContents($simpleTDcontents);
				}
				print "Point B3\n" if ($hangDebug);
				if (length($preAtPart)) {
					print "preAtPart: $preAtPart\n" if ($localDebug);
					$extra->discussion($preAtPart);
				} elsif ($extra != $curObj) {
					# Otherwise this would be bad....
					$extra->discussion($discussion);

				}
				print "Point B4\n" if ($hangDebug);
				$extra->abstract($abstract);
				if (length($value)) { $extra->value($value); }
				if ($extra != $curObj || !length($curObj->name())) {
					$name =~ s/^(\s|\*)*//sgo;
				}
				print "NAME IS $name\n" if ($localDebug);
				$extra->rawname($name);
				# my $namestring = $curObj->name();
				# if ($explicit_name && 0) {
					# $extra->name("$name ($namestring)");
				# } else {
					# $extra->name($name);
				# }
				print "Point B5\n" if ($hangDebug);
				$HeaderDoc::ignore_apiuid_errors = 1;
				$extra->name($name);
				my $junk = $extra->apirefSetup();
				$HeaderDoc::ignore_apiuid_errors = 0;


				# print "NAMES: \"".$curObj->name()."\" & \"".$extra->name()."\"\n";
				# print "ADDYS: ".$curObj." & ".$extra."\n";

				if ($extra != $curObj) {
				    my @params = $curObj->taggedParameters();
				    foreach my $param (@params) {
					$extradirty = 1;
					# print "CONSTANT $param\n";
					$extra->addTaggedParameter($param->clone());
				    }
				    my @constants = $curObj->constants();
				    foreach my $constant (@constants) {
					$extradirty = 1;
					# print "CONSTANT $constant\n";
					if ($extra->can("addToConstants")) {
					    $extra->addToConstants($constant->clone());
					    # print "ATC\n";
					} elsif ($extra->can("addConstant")) {
					    $extra->addConstant($constant->clone());
					    # print "AC\n";
					}
				    }

				    print "Point B6\n" if ($hangDebug);
				    if (length($curObj->name())) {
	# my $a = $extra->rawname(); my $b = $curObj->rawname(); my $c = $curObj->name();
	# print "EXTRA RAWNAME: $a\nCUROBJ RAWNAME: $b\nCUROBJ NAME: $c\n";
					# change whitespace to ctrl-d to
					# allow multi-word names.
					my $ern = $extra->rawname();
					if ($ern =~ /\s/o && $localDebug) {
						print "changed space to ctrl-d\n";
						print "ref is ".$extra->apiuid()."\n";
					}
					$ern =~ s/\s/\cD/sgo;
					my $crn = $curObj->rawname();
					if ($crn =~ /\s/o && $localDebug) {
						print "changed space to ctrl-d\n";
						print "ref is ".$curObj->apiuid()."\n";
					}
					$crn =~ s/\s/\cD/sgo;
					$curObj->attributelist("See Also", $ern." ".$extra->apiuid());
					$extra->attributelist("See Also", $crn." ".$curObj->apiuid());
				    }
				}
				print "Point B7 TS = $typestring\n" if ($hangDebug);
				if (ref($apiOwner) ne "HeaderDoc::Header") {
					$extra->accessControl($cppAccessControlState); # @@@ FIXME DAG CHECK FOR OBJC
				}
				if ($extra != $curObj && $curtype ne "UNKNOWN" && $curObj->can("fields") && $extra->can("fields")) {
					my @fields = $curObj->fields();
					print "B7COPY\n" if ($localDebug);

					foreach my $field (@fields) {
						bless($field, "HeaderDoc::MinorAPIElement");
						my $newfield = $field->clone();
						$extradirty = 1;
						$extra->addField($newfield);
						# print "Added field ".$newfield->name()." to $extra ".$extra->name()."\n";
					}
				}
				$extra->apiOwner($apiOwner);
				if ($xml_output) {
				    $extra->outputformat("hdxml");
				} else { 
				    $extra->outputformat("html");
				}
				$extra->filename($filename);

		# warn("Added ".$extra->name()." ".$extra->apiuid().".\n");

				print "B8 blockmode=$blockmode ts=$typestring\n" if ($localDebug || $hangDebug);
				if ($typestring =~ /$typedefname/ && length($typedefname)) {
	                		if (length($declaration)) {
                        			$extra->setTypedefDeclaration($declaration);
					}
					if (length($extra->name())) {
						if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToTypedefs($extra); }
				    	}
				} elsif ($typestring =~ /MACRO/o) {
					# throw these away.
					# $extra->setPDefineDeclaration($declaration);
					# $apiOwner->addToPDefines($extra);
				} elsif ($typestring =~ /#define/o) {
					print "SPDF[2]\n" if ($hangDebug);
					$extra->setPDefineDeclaration($declaration);
# print "DEC:$declaration\n" if ($hangDebug);
					print "END SPDF[2]\n" if ($hangDebug);
					if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToPDefines($extra); }
				} elsif ($typestring =~ /struct/o || $typestring =~ /union/o || ($lang eq "pascal" && $typestring =~ /record/o)) {
					if ($typestring =~ /union/o) {
						$extra->isUnion(1);
					} else {
						$extra->isUnion(0);
					}
					# $extra->declaration($declaration);
# print "PRE (DEC IS $declaration)\n";
					$extra->setStructDeclaration($declaration);
# print "POST\n";
					if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToStructs($extra); }
				} elsif ($typestring =~ /enum/o) {
					$extra->declaration($declaration);
					$extra->declarationInHTML($extra->getEnumDeclaration($declaration));
print "B8ENUM\n" if ($localDebug || $hangDebug);
					if (($blockmode != 2) || ($extra != $curObj)) {
print "B8ENUMINSERT apio=$apiOwner\n" if ($localDebug || $hangDebug);
 $apiOwner->addToEnums($extra); }
				} elsif ($typestring =~ /\#define/o) {
					print "SPDF[3]\n" if ($hangDebug);
					$extra->setPDefineDeclaration($declaration);
					print "END SPDF[3]\n" if ($hangDebug);
					if (($blockmode != 2) || ($extra != $curObj)) { $headerObject->addToPDefines($extra); }
				} elsif ($typestring =~ /(function|method|operator|ftmplt)/o) {
					if ($method) {
						$extra->setMethodDeclaration($declaration);
						$HeaderDoc::ignore_apiuid_errors = 1;
						my $junk = $extra->apirefSetup(1);
						$extradirty = 0;
						$HeaderDoc::ignore_apiuid_errors = 0;
						if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToMethods($extra); }
					} else {
						print "SFD\n" if ($hangDebug);
						$extra->setFunctionDeclaration($declaration);
						print "END SFD\n" if ($hangDebug);
						$HeaderDoc::ignore_apiuid_errors = 1;
						my $junk = $extra->apirefSetup(1);
						$extradirty = 0;
						$HeaderDoc::ignore_apiuid_errors = 0;
						if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToFunctions($extra); }
					}
					if ($typestring eq "ftmplt") {
						$extra->isTemplate(1);
					}
				} elsif ($typestring =~ /constant/o) {
					$extra->declaration($declaration);
					if ($varIsConstant) {
					    $extra->setConstantDeclaration($declaration);
                                            if (length($extra->name())) {
                                                    if (ref($apiOwner) ne "HeaderDoc::Header") {
                                                        $extra->accessControl($cppAccessControlState);
                                                        if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToVars($extra); }
                                                    } else { # headers group by type
                                                            if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToConstants($extra); }
                                                }
                                            }
					} else {
						$extra->setVarDeclaration($declaration);
                                                if (ref($apiOwner) ne "HeaderDoc::Header") {
                                                    $extra->accessControl($cppAccessControlState);
						}
						if (($blockmode != 2) || ($extra != $curObj)) { $apiOwner->addToVars($extra); }
					}
				} else {
					my $linenum = $inputCounter + $blockOffset;
					warn("$filename:$linenum:Unknown typestring $typestring returned by blockParse\n");
				}
				print "B9 blockmode=$blockmode ts=$typestring\n" if ($localDebug || $hangDebug);
				$extra->checkDeclaration();
				$HeaderDoc::ignore_apiuid_errors = 1;
				my $junk = $extra->apirefSetup($extradirty);
				$HeaderDoc::ignore_apiuid_errors = 0;
			}
		}
		if ($hangDebug) {
			print "Point C\n";
			print "inputCounter is $inputCounter, #inputLines is $nlines\n";
		}

		while ($inputLines[$inputCounter] !~ /\S/o && ($inputCounter <= $nlines)) { $inputCounter++; }
		if ($hangDebug) { print "Point D\n"; }
		if ($curtype eq "UNKNOWN") { $curtype = $outertype; }
		if ((($outertype ne $curtype && $innertype ne $curtype && $posstypes !~ /$curtype/)) && (($inputCounter > $nlines) || warnHDComment(\@inputLines, $inputCounter, $blockOffset, "blockParse:$outertype", "18a"))) {
			warn "No matching declaration found.  Last name was $curname\n";
			warn "$outertype ne $curtype && $innertype ne $curtype && $posstypes !~ $curtype\n";
			last;
		}
		if ($hangDebug) { print "Point E\n"; }
		if ($blockmode) {
			warn "next line: ".$inputLines[$inputCounter]."\n" if ($hangDebug);
			$blockmode = 2;
			$HeaderDoc::ignore_apiuid_errors = 1;
			if (warnHDComment(\@inputLines, $inputCounter, $blockOffset, "blockParse:$outertype", "18a")) {
				$blockmode = 0;
				warn "Block Mode Ending\n" if ($hangDebug);
			}
			$HeaderDoc::ignore_apiuid_errors = 0;
		}
		print "PTCT: $posstypes =? $curtype\n" if ($localDebug || $blockDebug);
	}
	if (length($blockDec)) {
		$curObj->declaration($blockDec);
		$curObj->declarationInHTML($blockDec);
	}
	if ($hangDebug) { print "Point F\n"; }
	print "Out of Block\n" if ($localDebug || $blockDebug);
	# the end of this block assumes that inputCounter points
	# to the last line grabbed, but right now it points to the
	# next line available.  Back it up by one.
	$inputCounter--;
	# warn("NEWDEC:\n$declaration\nEND NEWDEC\n");

				}  ## end blockParse handler
				
	        }
			$inCPPHeader = $inOCCHeader = $inPerlScript = $inShellScript = $inPHPScript = $inJavaSource = $inHeader = $inUnknown = $inFunction = $inAvailabilityMacro = $inFunctionGroup = $inGroup = $inTypedef = $inUnion = $inStruct = $inConstant = $inVar = $inPDefine = $inEnum = $inMethod = $inClass = 0;
	        $inputCounter++;
		print "Input line number[8]: $inputCounter\n" if ($localDebug);
	    } # end processing individual line array
	    
	    if (ref($apiOwner) ne "HeaderDoc::Header") { # if we've been filling a class/protocol/category object, add it to the header
	        my $name = $apiOwner->name();
	        my $refName = ref($apiOwner);

			# print "$classType : ";
			SWITCH: {
				($classType eq "php" ) && do { 
					push (@classObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "java" ) && do { 
					push (@classObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "cpp" ) && do { 
					push (@classObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "cppt" ) && do { 
					push (@classObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					last SWITCH; };
				($classType eq "occ") && do { 
					push (@classObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner); 
					$objCClassNameToObject{$apiOwner->name()} = $apiOwner;
					last SWITCH; };           
				($classType eq "intf") && do { 
					push (@classObjects, $apiOwner);
					$headerObject->addToProtocols($apiOwner); 
					last SWITCH; 
				};           
				($classType eq "occCat") && do {
					push (@categoryObjects, $apiOwner);
					print "INSERTED CATEGORY into $headerObject\n" if ($ctdebug);
					$headerObject->addToCategories($apiOwner);
					last SWITCH; 
				};           
				($classType eq "C") && do {
					# $cppAccessControlState = "public:";
					$cppAccessControlState = "";
					push (@classObjects, $apiOwner);
					$headerObject->addToClasses($apiOwner);
					last SWITCH;
				};
foreach my $testclass ( $headerObject->classes() ) { print $testclass->name() . "\n"; }
			my $linenum = $inputCounter - 1;
                    	print "$filename:$linenum:Unknown class type '$classType' (known: cpp, objC, intf, occCat)\n";		
			}
	    }
    } # end processing array of line arrays
    push (@headerObjects, $headerObject);
}

if (!$quietLevel) {
    print "======= Beginning post-processing =======\n";
}

if (@classObjects && !$xml_output) {
    foreach my $class (@classObjects) {
	mergeClass($class);
    }
}

# we merge ObjC methods declared in categories into the owning class,
# if we've seen it during processing
if (@categoryObjects && !$xml_output) {
    foreach my $obj (@categoryObjects) {
        my $nameOfAssociatedClass = $obj->className();
        my $categoryName = $obj->categoryName();
        my $localDebug = 0;
        
		if (exists $objCClassNameToObject{$nameOfAssociatedClass}) {
			my $associatedClass = $objCClassNameToObject{$nameOfAssociatedClass};
			$associatedClass->addToMethods($obj->methods());
			
			my $owner = $obj->headerObject();
			
			print "Found category with name $categoryName and associated class $nameOfAssociatedClass\n" if ($localDebug);
			print "Associated class exists\n" if ($localDebug);
			print "Added methods to associated class\n" if ($localDebug);
			if (ref($owner)) {
			    my $numCatsBefore = $owner->categories();
			    # $owner->printObject();
			    $owner->removeFromCategories($obj);
			    my $numCatsAfter = $owner->categories();
				print "Number of categories before: $numCatsBefore after:$numCatsAfter\n" if ($localDebug);
			    
			} else {
				my $filename = $HeaderDoc::headerObject->filename();
				my $linenum = $obj->linenum();
                    		print "$filename:$linenum:Couldn't find Header object that owns the category with name $categoryName.\n";
			}
		} else {
			print "Found category with name $categoryName and associated class $nameOfAssociatedClass\n" if ($localDebug);
			print "Associated class doesn't exist\n" if ($localDebug);
        }
    }
}

foreach my $obj (@headerObjects) {
    if ($man_output) {
	$obj->writeHeaderElementsToManPage();
    } elsif ($xml_output) {
	$obj->writeHeaderElementsToXMLPage();
    } else {
	$obj->createFramesetFile();
	$obj->createTOCFile();
	$obj->writeHeaderElements(); 
	$obj->writeHeaderElementsToCompositePage();
	$obj->createContentFile();
	$obj->writeExportsWithName($rootFileName) if (($export) || ($testingExport));
    }
    if ("$write_control_file" eq "1") {
	print "Writing doc server control file... ";
	$obj->createMetaFile();
	print "done.\n";
    }
}

if ($quietLevel eq "0") {
    print "...done\n";
}
# print "COUNTER: ".$HeaderDoc::counter."\n";
exit 0;


#############################  Subroutines ###################################

# /*! @function nestignore
#     This function includes a list of headerdoc tags that are legal
#     within a headerdoc documentation block (e.g. a C struct)
#     such as parameters, etc.
#
#     The block parser support aspects of this function are
#     deprecated, as the calls to warnHDComment within the block
#     parser no longer exists.  Most calls to warnHDComment from
#     headerDoc2HTML.pl should always result in an error (since
#     they only occur outside the context of a declaration.
#
#     The exception is test point 12, which can cause false
#     positives for @defineblock blocks.
#  */
sub nestignore
{
    my $tag = shift;
    my $dectype = shift;

#print "DT: $dectype TG: $tag\n";

    # defineblock can only be passed in for debug point 12, so
    # this can't break anything.

    if ($dectype =~ /defineblock/o && $tag =~ /^\@define/o) {
	return 1;
    }

    return 0;

    # Old blockparser support logic.  Removed, since it broke other things.
    # if ($dectype =~ /(function|method|typedef)/o && $tag =~ /^\@param/o) {
	# return 1;
    # } elsif ($dectype =~ /\#define/o && $tag =~ /^\@define/o) {
	# return 1;
    # } elsif ($dectype !~ /(typedef|struct)/o && $tag =~ /^\@callback/o) {
	# return 1;
    # } elsif ($dectype !~ /(class|function|method|define)/o && $tag =~ /^\@field/o) {
	# return 1;
    # } elsif ($dectype !~ /(class|function|method|define)/o && $tag =~ /^\@constant/o) {
	# return 1;
    # }

    # return 0;
}

# /*! @function warnHDComment
#     @param teststring string to be checked for headerdoc markup
#     @param linenum line number
#     @param dectype declaration type
#     @param dp debug point string
#  */
sub warnHDComment
{
    my $linearrayref = shift;
    my $blocklinenum = shift;
    my $blockoffset = shift;
    my $dectype = shift;
    my $dp = shift;
    my $filename = $HeaderDoc::headerObject->filename();
    my $localDebug = 2; # Set to 2 so I wouldn't keep turning this off.

    my $line = ${$linearrayref}[$blocklinenum];
    my $linenum = $blocklinenum + $blockoffset;

    my $debugString = "";
    if ($localDebug) { $debugString = " [debug point $dp]"; }

    if ($line =~ /\/\*\!(.*)$/o) {
	my $rest = $1;

	$rest =~ s/^\s*//so;
	$rest =~ s/\s*$//so;

	while (!length($rest) && ($blocklinenum < scalar(@{$linearrayref}))) {
		$blocklinenum++;
		$rest = ${$linearrayref}[$blocklinenum];
		$rest =~ s/^\s*//so;
		$rest =~ s/\s*$//so;
	}

	if ($rest =~ /^\@/o) {
		 if (nestignore($rest, $dectype)) {
#print "IGNORE\n";
			return 0;
		}
	} else {
		printf("Nested headerdoc markup with no tag.\n") if ($localDebug);
	}

	if (!$HeaderDoc::ignore_apiuid_errors) {
		warn("$filename:$linenum: WARNING: Unexpected headerdoc markup found in $dectype declaration$debugString.  Output may be broken.\n");
	}
	return 1;
    }
#print "OK\n";
    return 0;
}


sub mergeClass
{
	my $class = shift;
	my $superName = $class->checkShortLongAttributes("Superclass");
	my $merge_content = 1;
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
			    foreach my $class (@classes) {
				if ($class->accessControl() eq "private") {
					next;
				}
				my $include = 1;
				foreach my $childclass (@childclasses) {
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
	$class->isMerged(1);
}

sub emptyHDok
{
    my $line = shift;
    my $okay = 0;

    SWITCH: {
	($line =~ /\@(function|method|)group/o) && do { $okay = 1; };
	($line =~ /\@language/o) && do { $okay = 1; };
	($line =~ /\@header/o) && do { $okay = 1; };
	($line =~ /\@framework/o) && do { $okay = 1; };
	($line =~ /\@\/define(d)?block/o) && do { $okay = 1; };
	($line =~ /\@lineref/o) && do { $okay = 1; };
    }
    return $okay;
}

# /*! @function getLineArrays
#     @abstract splits the input files into multiple text blocks
#   */
sub getLineArrays {
# @@@
    my $classDebug = 0;
    my $localDebug = 0;
    my $blockDebug = 0;
    my $rawLineArrayRef = shift;
    my @arrayOfLineArrays = ();
    my @generalHeaderLines = ();
    my @classStack = ();
	
    my $inputCounter = 0;
    my $lastArrayIndex = @{$rawLineArrayRef};
    my $line = "";
    my $className = "";
    my $classType = "";

    while ($inputCounter <= $lastArrayIndex) {
        $line = ${$rawLineArrayRef}[$inputCounter];
        
	# inputCounter should always point to the current line being processed

        # we're entering a headerdoc comment--look ahead for @class tag
	my $startline = $inputCounter;

	print "MYLINE: $line\n" if ($localDebug);
        if (($line =~ /^\s*\/\*\!/o) || (($lang eq "java") && ($line =~ /^\s*\/\*\*/o))) {  # entering headerDoc comment
			print "inHDComment\n" if ($localDebug);
			my $headerDocComment = "";
			{
				local $^W = 0;  # turn off warnings since -w is overly sensitive here
				my $in_textblock = 0; my $in_pre = 0;
				while (($line !~ /\*\//o) && ($inputCounter <= $lastArrayIndex)) {
				    # if ($lang eq "java") {
					$line =~ s/\{\s*\@linkplain\s+(.*?)\}/\@link $1\@\/link/sgio;
					$line =~ s/\{\s*\@link\s+(.*?)\}/<code>\@link $1\@\/link<\/code>/sgio;
					$line =~ s/\{\s*\@docroot\s*\}/\\\@\\\@docroot/gio;
					# if ($line =~ /value/o) { warn "line was: $line\n"; }
					$line =~ s/\{\@value\}/\@value/sgio;
					$line =~ s/\{\@inheritDoc\}/\@inheritDoc/sgio;
					# if ($line =~ /value/o) { warn "line now: $line\n"; }
				    # }
				    $line =~ s/([^\\])\@docroot/$1\\\@\\\@docroot/gi;
				    my $templine = $line;
				    while ($templine =~ s/\@textblock//io) { $in_textblock++; }
				    while ($templine =~ s/\@\/textblock//io) { $in_textblock--; }
				    while ($templine =~ s/<pre>//io) { $in_pre++; }
				    while ($templine =~ s/<\/pre>//io) { $in_pre--; }
				    if (!$in_textblock && !$in_pre) {
					$line =~ s/^[ \t]*//o; # remove leading whitespace
				    }
				    $line =~ s/^[*]\s*$/\n/o; # replace sole asterisk with paragraph divider
				    $line =~ s/^[*]\s+(.*)/$1/o; # remove asterisks that precede text
				    $headerDocComment .= $line;
				    # warnHDComment($rawLineArrayRef, $inputCounter, 0, "HeaderDoc comment", "32");
			            $line = ${$rawLineArrayRef}[++$inputCounter];
				    warnHDComment($rawLineArrayRef, $inputCounter, 0, "HeaderDoc comment", "33");
				}
				$line =~ s/\{\s*\@docroot\s*\}/\\\@\\\@docroot/go;
				$headerDocComment .= $line ;
				# warnHDComment($rawLineArrayRef, $inputCounter, 0, "HeaderDoc comment", "34");
				$line = ${$rawLineArrayRef}[++$inputCounter];

				# A HeaderDoc comment block immediately
				# after another one can be legal after some
				# tag types (e.g. @language, @header).
				# We'll postpone this check until the
				# actual parsing.
				# 
				if (!emptyHDok($headerDocComment)) {
					my $emptyDebug = 0;
					warn "curline is $line" if ($emptyDebug);
					warnHDComment($rawLineArrayRef, $inputCounter, 0, "HeaderDoc comment", "35");
				}
			}
			# print "first line after $headerDocComment is $line\n";

			# test for @class, @protocol, or @category comment
			# here is where we create an array of class-specific lines
			# first, get the class name
			my $name = ""; my $type = "";
			if (($headerDocComment =~ /^\/\*!\s*\@class|\@interface|\@protocol|\@category\s*/io ||
			    ($headerDocComment =~ /^\/\*\!\s*\w+/o && (($name,$type)=classLookAhead($rawLineArrayRef, $inputCounter, $lang, $HeaderDoc::sublang)))) ||
			    ($lang eq "java" &&
				($headerDocComment =~ /^\/\*!\s*\@class|\@interface|\@protocol|\@category\s*/io ||
				($headerDocComment =~ /^\/\*\*\s*\w+/o && (($name,$type)=classLookAhead($rawLineArrayRef, $inputCounter, $lang, $HeaderDoc::sublang)))))) {
				print "INCLASS\n" if ($localDebug);
				my $explicitName = "";
				if (length($type)) {
					$headerDocComment =~ s/^\s*\/\*(\*|\!)/\/\*$1 \@$type $name\n/so;
					print "CLARETURNED: \"$name\" \"$type\"\n" if ($localDebug || $classDebug || $blockDebug);
				} else {
					# We had an explicit @class or similar.
					my $getname = $headerDocComment;
					$getname =~ s/^\s*\/\*(\*|\!)\s*\@\w+\s+//so;
					if ($getname =~ /^(\w+)/o) {
						$explicitName = $1;
					}
				}
				my $class = HeaderDoc::ClassArray->new(); # @@@
			   
				# insert line number (short form, since we're in a class)
				my $ln = $startline;
				my $linenumline = "/*! \@lineref $ln */\n";
				if ($lang eq "perl" || $lang eq "shell") {
					$linenumline = "# $linenumline";
				}
				$class->push($linenumline);
				# end insert line number

				($className = $headerDocComment) =~ s/.*\@class|\@protocol|\@category\s+(\w+)\s+.*/$1/so;
				$class->pushlines ($headerDocComment);

				# print "LINE IS $line\n";
				while (($line !~ /class\s|\@class|\@interface\s|\@protocol\s|typedef\s+struct\s/o) && ($inputCounter <= $lastArrayIndex)) {
					$class->push ($line);  
					warnHDComment($rawLineArrayRef, $inputCounter, 0, "class", "36");
					$line = ${$rawLineArrayRef}[++$inputCounter];
					warnHDComment($rawLineArrayRef, $inputCounter, 0, "class", "37");
				}
				# $class->push ($line);  
				my $initial_bracecount = 0; # ($templine =~ tr/{//) - ($templine =~ tr/}//);
				print "[CLASSTYPE]line $line\n" if ($localDebug);

				SWITCH: {
					($line =~ /^\s*\@protocol\s+/o ) && 
						do { 
							$classType = "objCProtocol";  
							# print "FOUND OBJCPROTOCOL\n"; 
							$HeaderDoc::sublang="occ";
							$initial_bracecount++;
							last SWITCH; 
						};
					($line =~ /^\s*typedef\s+struct\s+/o ) && 
						do { 
							$classType = "C";  
							# print "FOUND C CLASS\n"; 
							last SWITCH; 
						};
					($line =~ /^\s*template\s+/o ) && 
						do { 
							$classType = "cppt";  
							# print "FOUND CPP TEMPLATE CLASS\n"; 
							$HeaderDoc::sublang="cpp";
							last SWITCH; 
						};
					($line =~ /^\s*(public|private|protected|)\s*class\s+/o ) && 
						do { 
							$classType = "cpp";  
							# print "FOUND CPP CLASS\n"; 
							$HeaderDoc::sublang="cpp";
							last SWITCH; 
						};
					($line =~ /^\s*(\@class|\@interface)\s+/o ) && 
						do { 
						        # it's either an ObjC class or category
						        if ($line =~ /\(.*\)/o) {
								$classType = "objCCategory"; 
								# print "FOUND OBJC CATEGORY\n"; 
						        } else {
								$classType = "objC"; 
								 # print "FOUND OBJC CLASS\n"; 
						        }
							$HeaderDoc::sublang="occ";
							if ($1 ne "\@class") {
							    $initial_bracecount++;
							}
							last SWITCH; 
						};
					print "Unknown class type (known: cpp, cppt, objCCategory, objCProtocol, C,)\nline=\"$line\"";		
				}
				my $tempclassline = $line;
				$initial_bracecount += ($tempclassline =~ tr/{//) - ($tempclassline =~ tr/}//);
				if ($lang eq "php") {$classType = "php";}
				elsif ($lang eq "java") {$classType = "java";}

				# now we're at the opening line of the class declaration
				# push it into the array
				# print "INCLASS! (line: $inputCounter $line)\n";
				my $inClassBraces = $initial_bracecount;
				my $leftBraces = 0;
				my $rightBraces = 0;

				# make sure we've seen at least one left brace
				# at the start of the class

				# $line = ${$rawLineArrayRef}[++$inputCounter];
				if (!($initial_bracecount) &&
					($line !~ /;/o || (length($explicitName) && 
						classLookAhead($rawLineArrayRef, $inputCounter+1, $lang, $HeaderDoc::sublang, $explicitName)))) {
				    while (($inputCounter <= $lastArrayIndex)
					    && (!($leftBraces))) {
					print "[IP]line=$line\n" if ($localDebug);
					$class->push ($line);
					# print "line $line\n" if ($localDebug);
					# print "LINE IS[1] $line\n";
                                       	$leftBraces = $line =~ tr/{//;
                                       	$rightBraces = $line =~ tr/}//;
                                        $inClassBraces += $leftBraces;
                                        $inClassBraces -= $rightBraces;
					warnHDComment($rawLineArrayRef, $inputCounter, 0, "class", "38");
					$line = ${$rawLineArrayRef}[++$inputCounter];
					# this is legal (headerdoc markup in
					# first line of class).
					# warnHDComment($rawLineArrayRef, $inputCounter, 0, "class", "39");
				    }
				}
			# print "LINE IS[2] $line\n";
				# $inputCounter++;

				$class->push($line);
				$class->bracecount_inc($inClassBraces);
				my $bc = $class->bracecount();
				print "NEW: pushing class $class bc=$bc\n" if ($classDebug);
				print "CURLINE: $line\n" if ($localDebug);

				push(@classStack, $class);
			} else {

			    # HeaderDoc comment, but not a class

			    print "[2] line = $line\n" if ($localDebug);
			    my $class = pop(@classStack);
			    if ($class) {
				my $bc = $class->bracecount();
				print "popped class $class bc=$bc\n" if ($classDebug);
				$class->pushlines($headerDocComment);
				$class->push($line);
			   
				# now collect class lines until the closing
				# curly brace

				if (($classType =~ /cpp/o) || ($classType =~ /^C/o) || ($classType =~ /cppt/o) ||
				    ($classType =~ /php/o) || ($classType =~ /java/o)) {
					my $leftBraces = $headerDocComment =~ tr/{// + $line =~ tr/{//;
					$class->bracecount_inc($leftBraces);
					my $rightBraces = $headerDocComment =~ tr/}// + $line =~ tr/}//;
					$class->bracecount_dec($rightBraces);
				}
				if (($classType =~ /objC/o) || ($classType =~ /objCProtocol/o) || ($classType =~ /objCCategory/o)) {
					# @@@ VERIFY this next line used to be !~, but I think it should be =~
					if ($headerDocComment =~ /\@end/o || $line =~ /\@end/o) {
						$class->bracecount_dec();
					}
				}
				if (my $bc=$class->bracecount()) {
					print "pushing class $class bc=$bc\n" if ($classDebug);
					push(@classStack, $class);
				} else {
					# push (@arrayOfLineArrays, \@classLines);
					my @array = $class->getarray();
					push (@arrayOfLineArrays, \@array);
					print "OUT OF CLASS[2]! (headerDocComment: $inputCounter $headerDocComment)\n" if ($localDebug);

					# insert line number
					my $tc = pop(@classStack);
					my $ln = $inputCounter + 1;
					my $linenumline = "/*! \@lineref $ln */\n";
					if ($lang eq "perl" || $lang eq "shell") {
						$linenumline = "# $linenumline";
					}
					if ($tc) {
						$tc->push($linenumline);
						push(@classStack, $tc);
					} else {
						push(@generalHeaderLines, $linenumline);
					}
					# end insert line number

# print "class declaration was:\n"; foreach my $line (@array) { print "$line\n"; }
					if ($localDebug) {
					    print "array is:\n";
					    foreach my $arrelem (@array) {
						print "$arrelem\n";
					    }
					    print "end of array.\n";
					}
				}
			    } else {
				# globalpushlines (\@generalHeaderLines, $headerDocComment);
				my @linearray = split (/\n/, $headerDocComment);
				foreach my $arrayline (@linearray) {
					push(@generalHeaderLines, "$arrayline\n");
				}
				push(@generalHeaderLines, $line);

				# push (@generalHeaderLines, $headerDocComment);
			    }
			}
		} else {
			print "[3]line=$line\n" if ($classDebug > 3);
			my $class = pop(@classStack);
			if ($class) {
				my $bc = $class->bracecount();
				print "[tail]popped class $class bc=$bc\n" if ($classDebug);

				$class->push($line);
				print "pushed line $line\n" if ($classDebug);
				   
				# now collect class lines until the closing
				# curly brace
	
				if (($classType =~ /cpp/o) || ($classType =~ /^C/o) || ($classType =~ /cppt/o) ||
				    ($classType =~ /php/o) || ($classType =~ /java/o)) {
					my $leftBraces = $line =~ tr/{//;
					$class->bracecount_inc($leftBraces);
					my $rightBraces = $line =~ tr/}//;
					$class->bracecount_dec($rightBraces);
					print "lb=$leftBraces, rb=$rightBraces\n" if ($localDebug);
				} elsif (($classType =~ /objC/o) || ($classType =~ /objCProtocol/o) || ($classType =~ /objCCategory/o)) {
					if ($line =~ /\@end/o) {
						$class->bracecount_dec();
					}
					my $leftBraces = $line =~ tr/{//;
					$class->bracecount_inc($leftBraces);
					my $rightBraces = $line =~ tr/}//;
					$class->bracecount_dec($rightBraces);
					print "lb=$leftBraces, rb=$rightBraces\n" if ($localDebug || $classDebug);
					my $bc = $class->bracecount();
					print "bc=$bc\n" if ($localDebug || $classDebug);
				} else {
					print "WARNING: Unknown classtype $classType\n";
				}
				if (my $bc=$class->bracecount()) {
					print "pushing class $class bc=$bc\n" if ($classDebug);
					push(@classStack, $class);
				} else {
					# push (@arrayOfLineArrays, \@classLines);
					my @array = $class->getarray();
					push (@arrayOfLineArrays, \@array);
					print "OUT OF CLASS! (line: $inputCounter $line)\n" if ($localDebug);
					# insert line number
					my $tc = pop(@classStack);
					my $ln = $inputCounter + 1;
					my $linenumline = "/*! \@lineref $ln */\n";
					if ($lang eq "perl" || $lang eq "shell") {
						$linenumline = "# $linenumline";
					}
					if ($tc) {
						$tc->push($linenumline);
						push(@classStack, $tc);
					} else {
						push(@generalHeaderLines, $linenumline);
					}
					# end insert line number

# print "class declaration was:\n"; foreach my $line (@array) { print "$line\n"; }
					my $localDebug = 0;
					if ($localDebug) {
					    print "array is:\n";
					    foreach my $arrelem (@array) {
						print "$arrelem\n";
					    }
					    print "end of array.\n";
					}
				}
			} else {
				push (@generalHeaderLines, $line); print "PUSHED $line\n" if ($blockDebug);
			}
		}
		$inputCounter++;
	}
    push (@arrayOfLineArrays, \@generalHeaderLines);
    return @arrayOfLineArrays;
}

# /*! @function processCPPHeaderComment
#   */
sub processCPPHeaderComment {
# 	for now, we do nothing with this comment
    return;
}

# /*! @function removeSlashSlashComment
#   */
sub removeSlashSlashComment {
    my $line = shift;
    $line =~ s/\/\/.*$//o;
    return $line;
}


sub get_super {
my $classType = shift;
my $dec = shift;
my $super = "";
my $localDebug = 0;

    print "GS: $dec EGS\n" if ($localDebug);

    $dec =~ s/\n/ /smgo;

    if ($classType =~ /^occ/o) {
	if ($dec !~ s/^\s*\@interface\s*//so) {
	    if ($dec !~ s/^\s*\@protocol\s*//so) {
	    	$dec !~ s/^\s*\@class\s*//so;
	    }
	}
	if ($dec =~ /(\w+)\s*\(\s*(\w+)\s*\)/o) {
	    $super = $1; # delegate is $2
        } elsif (!($dec =~ s/.*?://so)) {
	    $super = "";
	} else {
	    $dec =~ s/\(.*//sgo;
	    $dec =~ s/\{.*//sgo;
	    $super = $dec;
	}
    } elsif ($classType =~ /^cpp$/o) {
	$dec !~ s/^\s*\class\s*//so;
        if (!($dec =~ s/.*?://so)) {
	    $super = "";
	} else {
	    $dec =~ s/\(.*//sgo;
	    $dec =~ s/\{.*//sgo;
	    $dec =~ s/^\s*//sgo;
	    $dec =~ s/^public//go;
	    $dec =~ s/^private//go;
	    $dec =~ s/^protected//go;
	    $dec =~ s/^virtual//go;
	    $super = $dec;
	}
    }

    $super =~ s/^\s*//o;
    $super =~ s/\s.*//o;

    print "$super is super\n" if ($localDebug);
    return $super;
}

# /*! @function determineClassType
#     @discussion determines the class type.
#   */
sub determineClassType {
	my $lineCounter   = shift;
	my $apiOwner      = shift;
	my $inputLinesRef = shift;
	my @inputLines    = @$inputLinesRef;
	my $classType = "unknown";
	my $tempLine = "";
	my $localDebug = 0;

	my $nlines = $#inputLines;
 	do {
	# print "inc\n";
		$tempLine = $inputLines[$lineCounter];
		$lineCounter++;
	} while (($tempLine !~ /class|\@class|\@interface|\@protocol|typedef\s+struct/o) && ($lineCounter <= $nlines));

	if ($tempLine =~ s/class\s//o) {
	 	$classType = "cpp";  
	}
	if ($tempLine =~ s/typedef\s+struct\s//o) {
	    # print "===>Cat: $tempLine\n";
	    $classType = "C"; # standard C "class", such as a
		                       # COM interface
	}
	if ($tempLine =~ s/(\@class|\@interface)\s//o) { 
	    if ($tempLine =~ /\(.*\)/o && ($1 ne "\@class")) {
			# print "===>Cat: $tempLine\n";
			$classType = "occCat";  # a temporary distinction--not in apple_ref spec
									# methods in categories will be lumped in with rest of class, if existent
		} else {
			# print "===>Class: $tempLine\n";
			$classType = "occ"; 
		}
	}
	if ($tempLine =~ s/\@protocol\s//o) {
	 	$classType = "intf";  
	}
	if ($lang eq "php") {
		$classType = "php";
	}
	if ($lang eq "java") {
		$classType = "java";
	}
print "determineClassType: returning $classType\n" if ($localDebug);
	if ($classType eq "unknown") {
		print "Bogus class ($tempLine)\n";
	}
	
	$HeaderDoc::sublang = $classType;
	return $classType;
}

# /*! @function processClassComments
#   */
sub processClassComment {
	my $apiOwner = shift;
	my $headerObj = $apiOwner;
	my $rootOutputDir = shift;
	my $fieldArrayRef = shift;
	my @fields = @$fieldArrayRef;
	my $classType = shift;
	my $filename = $HeaderDoc::headerObject->filename();
	my $linenum = shift;
	
	SWITCH: {
		($classType eq "php" ) && do { $apiOwner = HeaderDoc::CPPClass->new; $apiOwner->filename($filename); last SWITCH; };
		($classType eq "java" ) && do { $apiOwner = HeaderDoc::CPPClass->new; $apiOwner->filename($filename); last SWITCH; };
		($classType eq "cpp" ) && do { $apiOwner = HeaderDoc::CPPClass->new; $apiOwner->filename($filename); last SWITCH; };
		($classType eq "cppt" ) && do { $apiOwner = HeaderDoc::CPPClass->new; $apiOwner->filename($filename); last SWITCH; };
		($classType eq "occ") && do { $apiOwner = HeaderDoc::ObjCClass->new; $apiOwner->filename($filename); last SWITCH; };           
		($classType eq "occCat") && do { $apiOwner = HeaderDoc::ObjCCategory->new; $apiOwner->filename($filename); last SWITCH; };           
		($classType eq "intf") && do { $apiOwner = HeaderDoc::ObjCProtocol->new; $apiOwner->filename($filename); last SWITCH; };           
		($classType eq "C") && do { $apiOwner = HeaderDoc::CPPClass->new; $apiOwner->filename($filename); $apiOwner->CClass(1); last SWITCH; };
		print "Unknown type ($classType). known: classes (ObjC and C++), ObjC categories and protocols\n";		
	}
	# preserve class nesting
	$apiOwner->linenum($linenum);
	$apiOwner->apiOwner($HeaderDoc::currentClass);
	$HeaderDoc::currentClass = $apiOwner;

	if ($xml_output) {
	    $apiOwner->outputformat("hdxml");
	} else { 
	    $apiOwner->outputformat("html");
	}
	$apiOwner->headerObject($headerObj);
	$apiOwner->outputDir($rootOutputDir);
	foreach my $field (@fields) {
		SWITCH: {
			($field =~ /^\/\*\!/o) && do {last SWITCH;}; # ignore opening /*!
			(($lang eq "java") && ($field =~ /^\s*\/\*\*/o)) && do {last SWITCH;}; # ignore opening /**
			($field =~ s/^(class|interface|template)(\s+)/$2/io) && 
				do {
					my ($name, $disc);
					my $filename = $HeaderDoc::headerObject->filename();
					# print "CLASSNAMEANDDISC:\n";
					($name, $disc) = &getAPINameAndDisc($field);
					my $classID = ref($apiOwner);
					$apiOwner->name($name);
					$apiOwner->filename($filename);
					if (length($disc)) {$apiOwner->discussion($disc);};
					$functionGroup = "";
					$HeaderDoc::globalGroup = "";
                	last SWITCH;
            	};
			($field =~ s/^see(also|)(\s+)/$2/io) &&
				do {
					$apiOwner->see($field);
				};
			($field =~ s/^protocol(\s+)/$1/io) && 
				do {
					my ($name, $disc);
					my $filename = $HeaderDoc::headerObject->filename();
					($name, $disc) = &getAPINameAndDisc($field); 
					$apiOwner->name($name);
					$apiOwner->filename($filename);
					if (length($disc)) {$apiOwner->discussion($disc);};
					$functionGroup = "";
					$HeaderDoc::globalGroup = "";
					last SWITCH;
				};
			($field =~ s/^category(\s+)/$1/io) && 
				do {
					my ($name, $disc);
					my $filename = $HeaderDoc::headerObject->filename();
					($name, $disc) = &getAPINameAndDisc($field); 
					$apiOwner->name($name);
					$apiOwner->filename($filename);
					if (length($disc)) {$apiOwner->discussion($disc);};
					$functionGroup = "";
					$HeaderDoc::globalGroup = "";
					last SWITCH;
				};
            			($field =~ s/^templatefield(\s+)/$1/io) && do {     
                                	$field =~ s/^\s+|\s+$//go;
                    			$field =~ /(\w*)\s*(.*)/so;
                    			my $fName = $1;
                    			my $fDesc = $2;
                    			my $fObj = HeaderDoc::MinorAPIElement->new();
					$fObj->linenum($linenum);
					$fObj->apiOwner($apiOwner);
                    			$fObj->outputformat($apiOwner->outputformat);
                    			$fObj->name($fName);
                    			$fObj->discussion($fDesc);
                    			$apiOwner->addToFields($fObj);
# print "inserted field $fName : $fDesc";
                                	last SWITCH;
                        	};
			($field =~ s/^super(class|)(\s+)/$2/io) && do { $apiOwner->attribute("Superclass", $field, 0); $apiOwner->explicitSuper(1); last SWITCH; };
			($field =~ s/^throws(\s+)/$1/io) && do {$apiOwner->throws($field); last SWITCH;};
			($field =~ s/^exception(\s+)/$1/io) && do {$apiOwner->throws($field); last SWITCH;};
			($field =~ s/^abstract(\s+)/$1/io) && do {$apiOwner->abstract($field); last SWITCH;};
			($field =~ s/^discussion(\s+)/$1/io) && do {$apiOwner->discussion($field); last SWITCH;};
			($field =~ s/^availability(\s+)/$1/io) && do {$apiOwner->availability($field); last SWITCH;};
			($field =~ s/^since(\s+)/$1/io) && do {$apiOwner->availability($field); last SWITCH;};
            		($field =~ s/^author(\s+)/$1/io) && do {$apiOwner->attribute("Author", $field, 0); last SWITCH;};
			($field =~ s/^version(\s+)/$1/io) && do {$apiOwner->attribute("Version", $field, 0); last SWITCH;};
            		($field =~ s/^deprecated(\s+)/$1/io) && do {$apiOwner->attribute("Deprecated", $field, 0); last SWITCH;};
            		($field =~ s/^version(\s+)/$1/io) && do {$apiOwner->attribute("Version", $field, 0); last SWITCH;};
			($field =~ s/^updated(\s+)/$1/io) && do {$apiOwner->updated($field); last SWITCH;};
	    ($field =~ s/^attribute(\s+)/$1/io) && do {
		    my ($attname, $attdisc) = &getAPINameAndDisc($field);
		    if (length($attname) && length($attdisc)) {
			$apiOwner->attribute($attname, $attdisc, 0);
		    } else {
			warn "$filename:$linenum:Missing name/discussion for attribute\n";
		    }
		    last SWITCH;
		};
	    ($field =~ s/^attributelist(\s+)/$1/io) && do {
		    $field =~ s/^\s*//so;
		    $field =~ s/\s*$//so;
		    my ($name, $lines) = split(/\n/, $field, 2);
		    $name =~ s/^\s*//so;
		    $name =~ s/\s*$//so;
		    $lines =~ s/^\s*//so;
		    $lines =~ s/\s*$//so;
		    if (length($name) && length($lines)) {
			my @attlines = split(/\n/, $lines);
			foreach my $line (@attlines) {
			    $apiOwner->attributelist($name, $line);
			}
		    } else {
			warn "$filename:$linenum:Missing name/discussion for attributelist\n";
		    }
		    last SWITCH;
		};
	    ($field =~ s/^attributeblock(\s+)/$1/io) && do {
		    my ($attname, $attdisc) = &getAPINameAndDisc($field);
		    if (length($attname) && length($attdisc)) {
			$apiOwner->attribute($attname, $attdisc, 1);
		    } else {
			warn "$filename:$linenum:Missing name/discussion for attributeblock\n";
		    }
		    last SWITCH;
		};
			($field =~ s/^namespace(\s+)/$1/io) && do {$apiOwner->namespace($field); last SWITCH;};
			($field =~ s/^instancesize(\s+)/$1/io) && do {$apiOwner->attribute("Instance Size", $field, 0); last SWITCH;};
			($field =~ s/^performance(\s+)/$1/io) && do {$apiOwner->attribute("Performance", $field, 1); last SWITCH;};
			# ($field =~ s/^subclass(\s+)/$1/io) && do {$apiOwner->attributelist("Subclasses", $field); last SWITCH;};
			($field =~ s/^nestedclass(\s+)/$1/io) && do {$apiOwner->attributelist("Nested Classes", $field); last SWITCH;};
			($field =~ s/^coclass(\s+)/$1/io) && do {$apiOwner->attributelist("Co-Classes", $field); last SWITCH;};
			($field =~ s/^helper(class|)(\s+)/$2/io) && do {$apiOwner->attributelist("Helper Classes", $field); last SWITCH;};
			($field =~ s/^helps(\s+)/$1/io) && do {$apiOwner->attribute("Helps", $field, 0); last SWITCH;};
			($field =~ s/^classdesign(\s+)/$1/io) && do {$apiOwner->attribute("Class Design", $field, 1); last SWITCH;};
			($field =~ s/^dependency(\s+)/$1/io) && do {$apiOwner->attributelist("Dependencies", $field); last SWITCH;};
			($field =~ s/^ownership(\s+)/$1/io) && do {$apiOwner->attribute("Ownership Model", $field, 1); last SWITCH;};
			($field =~ s/^security(\s+)/$1/io) && do {$apiOwner->attribute("Security", $field, 1); last SWITCH;};
			($field =~ s/^whysubclass(\s+)/$1/io) && do {$apiOwner->attribute("Reason to Subclass", $field, 1); last SWITCH;};
			# print "Unknown field in class comment: $field\n";
			warn "$filename:$linenum:Unknown field (\@$field) in class comment (".$apiOwner->name().")\n";
		}
	}
	return $apiOwner;
}

# /*! @function processHeaderComment
#   */ 
sub processHeaderComment {
    my $apiOwner = shift;
    my $rootOutputDir = shift;
    my $fieldArrayRef = shift;
    my @fields = @$fieldArrayRef;
    my $linenum = $apiOwner->linenum();
    my $filename = $apiOwner->filename();
    my $localDebug = 0;

	foreach my $field (@fields) {
	    # print "header field: |$field|\n";
		SWITCH: {
			($field =~ /^\/\*\!/o)&& do {last SWITCH;}; # ignore opening /*!
			(($lang eq "java") && ($field =~ /^\s*\/\*\*/o)) && do {last SWITCH;}; # ignore opening /**
			($field =~ s/^see(also)\s+//o) &&
				do {
					$apiOwner->see($field);
				};
			(($field =~ /^header\s+/io) ||
			 ($field =~ /^framework\s+/io)) && 
			    do {
			 	if ($field =~ s/^framework//io) {
					$apiOwner->isFramework(1);
				} else {
					$field =~ s/^header//o;
				}
				
				my ($name, $disc);
				($name, $disc) = &getAPINameAndDisc($field); 
				my $longname = $name; #." (".$apiOwner->name().")";
				if (length($name)) {
					print "Setting header name to $longname\n" if ($debugging);
					$apiOwner->name($longname);
				}
				print "Discussion is:\n" if ($debugging);
				print "$disc\n" if ($debugging);
				if (length($disc)) {$apiOwner->discussion($disc);};
				last SWITCH;
			};
            ($field =~ s/^availability\s+//io) && do {$apiOwner->availability($field); last SWITCH;};
	    ($field =~ s/^since\s+//io) && do {$apiOwner->availability($field); last SWITCH;};
            ($field =~ s/^author\s+//io) && do {$apiOwner->attribute("Author", $field, 0); last SWITCH;};
	    ($field =~ s/^version\s+//io) && do {$apiOwner->attribute("Version", $field, 0); last SWITCH;};
            ($field =~ s/^deprecated\s+//io) && do {$apiOwner->attribute("Deprecated", $field, 0); last SWITCH;};
            ($field =~ s/^version\s+//io) && do {$apiOwner->attribute("Version", $field, 0); last SWITCH;};
	    ($field =~ s/^attribute\s+//io) && do {
		    my ($attname, $attdisc) = &getAPINameAndDisc($field);
		    if (length($attname) && length($attdisc)) {
			$apiOwner->attribute($attname, $attdisc, 0);
		    } else {
			warn "$filename:$linenum:Missing name/discussion for attribute\n";
		    }
		    last SWITCH;
		};
	    ($field =~ s/^attributelist\s+//io) && do {
		    $field =~ s/^\s*//so;
		    $field =~ s/\s*$//so;
		    my ($name, $lines) = split(/\n/, $field, 2);
		    $name =~ s/^\s*//so;
		    $name =~ s/\s*$//so;
		    $lines =~ s/^\s*//so;
		    $lines =~ s/\s*$//so;
		    if (length($name) && length($lines)) {
			my @attlines = split(/\n/, $lines);
			foreach my $line (@attlines) {
			    $apiOwner->attributelist($name, $line);
			}
		    } else {
			warn "$filename:$linenum:Missing name/discussion for attributelist\n";
		    }
		    last SWITCH;
		};
	    ($field =~ s/^attributeblock\s+//io) && do {
		    my ($attname, $attdisc) = &getAPINameAndDisc($field);
		    if (length($attname) && length($attdisc)) {
			$apiOwner->attribute($attname, $attdisc, 1);
		    } else {
			warn "$filename:$linenum:Missing name/discussion for attributeblock\n";
		    }
		    last SWITCH;
		};
            ($field =~ s/^updated\s+//io) && do {$apiOwner->updated($field); last SWITCH;};
            ($field =~ s/^abstract\s+//io) && do {$apiOwner->abstract($field); last SWITCH;};
            ($field =~ s/^discussion\s+//io) && do {$apiOwner->discussion($field); last SWITCH;};
            ($field =~ s/^copyright\s+//io) && do { $apiOwner->headerCopyrightOwner($field); last SWITCH;};
            ($field =~ s/^meta\s+//io) && do {$apiOwner->HTMLmeta($field); last SWITCH;};
	    ($field =~ s/^language\s+//io) && do {
		SWITCH {
		    ($field =~ /^\s*c\+\+\s*$/io) && do { $HeaderDoc::sublang = "cpp"; last SWITCH; };
		    ($field =~ /^\s*objc\s*$/io) && do { $HeaderDoc::sublang = "occ"; last SWITCH; };
		    ($field =~ /^\s*pascal\s*$/io) && do { $HeaderDoc::sublang = "pascal"; last SWITCH; };
		    ($field =~ /^\s*perl\s*$/io) && do { $HeaderDoc::sublang = "perl"; last SWITCH; };
		    ($field =~ /^\s*shell\s*$/io) && do { $HeaderDoc::sublang = "shell"; last SWITCH; };
		    ($field =~ /^\s*php\s*$/io) && do { $HeaderDoc::sublang = "php"; last SWITCH; };
		    ($field =~ /^\s*javascript\s*$/io) && do { $HeaderDoc::sublang = "javascript"; last SWITCH; };
		    ($field =~ /^\s*java\s*$/io) && do { $HeaderDoc::sublang = "java"; last SWITCH; };
		    ($field =~ /^\s*c\s*$/io) && do { $HeaderDoc::sublang = "C"; last SWITCH; };
			{
				warn("$filename:$linenum:Unknown language $field in header comment\n");
			};
		};
	    };
            ($field =~ s/^CFBundleIdentifier\s+//io) && do {$apiOwner->attribute("CFBundleIdentifier", $field, 0); last SWITCH;};
            ($field =~ s/^related\s+//io) && do {$apiOwner->attributelist("Related Headers", $field); last SWITCH;};
            ($field =~ s/^(compiler|)flag\s+//io) && do {$apiOwner->attributelist("Compiler Flags", $field); last SWITCH;};
            ($field =~ s/^preprocinfo\s+//io) && do {$apiOwner->attribute("Preprocessor Behavior", $field, 1); last SWITCH;};
	    ($field =~ s/^whyinclude\s+//io) && do {$apiOwner->attribute("Reason to Include", $field, 1); last SWITCH;};
            ($field =~ s/^ignore\s+//io) && do { $field =~ s/\n//smgo; $field =~ s/<br>//sgo; $field =~ s/^\s*//sgo; $field =~ s/\s*$//sgo;
		# push(@HeaderDoc::perHeaderIgnorePrefixes, $field);
		$HeaderDoc::perHeaderIgnorePrefixes{$field} = $field;
		if (!($reprocess_input)) {$reprocess_input = 1;} print "ignoring $field" if ($localDebug); last SWITCH;};
            # warn("$filename:$linenum:Unknown field in header comment: $field\n");
	    warn("$filename:$linenum:Unknown field (\@$field) in header comment.\n");
		}
	}


	return $apiOwner;
}

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
	print "output path: $output_path\n";
	print "short output path: $short_output_path\n";
	print "long output path: $long_output_path\n";
	print "input path and filename: $input_path_and_filename\n";
	print "input path: $input_path\n";
	print "filename: $filename\n";
	print "output file: $output_file\n";
    }

    if (-e $output_file) {
	# don't risk writing over original header
	$output_file .= "-stripped";
	print "WARNING: output file exists.  Saving as\n\n";
	print "        $output_file\n\n";
	print "instead.\n";
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
	print "line $line\n" if ($localDebug);
	print "inComment $inComment\n" if ($localDebug);
        if (($line =~ /^\/\*\!/o) || (($lang eq "java") && ($line =~ /^\s*\/\*\*/o))) {  # entering headerDoc comment
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

# print "text is $text\n";
    print OUTFILE $text;

    close OUTFILE;
}

sub classLookAhead
{
    my $lineref = shift;
    my $inputCounter = shift;
    my $lang = shift;
    my $sublang = shift;

    my $searchname = "";
    if (@_) {
	$searchname = shift;
    }

    my @linearray = @{$lineref};
    my $inComment = 0;
    my $inILC = 0;
    my $inAt = 0;
    my $localDebug = 0;

    my ($sotemplate, $eotemplate, $operator, $soc, $eoc, $ilc, $sofunction,
        $soprocedure, $sopreproc, $lbrace, $rbrace, $unionname, $structname,
        $typedefname, $varname, $constname, $structisbrace, $macronameref)
		= parseTokens($lang, $sublang);

    my $nametoken = "";
    my $typetoken = "";
    my $occIntfName = "";
    my $occColon = 0;
    my $occParen = 0;

    my $nlines = scalar(@linearray);
    while ($inputCounter < $nlines) {
	my $line = $linearray[$inputCounter];
	my @parts = split(/((\/\*|\/\/|\*\/|\W))/, $line);

	print "CLALINE: $line\n" if ($localDebug);

	foreach my $token (@parts) {
		print "TOKEN: $token\n" if ($localDebug);
		if (!length($token)) {
			next;
			print "CLA:notoken\n" if ($localDebug);
		} elsif ($token eq "$soc") {
			$inComment = 1;
			print "CLA:soc\n" if ($localDebug);
		} elsif ($token eq "$ilc") {
			$inILC = 1;
			print "CLA:ilc\n" if ($localDebug);
		} elsif ($token eq "$eoc") {
			$inComment = 0;
			print "CLA:eoc\n" if ($localDebug);
		} elsif ($token =~ /\s+/o) {
			print "CLA:whitespace\n" if ($localDebug);
		} elsif ($inComment) {
			print "CLA:comment\n" if ($localDebug);
		} elsif (length($occIntfName)) {
			if ($token eq ":") {
				$occColon = 1;
				$occIntfName .= $token;
			} elsif ($occColon && $token !~ /\s/o) {
				my $testnameA = $occIntfName;
				$occIntfName .= $token;
				my $testnameB = $searchname;
				$testnameB =~ s/:$//so;
				if ((!length($searchname)) || $testnameA eq $testnameB) {
					return ($occIntfName, $typetoken);
				} else {
					$occIntfName = ""; $typetoken = "";
				}
			} elsif ($token eq "(") {
				$occParen++;
				$occIntfName .= $token;
			} elsif ($token eq ")") {
				$occParen--;
				$occIntfName .= $token;
			} elsif ($token =~ /\s/o) {
				$occIntfName .= $token;
			} elsif (!$occParen) {
				# return ($occIntfName, $typetoken);
				my $testnameA = $occIntfName;
				my $testnameB = $searchname;
				$testnameB =~ s/:$//so;
				if ((!length($searchname)) || $testnameA eq $testnameB) {
					return ($occIntfName, $typetoken);
				} else {
					$occIntfName = ""; $typetoken = "";
				}
			}
		} else {
			print "CLA:text\n" if ($localDebug);
			if ($token =~ /\;/o) {
				print "CLA:semi\n" if ($localDebug);
				next;
			} elsif ($token =~ /\@/o) {
				$inAt = 1;
				print "CLA:inAt\n" if ($localDebug);
			} elsif (!$inAt && $token =~ /^class$/o) {
				print "CLA:cpp_or_java_class\n" if ($localDebug);
				$typetoken = "class";
			} elsif ($inAt && $token =~ /^(class|interface|protocol)$/o) {
				print "CLA:occ_$1\n" if ($localDebug);
				$typetoken = $1;
			} else {
				# The first non-comment token isn't a class.
				if ($typetoken eq "") {
					print "CLA:NOTACLASS:\"$token\"\n" if ($localDebug);
					return ();
				} else {
					print "CLA:CLASSNAME:\"$token\"\n" if ($localDebug);
					if ($typetoken eq "interface") {
						$occIntfName = $typetoken;
					} else {
						if ((!length($searchname)) || $token eq $searchname) {
							return ($token, $typetoken);
						} else { $typetoken = ""; }
					}
				}
			}
		}
	}

	$inputCounter++; $inILC = 0;
    }

    # Yikes!  We ran off the end of the file!
    if (!length($searchname)) { warn "ClassLookAhead ran off EOF\n"; }
    return ();
}

# @@@@@@@
sub getAvailabilityMacros
{
    my $filename = shift;

    my @availabilitylist = ();

    if (-f $filename) {
	@availabilitylist = &linesFromFile($filename);
    } else {
	# @availabilitylist = &linesFromFile($filename);
	warn "Can't open $filename for availability macros\n";
    }

    foreach my $line (@availabilitylist) {
	addAvailabilityMacro($line);
    }
}

sub addAvailabilityMacro($)
{
    my $localDebug = 0;
    my $line = shift;

    my ($token, $description) = split(/\s/, $line, 2);
    if (length($token) && length($description)) {
	print "AVTOKEN: $token\nDESC: $description\n" if ($localDebug);
	# push(@HeaderDoc::ignorePrefixes, $token);
	$HeaderDoc::availability_defs{$token} = $description;
    }
}

# /*! Grab any #include directives. */
sub processIncludes($$)
{
    my $lineArrayRef = shift;
    my $pathname = shift;
    my @lines = @{$lineArrayRef};
    my $filename = basename($pathname);

    my $includeListRef = $HeaderDoc::perHeaderIncludes{$filename};
    my @includeList = ();
    if ($includeListRef) {
	@includeList = @{$includeListRef};
    }

    my $linenum = 1;
    foreach my $line (@lines) {
	my $hackline = $line;
	if ($hackline =~ s/^\s*#include\s+//so) {
		my $incfile = "";
		if ($hackline =~ /^(<.*?>)/o) {
			$incfile = $1;
		} elsif ($hackline =~ /^(\".*?\")/o) {
			$incfile = $1;
		} else {
			warn "$filename:$linenum:Unable to determine include file name for \"$line\".\n";
		}
		if (length($incfile)) {
			push(@includeList, $incfile);
		}
	}
	$linenum++;
    }

    if (0) {
	print "Includes for \"$filename\":\n";
	foreach my $name (@includeList) {
		print "$name\n";
	}
    }

    $HeaderDoc::perHeaderIncludes{$filename} = \@includeList;
}

sub printVersionInfo {
    my $av = HeaderDoc::APIOwner->VERSION();
    my $hev = HeaderDoc::HeaderElement->VERSION();
    my $hv = HeaderDoc::Header->VERSION();
    my $cppv = HeaderDoc::CPPClass->VERSION();
    my $objcv = HeaderDoc::ObjCClass->VERSION();
    my $objcprotocolv = HeaderDoc::ObjCProtocol->VERSION();
    my $fv = HeaderDoc::Function->VERSION();
    my $mv = HeaderDoc::Method->VERSION();
    my $tv = HeaderDoc::Typedef->VERSION();
    my $sv = HeaderDoc::Struct->VERSION();
    my $cv = HeaderDoc::Constant->VERSION();
    my $vv = HeaderDoc::Var->VERSION();
    my $ev = HeaderDoc::Enum->VERSION();
    my $uv = HeaderDoc::Utilities->VERSION();
    my $me = HeaderDoc::MinorAPIElement->VERSION();
    
	print "----------------------------------------------------\n";
	print "\tHeaderDoc version $VERSION.\n";
	print "\tModules:\n";
	print "\t\tAPIOwner - $av\n";
	print "\t\tHeaderElement - $hev\n";
	print "\t\tHeader - $hv\n";
	print "\t\tCPPClass - $cppv\n";
	print "\t\tObjClass - $objcv\n";
	print "\t\tObjCProtocol - $objcprotocolv\n";
	print "\t\tFunction - $fv\n";
	print "\t\tMethod - $mv\n";
	print "\t\tTypedef - $tv\n";
	print "\t\tStruct - $sv\n";
	print "\t\tConstant - $cv\n";
	print "\t\tEnum - $ev\n";
	print "\t\tVar - $vv\n";
	print "\t\tMinorAPIElement - $me\n";
	print "\t\tUtilities - $uv\n";
	print "----------------------------------------------------\n";
}

################################################################################
# Version Notes
# 1.61 (02/24/2000) Fixed getLineArrays to respect paragraph breaks in comments that 
#                   have an asterisk before each line.
################################################################################

