#! /usr/bin/perl -w
#
# Class name: APIOwner
# Synopsis: Abstract superclass for Header and OO structures
#
# Author: Matt Morse (matt@apple.com)
# Last Updated: $Date: 2004/06/13 04:59:12 $
# 
# Method additions by SKoT McDonald <skot@tomandandy.com> Aug 2001 
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
package HeaderDoc::APIOwner;

BEGIN {
	foreach (qw(Mac::Files)) {
	    $MOD_AVAIL{$_} = eval "use $_; 1";
    }
}
use HeaderDoc::HeaderElement;
use HeaderDoc::DBLookup;
use HeaderDoc::Utilities qw(findRelativePath safeName getAPINameAndDisc convertCharsForFileMaker printArray printHash resolveLink quote sanitize);
use File::Basename;
use Cwd;

use strict;
use vars qw($VERSION @ISA);
$VERSION = '1.20';

# Inheritance
@ISA = qw(HeaderDoc::HeaderElement);
################ Portability ###################################
my $isMacOS;
my $pathSeparator;
if ($^O =~ /MacOS/io) {
	$pathSeparator = ":";
	$isMacOS = 1;
} else {
	$pathSeparator = "/";
	$isMacOS = 0;
}
################ General Constants ###################################
my $debugging = 0;
my $theTime = time();
my ($sec, $min, $hour, $dom, $moy, $year, @rest);
($sec, $min, $hour, $dom, $moy, $year, @rest) = localtime($theTime);
$moy++;
$year += 1900;
my $dateStamp = HeaderDoc::HeaderElement::strdate($moy, $dom, $year);
######################################################################

my $depth = 0;


# class variables and accessors
{
    my $_copyrightOwner;
    my $_defaultFrameName;
    my $_compositePageName;
    my $_htmlHeader;
    my $_apiUIDPrefix;
    # my $_headerObject;
    
    sub copyrightOwner {    
        my $class = shift;
        if (@_) {
            $_copyrightOwner = shift;
        }
        return $_copyrightOwner;
    }

    sub defaultFrameName {    
        my $class = shift;
        if (@_) {
            $_defaultFrameName = shift;
        }
        return $_defaultFrameName;
    }

    sub compositePageName {    
        my $class = shift;
        if (@_) {
            $_compositePageName = shift;
        }
        return $_compositePageName;
    }

    sub htmlHeader {
        my $class = shift;
        if (@_) {
            $_htmlHeader = shift;
        }
        return $_htmlHeader;
    }

    sub apiUIDPrefix {    
        my $class = shift;
        if (@_) {
            $_apiUIDPrefix = shift;
        }
        return $_apiUIDPrefix;
    }

    # sub headerObject {
	# my $class = shift;
# 
	# if (@_) {
            # $_headerObject = shift;
	# }
	# return $_headerObject;
    # }
}

sub headerObject {
	my $class = shift;

	if (@_) {
            $class->{HEADEROBJECT} = shift;
	}
	return $class->{HEADEROBJECT};
}

sub fix_date
{
    $dateStamp = HeaderDoc::HeaderElement::strdate($moy, $dom, $year);
    # print "fixed date stamp.\n";
    return $dateStamp;
}

sub new {
    my($param) = shift;
    my($class) = ref($param) || $param;
    my $self = {};
    
    bless($self, $class);
    $self->_initialize();
    return($self);
}

sub _initialize {
    my($self) = shift;

    $self->SUPER::_initialize();
    
    # $self->{OUTPUTDIR} = undef;
    $self->{CONSTANTS} = ();
    $self->{FUNCTIONS} = ();
    $self->{METHODS} = ();
    $self->{TYPEDEFS} = ();
    $self->{STRUCTS} = ();
    $self->{VARS} = ();
    $self->{PDEFINES} = ();
    $self->{ENUMS} = ();
    # $self->{CONSTANTSDIR} = undef;
    # $self->{DATATYPESDIR} = undef;
    # $self->{STRUCTSDIR} = undef;
    # $self->{VARSDIR} = undef;
    # $self->{FUNCTIONSDIR} = undef;
    # $self->{METHODSDIR} = undef;
    # $self->{PDEFINESDIR} = undef;
    # $self->{ENUMSDIR} = undef;
    # $self->{EXPORTSDIR} = undef;
    # $self->{EXPORTINGFORDB} = 0;
    $self->{TOCTITLEPREFIX} = 'GENERIC_OWNER:';
    # $self->{HEADEROBJECT} = undef;
    $self->{NAMESPACE} = "";
    $self->{UPDATED} = "";
    $self->{EXPLICITSUPER} = 0;
    $self->{CLASSES} = ();
    $self->{ISFRAMEWORK} = 0;
    $self->{ISMERGED} = 0;
    $self->{CCLASS} = 0;
    $self->{HEADEROBJECT} = 0;
    $self->{CLASS} = "HeaderDoc::APIOwner";
} 

sub clone {
    my $self = shift;
    my $clone = undef;
    if (@_) {
	$clone = shift;
    } else {
	$clone = HeaderDoc::APIOwner->new();
    }

    $self->SUPER::clone($clone);

    # now clone stuff specific to API owner

    $clone->{OUTPUTDIR} = $self->{OUTPUTDIR};
    $clone->{CONSTANTS} = ();
    if ($self->{CONSTANTS}) {
        my @params = @{$self->{CONSTANTS}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{CONSTANTS}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }
    $clone->{FUNCTIONS} = ();
    if ($self->{FUNCTIONS}) {
        my @params = @{$self->{FUNCTIONS}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{FUNCTIONS}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }
    $clone->{METHODS} = ();
    if ($self->{METHODS}) {
        my @params = @{$self->{METHODS}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{METHODS}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }
    $clone->{TYPEDEFS} = ();
    if ($self->{TYPEDEFS}) {
        my @params = @{$self->{TYPEDEFS}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{TYPEDEFS}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }
    $clone->{STRUCTS} = ();
    if ($self->{STRUCTS}) {
        my @params = @{$self->{STRUCTS}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{STRUCTS}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }
    $clone->{VARS} = ();
    if ($self->{VARS}) {
        my @params = @{$self->{VARS}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{VARS}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }
    $clone->{PDEFINES} = ();
    if ($self->{PDEFINES}) {
        my @params = @{$self->{PDEFINES}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{PDEFINES}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }
    $clone->{ENUMS} = ();
    if ($self->{ENUMS}) {
        my @params = @{$self->{ENUMS}};
        foreach my $param (@params) {
            my $cloneparam = $param->clone();
            push(@{$clone->{ENUMS}}, $cloneparam);
            $cloneparam->apiOwner($clone);
	}
    }

    $clone->{CONSTANTSDIR} = $self->{CONSTANTSDIR};
    $clone->{DATATYPESDIR} = $self->{DATATYPESDIR};
    $clone->{STRUCTSDIR} = $self->{STRUCTSDIR};
    $clone->{VARSDIR} = $self->{VARSDIR};
    $clone->{FUNCTIONSDIR} = $self->{FUNCTIONSDIR};
    $clone->{METHODSDIR} = $self->{METHODSDIR};
    $clone->{PDEFINESDIR} = $self->{PDEFINESDIR};
    $clone->{ENUMSDIR} = $self->{ENUMSDIR};
    $clone->{EXPORTSDIR} = $self->{EXPORTSDIR};
    $clone->{EXPORTINGFORDB} = $self->{EXPORTINGFORDB};
    $clone->{TOCTITLEPREFIX} = $self->{TOCTITLEPREFIX};
    $clone->{HEADEROBJECT} = $self->{HEADEROBJECT};
    $clone->{NAMESPACE} = $self->{NAMESPACE};
    $clone->{UPDATED} = $self->{UPDATED};
    $clone->{EXPLICITSUPER} = $self->{EXPLICITSUPER};
    $clone->{CLASSES} = $self->{CLASSES};
    $clone->{ISFRAMEWORK} = $self->{ISFRAMEWORK};
    $clone->{ISMERGED} = $self->{ISMERGED};
    $clone->{CCLASS} = $self->{CCLASS};
    $clone->{HEADEROBJECT} = $self->{HEADEROBJECT} = 0;

    return $clone;
}


sub CClass
{
    my $self = shift;
    if (@_) {
	$self->{CCLASS} = shift;
    }
    return $self->{CCLASS};
}


sub isCOMInterface
{
    return 0;
}


sub isAPIOwner
{
    return 1;
}


# /*! @function explicitSuper
#     @abstract Test if superclass was specified in markup
#     @discussion
# 	If the superclass is explicitly specified in the markup,
# 	it means that we'd like to include the functions,
# 	data types, etc. from the superclass in the subclass's
# 	documentation where possible.
#  */
sub explicitSuper
{
    my $self = shift;
    if (@_) {
	my $value = shift;
	$self->{EXPLICITSUPER} = $value;
    }
    return $self->{EXPLICITSUPER};
}

# /*! @function isMerged
#     @abstract get/set whether this class has had its superclass's members
#     merged in yet (if applicable)
#  */
sub isMerged
{
    my $self = shift;

    if (@_) {
	my $value = shift;
	$self->{ISMERGED} = $value;
    }

    return $self->{ISMERGED};
}

# /*! @function isFramework
#     @abstract set whether this file contains framework documentation
#  */
sub isFramework
{
    my $self = shift;

    if (@_) {
	my $value = shift;
	$self->{ISFRAMEWORK} = $value;
    }

    return $self->{ISFRAMEWORK};
}

# /*! @function classes
#     @abstract return subclasses of this class (or classes within this header)
#  */
sub classes
{
    my $self = shift;
    if (@_) {
        @{ $self->{CLASSES} } = @_;
    }
    ($self->{CLASSES}) ? return @{ $self->{CLASSES} } : return ();
}


# /*! @function protocols
#     @abstract return protocols within this header
#  */
sub protocols
{
    return ();
}

# /*! @function categories
#     @abstract return categories within this header
#  */
sub categories
{
    return ();
}

# Add this as part of Java subclass support.
# /*! @function addToClasses
#     @abstract add to subclass list
#  */
# sub addToClasses
# {
# }

sub outputDir {
    my $self = shift;

    if (@_) {
        my $rootOutputDir = shift;
		if (-e $rootOutputDir) {
			if (! -d $rootOutputDir) {
			    die "Error: $rootOutputDir is not a directory. Exiting.\n\t$!\n";
			} elsif (! -w $rootOutputDir) {
			    die "Error: Output directory $rootOutputDir is not writable. Exiting.\n$!\n";
			}
		} else {
			unless (mkdir ("$rootOutputDir", 0777)) {
			    die ("Error: Can't create output folder $rootOutputDir.\n$!\n");
			}
	    }
        $self->{OUTPUTDIR} = $rootOutputDir;
	    $self->constantsDir("$rootOutputDir$pathSeparator"."Constants");
	    $self->datatypesDir("$rootOutputDir$pathSeparator"."DataTypes");
	    $self->structsDir("$rootOutputDir$pathSeparator"."Structs");
	    $self->functionsDir("$rootOutputDir$pathSeparator"."Functions");
	    $self->methodsDir("$rootOutputDir$pathSeparator"."Methods");
	    $self->varsDir("$rootOutputDir$pathSeparator"."Vars");
	    $self->pDefinesDir("$rootOutputDir$pathSeparator"."PDefines");
	    $self->enumsDir("$rootOutputDir$pathSeparator"."Enums");
	    $self->exportsDir("$rootOutputDir$pathSeparator"."Exports");
    }
    return $self->{OUTPUTDIR};
}

sub tocTitlePrefix {
    my $self = shift;

    if (@_) {
        $self->{TOCTITLEPREFIX} = shift;
    }
    return $self->{TOCTITLEPREFIX};
}

sub exportingForDB {
    my $self = shift;

    if (@_) {
        $self->{EXPORTINGFORDB} = shift;
    }
    return $self->{EXPORTINGFORDB};
}

sub exportsDir {
    my $self = shift;

    if (@_) {
        $self->{EXPORTSDIR} = shift;
    }
    return $self->{EXPORTSDIR};
}

sub constantsDir {
    my $self = shift;

    if (@_) {
        $self->{CONSTANTSDIR} = shift;
    }
    return $self->{CONSTANTSDIR};
}


sub datatypesDir {
    my $self = shift;

    if (@_) {
        $self->{DATATYPESDIR} = shift;
    }
    return $self->{DATATYPESDIR};
}

sub structsDir {
    my $self = shift;

    if (@_) {
        $self->{STRUCTSDIR} = shift;
    }
    return $self->{STRUCTSDIR};
}

sub varsDir {
    my $self = shift;

    if (@_) {
        $self->{VARSDIR} = shift;
    }
    return $self->{VARSDIR};
}

sub pDefinesDir {
    my $self = shift;

    if (@_) {
        $self->{PDEFINESDIR} = shift;
    }
    return $self->{PDEFINESDIR};
}

sub enumsDir {
    my $self = shift;

    if (@_) {
        $self->{ENUMSDIR} = shift;
    }
    return $self->{ENUMSDIR};
}


sub functionsDir {
    my $self = shift;

    if (@_) {
        $self->{FUNCTIONSDIR} = shift;
    }
    return $self->{FUNCTIONSDIR};
}

sub methodsDir {
    my $self = shift;

    if (@_) {
        $self->{METHODSDIR} = shift;
    }
    return $self->{METHODSDIR};
}

sub tocStringSub {
    my $self = shift;
    my $head = shift;
    my $groupref = shift;
    my $objref = shift;
    my $compositePageName = shift;
    my $baseref = shift;
    my $composite = shift;
    my $ignore_access = shift;
    my $tag = shift;

    my $localDebug = 0;
    my $class = ref($self) || $self;
    my @groups = @{$groupref};
    my @objs = @{$objref};

    my $tocString = "";
    my $jumpLabel = "";
    if ($tag && $tag ne "") {
	$jumpLabel = "#HeaderDoc_$tag";
    }

	    if ($composite) {
	        $tocString .= "<h4><a href=\"$compositePageName$jumpLabel\" target=\"doc\">$head</a></h4>\n";
	    } else {
	        $tocString .= "<h4><a href=\"$baseref$jumpLabel\" target=\"doc\">$head</a></h4>\n";
	    }

	    foreach my $group (@groups) {
	        my $done_one = 0;
		print "Sorting group $group\n" if ($localDebug);

		my @groupobjs = ();
		my @tempobjs = ();
		my @cdobjs = ();
		if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @objs;
		} else {
			@tempobjs = @objs;
		}
		foreach my $obj (@tempobjs) {
		    if ($obj->group() eq $group) {
			$done_one = 1;
			if (!$HeaderDoc::sort_entries || !$obj->constructor_or_destructor()) {
			    push(@groupobjs, $obj);
			} else {
			    push(@cdobjs, $obj);
			}
		    }
		}
		if (!$done_one) {
		    # empty group
		    next;
		}
		my $preface = "";
		if ($group eq "") {
			$preface = "&nbsp;&nbsp;";
		} else {
			# if ($done_one) { $tocString .= "&nbsp;<br>" }
			$tocString .= "<dl><dt>&nbsp;&nbsp;<font size=\"-1\"><i>$group:</i><br></font></dt><dd>";
		}

		my @Cs;
		my @publics;
		my @protecteds;
		my @privates;

              if ($HeaderDoc::sort_entries) {
                        @tempobjs = sort byAccessControl @groupobjs;
              } else {
                        @tempobjs = @groupobjs;
              }
	      foreach my $obj (@tempobjs) {
	        my $access = $obj->accessControl();

# print "ACCESS: $access\n";
	        
	        if ($access =~ /public/o || $ignore_access){
	            push (@publics, $obj);
	        } elsif ($access =~ /protected/o){
	            push (@protecteds, $obj);
	        } elsif ($access =~ /private/o){
	            push (@privates, $obj);
		} elsif ($access eq "") {
		    push (@Cs, $obj);
	        } else {
		    # assume public (e.g. C)
		    push (@publics, $obj);
		}
	      }
	      if (@cdobjs) {
		    $tocString .= "\n";
		    my @tempobjs = ();
		    if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @cdobjs;
		    } else {
			@tempobjs = @cdobjs;
		    }
		    foreach my $obj (@tempobjs) {
	        	my $name = $obj->name();
			my $urlname = $obj->apiuid(); # sanitize($name);
	        	if ($self->outputformat eq "hdxml") {
	        	    $tocString .= "XMLFIX<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
		        } elsif ($self->outputformat eq "html") {
			    if ($composite) {
	        		$tocString .= "<nobr>$preface<a href=\"$compositePageName#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    } else {
	        		$tocString .= "<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    }
			} else {
			}
		    }
	        }
	      if (@Cs) {
		    $tocString .= "\n";
		    my @tempobjs = ();
		    if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @Cs;
		    } else {
			@tempobjs = @Cs;
		    }
		    foreach my $obj (@tempobjs) {
	        	my $name = $obj->name();
			my $urlname = $obj->apiuid(); # sanitize($name);
	        	if ($self->outputformat eq "hdxml") {
	        	    $tocString .= "XMLFIX<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
		        } elsif ($self->outputformat eq "html") {
			    if ($composite) {
	        		$tocString .= "<nobr>$preface<a href=\"$compositePageName#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    } else {
	        		$tocString .= "<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    }
			} else {
			}
		    }
	        }
	      if (@publics) {
		if ($class eq "HeaderDoc::Header" || $ignore_access) {
		    $tocString .= "\n";
	        } elsif ($self->outputformat eq "hdxml") {
	            $tocString .= "XMLFIX<h5>Public</h5>\n";
	        } elsif ($self->outputformat eq "html") {
	            $tocString .= "<h5>Public</h5>\n";
		} else {
		}
		    my @tempobjs = ();
		    if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @publics;
		    } else {
			@tempobjs = @publics;
		    }
		    foreach my $obj (@tempobjs) {
	        	my $name = $obj->name();
			my $urlname = $obj->apiuid(); # sanitize($name);
	        	if ($self->outputformat eq "hdxml") {
	        	    $tocString .= "XMLFIX<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
		        } elsif ($self->outputformat eq "html") {
			    if ($composite) {
	        		$tocString .= "<nobr>$preface<a href=\"$compositePageName#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    } else {
	        		$tocString .= "<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    }
			} else {
			}
	        }
	      }
	      if (@protecteds) {
		if ($class eq "HeaderDoc::Header" || $ignore_access) {
		    $tocString .= "\n";
	        } elsif ($self->outputformat eq "hdxml") {
	            $tocString .= "XMLFIX<h5>Protected</h5>\n";
	        } elsif ($self->outputformat eq "html") {
	            $tocString .= "<h5>Protected</h5>\n";
		} else {
		}
		    my @tempobjs = ();
		    if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @protecteds;
		    } else {
			@tempobjs = @protecteds;
		    }
		    foreach my $obj (@tempobjs) {
	        	my $name = $obj->name();
			my $urlname = $obj->apiuid(); # sanitize($name);
		        if ($self->outputformat eq "hdxml") {
	        	    $tocString .= "XMLFIX<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
		        } elsif ($self->outputformat eq "html") {
			    if ($composite) {
	        		$tocString .= "<nobr>$preface<a href=\"$compositePageName#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    } else {
	        		$tocString .= "<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    }
			} else {
			}
	        }
	      }
	      if (@privates) {
		if ($class eq "HeaderDoc::Header" || $ignore_access) {
		    $tocString .= "\n";
	        } elsif ($self->outputformat eq "hdxml") {
	            $tocString .= "XMLFIX<h5>Private</h5>\n";
	        } elsif ($self->outputformat eq "html") {
	            $tocString .= "<h5>Private</h5>\n";
		} else {
		}
		    my @tempobjs = ();
		    if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @privates;
		    } else {
			@tempobjs = @privates;
		    }
		    foreach my $obj (@tempobjs) {
	        	my $name = $obj->name();
			my $urlname = $obj->apiuid(); # sanitize($name);
	        	if ($self->outputformat eq "hdxml") {
	        	    $tocString .= "XMLFIX<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
		        } elsif ($self->outputformat eq "html") {
			    if ($composite) {
	        		$tocString .= "<nobr>$preface<a href=\"$compositePageName#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    } else {
	        		$tocString .= "<nobr>$preface<a href=\"$baseref#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    }
			} else {
			}
	        }
	      }
	      if (!($group eq "")) {
		$tocString .= "</dd></dl><p>\n";
	      }
	 }

    return $tocString;
}

sub inarray
{
    my $name = shift;
    my $arrayref = shift;

    my @array = @{$arrayref};

    foreach my $arrname (@array) {
	if ($name eq $arrname) { return 1; }
    }

    return 0;
}

sub tocString {
    my $self = shift;
    my $contentFrameName = $self->filename();
    my @classes = $self->classes();     
    my @protocols = $self->protocols();
    my @categories = $self->categories();
    my $class = ref($self) || $self;
    my $xml = 0;
    if ($self->outputformat() eq "hdxml") { $xml = 1; }

    $contentFrameName =~ s/(.*)\.h/$1/o; 
    $contentFrameName = &safeName(filename => $contentFrameName);  
    $contentFrameName = $contentFrameName . ".html";

    my $composite = $HeaderDoc::ClassAsComposite;

    my $compositePageName = HeaderDoc::APIOwner->compositePageName(); 
    my $defaultFrameName = HeaderDoc::APIOwner->defaultFrameName(); 

    if ($xml && $class ne "HeaderDoc::Header") { $compositePageName = $self->filename(); }
	# @@@ WRONG PRINTABLE PAGE
    if ($xml) {
	$compositePageName =~ s/\.(h|i)$//o;
	$compositePageName .= ".xml";
    }
    
    my @funcs = $self->functions();
    my @methods = $self->methods();
    my @constants = $self->constants();
    my @typedefs = $self->typedefs();
    my @structs = $self->structs();
    my @enums = $self->enums();
    my @pDefines = $self->pDefines();
    my @globals = $self->vars();
    my $tocString = "";

    if ($composite)  {
	$tocString .= "<h4><br><nobr><a href=\"$compositePageName\" target=\"doc\">Introduction</a></nobr></h4>\n";
    } else {
	$tocString .= "<h4><br><nobr><a href=\"$contentFrameName\" target=\"doc\">Introduction</a></nobr></h4>\n";
    }

    my @groups = ("");
    my $localDebug = 0;

    my @objs = ( @funcs, @methods, @constants, @typedefs, @structs, @enums,
	@pDefines, @globals );
    if ($HeaderDoc::sort_entries) { @objs = sort objGroup @objs; }
    foreach my $obj (@objs) {
	# warn "obj is $obj\n";
	my $group = $obj->group();
	if (!inarray($group, \@groups)) {
		push (@groups, $group);
		if ($localDebug) {
		    print "Added $group\n";
		    print "List is:";
		    foreach my $printgroup (@groups) {
			print " $printgroup";
		    }
		    print "\n";
		}
	}
    }

    # output list of functions as TOC
    if (@funcs) {
	    my $funchead = "Functions";
	    if ($class eq "HeaderDoc::CPPClass") {
		$funchead = "Member Functions";
	    }
	    my $baseref = "Functions/Functions.html";
	    $tocString .= $self->tocStringSub($funchead, \@groups, \@funcs,
		$compositePageName, $baseref, $composite, 0, "functions");
    }
    if (@methods) {
	    # $tocString .= "<h4>Methods</h4>\n";
	    $tocString .= "<h4><a href=\"$compositePageName#HeaderDoc_methods\" target=\"doc\">Methods</a></h4>\n";

	    foreach my $group (@groups) {
	        my $done_one = 0;
		print "Sorting group $group\n" if ($localDebug);

		my @groupmeths = ();
		my @tempobjs = ();
		if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @methods;
		} else {
			@tempobjs = @methods;
		}
		foreach my $obj (@tempobjs) {
		    if ($obj->group() eq $group) {
			$done_one = 1;
			push(@groupmeths, $obj);
		    }
		}
		if (!$done_one) {
		    # empty group
		    next;
		}
		if (!($group eq "")) {
			# if ($done_one) { $tocString .= "&nbsp;<br>" }
			$tocString .= "<dl><dt>&nbsp;&nbsp;<font size=\"-1\"><i>$group:</i><br></font></dt><dd>";
		}

		my @classMethods;
		my @instanceMethods;

	      foreach my $obj (sort byMethodType @groupmeths) {
	        my $type = $obj->isInstanceMethod();
	        
	        if ($type =~ /NO/o){
	            push (@classMethods, $obj);
	        } elsif ($type =~ /YES/o){
	            push (@instanceMethods, $obj);
	        } else {
		    # assume instanceMethod
		    push (@instanceMethods, $obj);
		}
	      }
	      if (@classMethods) {
		if ($class eq "HeaderDoc::Header") {
		    $tocString .= "\n";
	        } elsif ($self->outputformat eq "hdxml") {
	            $tocString .= "XMLFIX<h5>Class Methods</h5>\n";
	        } elsif ($self->outputformat eq "html") {
	            $tocString .= "<h5>Class Methods</h5>\n";
		} else {
		}
		    my @tempobjs = ();
		    if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @classMethods;
		    } else {
			@tempobjs = @classMethods;
		    }
		    foreach my $obj (@tempobjs) {
	        	my $name = $obj->name();
			my $urlname = $obj->apiuid();
	        	if ($self->outputformat eq "hdxml") {
	        	    $tocString .= "XMLFIX<nobr>&nbsp;&nbsp;<font size=\"-1\">+</font><a href=\"Methods/Methods.html#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
		        } elsif ($self->outputformat eq "html") {
			    if ($composite) {
	        		$tocString .= "<nobr>&nbsp;&nbsp;<font size=\"-1\">+</font><a href=\"$compositePageName#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    } else {
	        		$tocString .= "<nobr>&nbsp;&nbsp;<font size=\"-1\">+</font><a href=\"Methods/Methods.html#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    }
			} else {
			}
	        }
	      }
	      if (@instanceMethods) {
		if ($class eq "HeaderDoc::Header") {
		    $tocString .= "\n";
	        } elsif ($self->outputformat eq "hdxml") {
	            $tocString .= "XMLFIX<h5>Instance Methods</h5>\n";
	        } elsif ($self->outputformat eq "html") {
	            $tocString .= "<h5>Instance Methods</h5>\n";
		} else {
		}
		    my @tempobjs = ();
		    if ($HeaderDoc::sort_entries) {
			@tempobjs = sort objName @instanceMethods;
		    } else {
			@tempobjs = @instanceMethods;
		    }
		    foreach my $obj (@tempobjs) {
	        	my $name = $obj->name();
			my $urlname = $obj->apiuid();
		        if ($self->outputformat eq "hdxml") {
	        	    $tocString .= "XMLFIX<nobr>&nbsp;&nbsp;<font size=\"-1\">-</font><a href=\"Methods/Methods.html#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
		        } elsif ($self->outputformat eq "html") {
			    if ($composite) {
	        		$tocString .= "<nobr>&nbsp;&nbsp;<font size=\"-1\">-</font><a href=\"$compositePageName#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    } else {
	        		$tocString .= "<nobr>&nbsp;&nbsp;<font size=\"-1\">-</font><a href=\"Methods/Methods.html#$urlname\" target=\"doc\">$name</a></nobr><br>\n";
			    }
			} else {
			}
	        }
	      }
	      if (!($group eq "")) {
		$tocString .= "</dd></dl><p>\n";
	      }
	}
    }
    if (@typedefs) {
	    my $head = "Defined Types\n";
	    my $baseref = "DataTypes/DataTypes.html";
	    $tocString .= $self->tocStringSub($head, \@groups, \@typedefs,
		$compositePageName, $baseref, $composite, 1, "");
    }
    if (@structs) {
	    my $head = "Structs and Unions\n";
	    my $baseref = "Structs/Structs.html";
	    $tocString .= $self->tocStringSub($head, \@groups, \@structs,
		$compositePageName, $baseref, $composite, 1, "");
    }
    if (@constants) {
	    my $head = "Constants\n";
	    my $baseref = "Constants/Constants.html";
	    $tocString .= $self->tocStringSub($head, \@groups, \@constants,
		$compositePageName, $baseref, $composite, 1, "");
	}
    if (@enums) {
	    my $head = "Enumerations\n";
	    my $baseref = "Enums/Enums.html";
	    $tocString .= $self->tocStringSub($head, \@groups, \@enums,
		$compositePageName, $baseref, $composite, 1, "");
	}
    if (@pDefines) {
	    my $head = "#defines\n";
	    my $baseref = "PDefines/PDefines.html";
	    $tocString .= $self->tocStringSub($head, \@groups, \@pDefines,
		$compositePageName, $baseref, $composite, 1, "");
	}
    if (@classes) {
	my @realclasses = ();
	my @comints = ();
	foreach my $obj (@classes) {
	    if ($obj->isCOMInterface()) {
		push(@comints, $obj);
	    } else {
		push(@realclasses, $obj);
	    }
	}
	if (@realclasses) {
	    @classes = @realclasses;
	    $tocString .= "<h4>Classes</h4>\n";
	    my @tempobjs = ();
	    if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @classes;
	    } else {
		@tempobjs = @classes;
	    }
	    foreach my $obj (@tempobjs) {
	        my $name = $obj->name();
	        my $safeName = $name;
	        # for now, always shorten long names since some files may be moved to a Mac for browsing
            if (1 || $isMacOS) {$safeName = &safeName(filename => $name);};
	        $tocString .= "<nobr>&nbsp;&nbsp;<a href=\"Classes/$safeName/$defaultFrameName\" target=\"_top\">$name</a></nobr><br>\n";
	    }
	}
	if (@comints) {
	    @classes = @comints;
	    $tocString .= "<h4>COM Interfaces</h4>\n";
	    my @tempobjs = ();
	    if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @classes;
	    } else {
		@tempobjs = @classes;
	    }
	    foreach my $obj (@tempobjs) {
	        my $name = $obj->name();
	        my $safeName = $name;
	        # for now, always shorten long names since some files may be moved to a Mac for browsing
            if (1 || $isMacOS) {$safeName = &safeName(filename => $name);};
	        $tocString .= "<nobr>&nbsp;&nbsp;<a href=\"Classes/$safeName/$defaultFrameName\" target=\"_top\">$name</a></nobr><br>\n";
	    }
	}
    }
    if (@protocols) {
	    $tocString .= "<h4>Protocols</h4>\n";
	    my @tempobjs = ();
	    if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @protocols;
	    } else {
		@tempobjs = @protocols;
	    }
	    foreach my $obj (@tempobjs) {
	        my $name = $obj->name();
	        my $safeName = $name;
	        # for now, always shorten long names since some files may be moved to a Mac for browsing
            if (1 || $isMacOS) {$safeName = &safeName(filename => $name);};
	        $tocString .= "<nobr>&nbsp;&nbsp;<a href=\"Protocols/$safeName/$defaultFrameName\" target=\"_top\">$name</a></nobr><br>\n";
	    }
    }
    if (@categories) {
	    $tocString .= "<h4>Categories</h4>\n";
	    my @tempobjs = ();
	    if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @categories;
	    } else {
		@tempobjs = @categories;
	    }
	    foreach my $obj (@tempobjs) {
	        my $name = $obj->name();
	        my $safeName = $name;
	        # for now, always shorten long names since some files may be moved to a Mac for browsing
            if (1 || $isMacOS) {$safeName = &safeName(filename => $name);};
	        $tocString .= "<nobr>&nbsp;&nbsp;<a href=\"Categories/$safeName/$defaultFrameName\" target=\"_top\">$name</a></nobr><br>\n";
	    }
    }
    if (@globals) {
	    my $globalname = "Globals";
	    if ($class ne "HeaderDoc::Header") {
		$globalname = "Member Data";
	    }
	    my $baseref = "Vars/Vars.html";
	    $tocString .= $self->tocStringSub($globalname, \@groups, \@globals,
		$compositePageName, $baseref, $composite, 0, "");
    }
    if ($class ne "HeaderDoc::Header") {
	$tocString .= "<br><h4>Other Reference</h4><hr>\n";
	$tocString .= "<nobr>&nbsp;&nbsp;<a href=\"../../$defaultFrameName\" target=\"_top\">Header</a></nobr><br>\n";
    }
    if (!$composite) {
	$tocString .= "<br><hr><a href=\"$compositePageName\" target=\"_blank\">[Printable HTML Page]</a>\n";
    }
    my $availability = $self->availability();
    my $updated = $self->updated();
    if (length($availability)) {
	$tocString .= "<p><i>Availability: $availability</i><p>";
    }
    if (length($updated)) {
	$tocString .= "<p><i>Updated: $updated</i><p>";
    }
    return $tocString;
}

sub enums {
    my $self = shift;

    if (@_) {
        @{ $self->{ENUMS} } = @_;
    }
    ($self->{ENUMS}) ? return @{ $self->{ENUMS} } : return ();
}

sub addToEnums {
    my $self = shift;

    if (@_) {
        foreach my $item (@_) {
            push (@{ $self->{ENUMS} }, $item);
        }
    }
    return @{ $self->{ENUMS} };
}

sub pDefines {
    my $self = shift;

    if (@_) {
        @{ $self->{PDEFINES} } = @_;
    }
    ($self->{PDEFINES}) ? return @{ $self->{PDEFINES} } : return ();
}

sub addToPDefines {
    my $self = shift;

    if (@_) {
        foreach my $item (@_) {
            push (@{ $self->{PDEFINES} }, $item);
        }
    }
    return @{ $self->{PDEFINES} };
}

sub constants {
    my $self = shift;

    if (@_) {
        @{ $self->{CONSTANTS} } = @_;
    }
    ($self->{CONSTANTS}) ? return @{ $self->{CONSTANTS} } : return ();
}

sub addToConstants {
    my $self = shift;
    
    if (@_) {
        foreach my $item (@_) {
            push (@{ $self->{CONSTANTS} }, $item);
        }
    }
    return @{ $self->{CONSTANTS} };
}


sub functions {
    my $self = shift;

    if (@_) {
        @{ $self->{FUNCTIONS} } = @_;
    }
    ($self->{FUNCTIONS}) ? return @{ $self->{FUNCTIONS} } : return ();
}

sub addToFunctions {
    my $self = shift;
    my $localDebug = 0;

    if (@_) {
        foreach my $item (@_) {
	    foreach my $compare (@{ $self->{FUNCTIONS} }) {
		my $name1 = $item->name();
		my $name2 = $compare->name();
		if ($item->name() eq $compare->name()) {
			my $oldconflict = ($item->conflict() && compare->conflict());
			$item->conflict(1);
			$compare->conflict(1);
			$HeaderDoc::ignore_apiuid_errors = 1;
			my $junk = $item->apirefSetup(1);
			$junk = $compare->apirefSetup(1);
			$HeaderDoc::ignore_apiuid_errors = 0;
			print "$name1 = $name2\n" if ($localDebug);

			if (!$oldconflict) {
			  my $apio = $self; # ->apiOwner();
			  my $apioclass = ref($apio) || $apio;
			  if ($apioclass ne "HeaderDoc::CPPClass") {
			    if ($apioclass !~ /HeaderDoc::ObjC/o) {
				warn "Conflicting declarations for function/method ($name1)\n    outside a class.  This is probably not what you want.\n";
			    }
			  }
			}
		}
	    }
            push (@{ $self->{FUNCTIONS} }, $item);
        }
    }
    return @{ $self->{FUNCTIONS} };
}

sub methods {
    my $self = shift;

    if (@_) {
        @{ $self->{METHODS} } = @_;
    }
    ($self->{METHODS}) ? return @{ $self->{METHODS} } : return ();
}

sub addToMethods {
    my $self = shift;

    if (@_) {
        foreach my $item (@_) {
	    foreach my $compare (@{ $self->{METHODS} }) {
		if ($item->name() eq $compare->name()) {
			$item->conflict(1);
			$compare->conflict(1);
		}
	    }
            push (@{ $self->{METHODS} }, $item);
        }
    }
    return @{ $self->{METHODS} };
}

sub typedefs {
    my $self = shift;

    if (@_) {
        @{ $self->{TYPEDEFS} } = @_;
    }
    ($self->{TYPEDEFS}) ? return @{ $self->{TYPEDEFS} } : return ();
}

sub addToTypedefs {
    my $self = shift;

    if (@_) {
        foreach my $item (@_) {
            push (@{ $self->{TYPEDEFS} }, $item);
	# print "added ".$item->name()." to $self.\n";
        }
    }
    return @{ $self->{TYPEDEFS} };
}

sub structs {
    my $self = shift;

    if (@_) {
        @{ $self->{STRUCTS} } = @_;
    }
    ($self->{STRUCTS}) ? return @{ $self->{STRUCTS} } : return ();
}

sub addToStructs {
    my $self = shift;

    if (@_) {
        foreach my $item (@_) {
            push (@{ $self->{STRUCTS} }, $item);
        }
    }
    return @{ $self->{STRUCTS} };
}

sub vars {
    my $self = shift;

    if (@_) {
        @{ $self->{VARS} } = @_;
    }
    ($self->{VARS}) ? return @{ $self->{VARS} } : return ();
}

sub addToVars {
    my $self = shift;

    if (@_) {
        foreach my $item (@_) {
            push (@{ $self->{VARS} }, $item);
        }
    }
    return @{ $self->{VARS} };
}

sub fields {
    my $self = shift;
    if (@_) { 
        @{ $self->{FIELDS} } = @_;
    }
    ($self->{FIELDS}) ? return @{ $self->{FIELDS} } : return ();
}

sub addToFields {
    my $self = shift;
    if (@_) { 
        push (@{$self->{FIELDS}}, @_);
    }
    return @{ $self->{FIELDS} };
}

sub namespace {
    my $self = shift;
    my $localDebug = 0;

    if (@_) { 
        $self->{NAMESPACE} = shift;
    }
    print "namespace ".$self->{NAMESPACE}."\n" if ($localDebug);
    return $self->{NAMESPACE};
}

sub availability {
    my $self = shift;

    if (@_) {
        $self->{AVAILABILITY} = shift;
    }
    return $self->{AVAILABILITY};
}

sub updated {
    my $self = shift;
    my $localDebug = 0;
    
    if (@_) {
	my $updated = shift;
        # $self->{UPDATED} = shift;
	my $month; my $day; my $year;

	$month = $day = $year = $updated;

	print "updated is $updated\n" if ($localDebug);
	if (!($updated =~ /\d\d\d\d-\d\d-\d\d/o )) {
	    if (!($updated =~ /\d\d-\d\d-\d\d\d\d/o )) {
		if (!($updated =~ /\d\d-\d\d-\d\d/o )) {
		    # my $filename = $HeaderDoc::headerObject->filename();
		    my $filename = $self->filename();
		    my $linenum = $self->linenum();
		    print "$filename:$linenum:Bogus date format: $updated.\n";
		    print "Valid formats are MM-DD-YYYY, MM-DD-YY, and YYYY-MM-DD\n";
		    return $self->{UPDATED};
		} else {
		    $month =~ s/(\d\d)-\d\d-\d\d/$1/smog;
		    $day =~ s/\d\d-(\d\d)-\d\d/$1/smog;
		    $year =~ s/\d\d-\d\d-(\d\d)/$1/smog;

		    my $century;
		    $century = `date +%C`;
		    $century *= 100;
		    $year += $century;
		    # $year += 2000;
		    print "YEAR: $year" if ($localDebug);
		}
	    } else {
		print "03-25-2003 case.\n" if ($localDebug);
		    $month =~ s/(\d\d)-\d\d-\d\d\d\d/$1/smog;
		    $day =~ s/\d\d-(\d\d)-\d\d\d\d/$1/smog;
		    $year =~ s/\d\d-\d\d-(\d\d\d\d)/$1/smog;
	    }
	} else {
		    $year =~ s/(\d\d\d\d)-\d\d-\d\d/$1/smog;
		    $month =~ s/\d\d\d\d-(\d\d)-\d\d/$1/smog;
		    $day =~ s/\d\d\d\d-\d\d-(\d\d)/$1/smog;
	}
	$month =~ s/\n*//smog;
	$day =~ s/\n*//smog;
	$year =~ s/\n*//smog;
	$month =~ s/\s*//smog;
	$day =~ s/\s*//smog;
	$year =~ s/\s*//smog;

	# Check the validity of the modification date

	my $invalid = 0;
	my $mdays = 28;
	if ($month == 2) {
		if ($year % 4) {
			$mdays = 28;
		} elsif ($year % 100) {
			$mdays = 29;
		} elsif ($year % 400) {
			$mdays = 28;
		} else {
			$mdays = 29;
		}
	} else {
		my $bitcheck = (($month & 1) ^ (($month & 8) >> 3));
		if ($bitcheck) {
			$mdays = 31;
		} else {
			$mdays = 30;
		}
	}

	if ($month > 12 || $month < 1) { $invalid = 1; }
	if ($day > $mdays || $day < 1) { $invalid = 1; }
	if ($year < 1970) { $invalid = 1; }

	if ($invalid) {
		# my $filename = $HeaderDoc::headerObject->filename();
		my $filename = $self->filename();
		my $linenum = $self->linenum();
		print "$filename:$linenum:Invalid date (year = $year, month = $month, day = $day).\n";
		print "$filename:$linenum:Valid formats are MM-DD-YYYY, MM-DD-YY, and YYYY-MM-DD\n";
		return $self->{UPDATED};
	} else {
		$self->{UPDATED} =HeaderDoc::HeaderElement::strdate($month, $day, $year);
	}
    }
    return $self->{UPDATED};
}


##################################################################

sub createMetaFile {
    my $self = shift;
    my $outDir = $self->outputDir();
    my $outputFile = "$outDir$pathSeparator"."book.xml";
    my $text = $self->metaFileText();

    open(OUTFILE, ">$outputFile") || die "Can't write $outputFile. \n$!\n";
    if ($isMacOS) {MacPerl::SetFileInfo('MSIE', 'TEXT', "$outputFile");};
    print OUTFILE "$text";
    close OUTFILE;
}

sub createFramesetFile {
    my $self = shift;
    my $docNavigatorComment = $self->docNavigatorComment();
    my $class = ref($self);
    my $defaultFrameName = $class->defaultFrameName();

    my $filename = $self->filename();
    my $name = $self->name();
    my $title = $filename;
    if (!length($name)) {
	$name = "$filename";
    } else {
	$title = "$name ($filename)";
    }

    my $outDir = $self->outputDir();
    
    my $outputFile = "$outDir$pathSeparator$defaultFrameName";    
    my $rootFileName = $self->filename();
    $rootFileName =~ s/(.*)\.h/$1/o; 
    $rootFileName = &safeName(filename => $rootFileName);
    my $compositePageName = $self->compositePageName();

    my $composite = $HeaderDoc::ClassAsComposite;
    if ($class eq "HeaderDoc::Header") {
	$composite = 0;
    }

    open(OUTFILE, ">$outputFile") || die "Can't write $outputFile. \n$!\n";
    if ($isMacOS) {MacPerl::SetFileInfo('MSIE', 'TEXT', "$outputFile");};
	print OUTFILE "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Frameset//EN\"\n    \"http://www.w3.org/TR/1999/REC-html401-19991224/frameset.dtd\">\n";
    print OUTFILE "<html><head>\n    <title>Documentation for $title</title>\n	<meta name=\"generator\" content=\"HeaderDoc\">\n</head>\n";
    print OUTFILE "<frameset cols=\"190,100%\">\n";
    print OUTFILE "<frame src=\"toc.html\" name=\"toc\">\n";
    if ($composite) {
	print OUTFILE "<frame src=\"$compositePageName\" name=\"doc\">\n";
    } else {
	print OUTFILE "<frame src=\"$rootFileName.html\" name=\"doc\">\n";
    }
    print OUTFILE "</frameset></html>\n";
    print OUTFILE "$docNavigatorComment\n";
    close OUTFILE;
}

# Overridden by subclasses to return HTML comment that identifies the 
# index file (Header vs. Class, name, etc.). gatherHeaderDoc uses this
# information to create a master TOC of the generated doc.
#
sub docNavigatorComment {
    return "";
}

sub createTOCFile {
    my $self = shift;
    my $rootDir = $self->outputDir();
    my $tocTitlePrefix = $self->tocTitlePrefix();
    my $outputFileName = "toc.html";    
    my $outputFile = "$rootDir$pathSeparator$outputFileName";    
    my $fileString = $self->tocString();    

    my $filename = $self->filename();
    my $name = $self->name();
    my $title = $filename;
    if (!length($name)) {
	$name = "$filename";
    } elsif ($name eq $filename) {
	$name = "$filename";
    } else {
	$title = "$name ($filename)";
    }

	open(OUTFILE, ">$outputFile") || die "Can't write $outputFile.\n$!\n";
    if ($isMacOS) {MacPerl::SetFileInfo('MSIE', 'TEXT', "$outputFile");};
	print OUTFILE "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\"\n    \"http://www.w3.org/TR/1998/REC-html40-19980424/loose.dtd\">\n";
	print OUTFILE "<html>";

	print OUTFILE $self->styleSheet(1);

	print OUTFILE "<head>\n    <title>Documentation for $title</title>\n	<meta name=\"generator\" content=\"HeaderDoc\">\n</head>\n";
	print OUTFILE "<body bgcolor=\"#edf2f6\" link=\"#000099\" vlink=\"#660066\"\n";
	print OUTFILE "leftmargin=\"0\" topmargin=\"0\" marginwidth=\"0\"\n"; 
	print OUTFILE "marginheight=\"0\">\n";

	print OUTFILE "<table width=\"100%\" cellpadding=0 cellspacing=0 border=0>";
	print OUTFILE "<tr height=51 bgcolor=\"#466C9B\"><td>&nbsp;</td></tr>";
	print OUTFILE "</table><br>";

	print OUTFILE "<table border=\"0\" cellpadding=\"0\" cellspacing=\"2\" width=\"148\">\n";
	print OUTFILE "<tr><td width=\"15\">&nbsp;</td><td colspan=\"2\"><font size=\"5\" color=\"#330066\"><b>$tocTitlePrefix</b></font></td></tr>\n";
	print OUTFILE "<tr><td width=\"15\">&nbsp;</td><td width=\"15\">&nbsp;</td><td><b><font size=\"+1\">$name</font></b></td></tr>\n";
	print OUTFILE "<tr><td></td><td colspan=\"2\">\n";
	print OUTFILE $fileString;
	print OUTFILE "</td></tr>\n";
	print OUTFILE "</table><p>&nbsp;<p>\n";
	print OUTFILE "</body></html>\n";
	close OUTFILE;
}

sub calcDepth
{
    my $filename = shift;
    my $base = $HeaderDoc::headerObject->outputDir();
    my $origfilename = $filename;
    my $localDebug = 0;

    $filename =~ s/^\Q$base//;

    my @parts = split(/\//, $filename);

    # Modify global depth.
    $depth = (scalar @parts)-1;

    warn("Filename: $origfilename; Depth: $depth\n") if ($localDebug);

    return $depth;
}

sub createContentFile {

    my $self = shift;
    my $class = ref($self);
    my $copyrightOwner = $class->copyrightOwner();
    my $filename = $self->filename();
    my $name = $self->name();
    my $title = $filename;
    if (!length($name)) {
	$name = "$filename";
    } else {
	$title = "$name ($filename)";
    }

    my $rootFileName = $self->filename();

    if ($class eq "HeaderDoc::Header") {
	my $headercopyright = $self->headerCopyrightOwner();
	if (!($headercopyright eq "")) {
	    $copyrightOwner = $headercopyright;
	}
    }

    my $HTMLmeta = "";
    if ($class eq "HeaderDoc::Header") {
	$HTMLmeta = $self->HTMLmeta();
    }
    if ($self->outputformat() eq "html") {
	$HTMLmeta .= $self->styleSheet(0);
    }

    my $fileString = "";

    $rootFileName =~ s/(.*)\.h/$1/o; 
    # for now, always shorten long names since some files may be moved to a Mac for browsing
    if (1 || $isMacOS) {$rootFileName = &safeName(filename => $rootFileName);};
    my $outputFileName = "$rootFileName.html";    
    my $rootDir = $self->outputDir();
    my $outputFile = "$rootDir$pathSeparator$outputFileName";    
    calcDepth($outputFile);

   	open (OUTFILE, ">$outputFile") || die "Can't write header-wide content page $outputFile. \n$!\n";
    if ($isMacOS) {MacPerl::SetFileInfo('MSIE', 'TEXT', "$outputFile");};


    my $headerDiscussion = $self->discussion();    
    my $headerAbstract = $self->abstract();  
    if ((!length($headerDiscussion)) && (!length($headerAbstract))) {
	my $linenum = $self->linenum();
        warn "$filename:$linenum: No header or class discussion/abstract found. Creating dummy file for default content page.\n";
	$headerAbstract .= "Use the links in the table of contents to the left to access documentation.<br>\n";    
    }
	$fileString .= "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\"\n    \"http://www.w3.org/TR/1998/REC-html40-19980424/loose.dtd\">\n";
	$fileString .= "<html><HEAD>\n    <title>API Documentation</title>\n	$HTMLmeta <meta name=\"generator\" content=\"HeaderDoc\">\n</HEAD>\n<BODY bgcolor=\"#ffffff\">\n";
	if ($HeaderDoc::insert_header) {
		$fileString .= "<!-- start of header -->\n";
		$fileString .= $self->htmlHeader()."\n";
		$fileString .= "<!-- end of header -->\n";
	}
	$fileString .= "<H1>$name</H1><hr>\n";
	if (length($headerAbstract)) {
	    # $fileString .= "<b>Abstract: </b>$headerAbstract<hr><br>\n";    
	    if ($self->can("isFramework") && $self->isFramework()) {
		$fileString .= "<!-- headerDoc=frameworkabstract;name=start -->\n";
	    }
	    $fileString .= "$headerAbstract\n";    
	    if ($self->can("isFramework") && $self->isFramework()) {
		$fileString .= "<!-- headerDoc=frameworkabstract;name=end -->\n";
	    }
	    $fileString .= "<br>\n";    
	}

	my $namespace = $self->namespace();
	my $availability = $self->availability();
	my $updated = $self->updated();
 	if (length($updated) || length($namespace)) {
	    $fileString .= "<p></p>\n";
	}

	if (length($namespace)) {
	    $fileString .= "<b>Namespace:</b> $namespace<br>\n";
	}
	if (length($availability)) {      
	    $fileString .= "<b>Availability:</b> $availability<br>\n";
	}
	if (length($updated)) {      
	    $fileString .= "<b>Updated:</b> $updated<br>\n";
	}
	my $includeList = "";
	if ($class eq "HeaderDoc::Header") {
	    my $includeref = $HeaderDoc::perHeaderIncludes{$filename};
	    if ($includeref) {
		my @includes = @{$includeref};

		my $first = 1;
		foreach my $include (@includes) {
			my $localDebug = 0;
			print "Included file: $include\n" if ($localDebug);

			if (!$first) { $includeList .= ",\n"; }
			my $xmlinc = $self->textToXML($include);

			my $includeguts = $include;
			$includeguts =~ s/[<\"](.*)[>\"]/$1/so;

			my $includefile = basename($includeguts);

			my $ref = $self->genRefSub("doc", "header", $includefile, "");

			$includeList .= "<!-- a logicalPath=\"$ref\" -->$xmlinc<!-- /a -->";
			$first = 0;
		}

		if (length($includeList)) {
			$fileString .= "<b>Includes:</b> ";
			$fileString .= $includeList;
			$fileString .= "<br>\n";
		}
	    }
	}
	my $short_attributes = $self->getAttributes(0);
	my $long_attributes = $self->getAttributes(1);
	my $list_attributes = $self->getAttributeLists(0);
	if (length($short_attributes)) {
	        $fileString .= "$short_attributes";
	}
	if (length($list_attributes)) {
	        $fileString .= "$list_attributes";
	}
 	if (length($updated) || length($availability) || length($namespace) || length($headerAbstract) || length($short_attributes) || length($list_attributes) || length($includeList)) {
	    $fileString .= "<p></p>\n";
	    $fileString .= "<hr><br>\n";
	}

	if ($self->can("isFramework") && $self->isFramework()) {
		$fileString .= "<!-- headerDoc=frameworkdiscussion;name=start -->\n";
	}
	$fileString .= "$headerDiscussion\n";
	if ($self->can("isFramework") && $self->isFramework()) {
		$fileString .= "<!-- headerDoc=frameworkdiscussion;name=end -->\n";
	}
	$fileString .= "<br><br>\n";

	if (length($long_attributes)) {
	        $fileString .= "$long_attributes";
	}

	my @fields = $self->fields();
	if (@fields) {
		$fileString .= "<hr><h5><font face=\"Lucida Grande,Helvetica,Arial\">Template Parameter Descriptions</font></h5>";
		# print "\nGOT fields.\n";
		# $fileString .= "<table width=\"90%\" border=1>";
		# $fileString .= "<thead><tr><th>Name</th><th>Description</th></tr></thead>";
		$fileString .= "<dl>";
		for my $field (@fields) {
			my $name = $field->name();
			my $desc = $field->discussion();
			# print "field $name $desc\n";
			# $fileString .= "<tr><td><tt>$name</tt></td><td>$desc</td></tr>";
			$fileString .= "<dt><tt>$name</tt></dt><dd>$desc</dd>";
		}
		# $fileString .= "</table>\n";
		$fileString .= "</dl>\n";
	}
	$fileString .= "<hr><br><center>";
	$fileString .= "&#169; $copyrightOwner " if (length($copyrightOwner));
	my $filedate = $self->updated();
	if (length($filedate)) {
	    $fileString .= "(Last Updated $filedate)\n";
	} else {
	    $fileString .= "(Last Updated $dateStamp)\n";
	}
	$fileString .= "<br>";
	$fileString .= "<font size=\"-1\">HTML documentation generated by <a href=\"http://www.opensource.apple.com/projects\" target=\"_blank\">HeaderDoc</a></font>\n";    
	$fileString .= "</center>\n";
	$fileString .= "</BODY>\n</HTML>\n";

	print OUTFILE $self->fixup_inheritDoc(toplevel_html_fixup_links($self, $fileString));

	close OUTFILE;
}

sub writeHeaderElements {
    my $self = shift;
    my $rootOutputDir = $self->outputDir();
    my $functionsDir = $self->functionsDir();
    my $methodsDir = $self->methodsDir();
    my $dataTypesDir = $self->datatypesDir();
    my $structsDir = $self->structsDir();
    my $constantsDir = $self->constantsDir();
    my $varsDir = $self->varsDir();
    my $enumsDir = $self->enumsDir();
    my $pDefinesDir = $self->pDefinesDir();

	if (! -e $rootOutputDir) {
		unless (mkdir ("$rootOutputDir", 0777)) {die ("Can't create output folder $rootOutputDir. \n$!");};
    }

    # pre-process everything to make sure we don't have any unregistered
    # api refs.
    my $junk = "";
    $HeaderDoc::ignore_apiuid_errors = 1;
    my @functions = $self->functions();
    my @methods = $self->methods();
    my @constants = $self->constants();
    my @typedefs = $self->typedefs();
    my @structs = $self->structs();
    my @vars = $self->vars();
    my @enums = $self->enums();
    my @pDefines = $self->pDefines();
    if (@functions) { foreach my $obj (@functions) { $junk = $obj->apirefSetup();}}
    if (@methods) { foreach my $obj (@methods) { $junk = $obj->apirefSetup();}}
    if (@constants) { foreach my $obj (@constants) { $junk = $obj->apirefSetup();}}
    if (@typedefs) { foreach my $obj (@typedefs) { $junk = $obj->apirefSetup();}}
    if (@structs) { foreach my $obj (@structs) { $junk = $obj->apirefSetup();}}
    if (@vars) { foreach my $obj (@vars) { $junk = $obj->apirefSetup();}}
    if (@enums) { foreach my $obj (@enums) { $junk = $obj->apirefSetup();}}
    if (@pDefines) { foreach my $obj (@pDefines) { $junk = $obj->apirefSetup();}}
    $HeaderDoc::ignore_apiuid_errors = 0;
    
    if ($self->functions()) {
		if (! -e $functionsDir) {
			unless (mkdir ("$functionsDir", 0777)) {die ("Can't create output folder $functionsDir. \n$!");};
	    }
	    $self->writeFunctions();
    }
    if ($self->methods()) {
		if (! -e $methodsDir) {
			unless (mkdir ("$methodsDir", 0777)) {die ("Can't create output folder $methodsDir. \n$!");};
	    }
	    $self->writeMethods();
    }
    
    if ($self->constants()) {
		if (! -e $constantsDir) {
			unless (mkdir ("$constantsDir", 0777)) {die ("Can't create output folder $constantsDir. \n$!");};
	    }
	    $self->writeConstants();
    }
    
    if ($self->typedefs()) {
		if (! -e $dataTypesDir) {
			unless (mkdir ("$dataTypesDir", 0777)) {die ("Can't create output folder $dataTypesDir. \n$!");};
	    }
	    $self->writeTypedefs();
    }
    
    if ($self->structs()) {
		if (! -e $structsDir) {
			unless (mkdir ("$structsDir", 0777)) {die ("Can't create output folder $structsDir. \n$!");};
	    }
	    $self->writeStructs();
    }
    if ($self->vars()) {
		if (! -e $varsDir) {
			unless (mkdir ("$varsDir", 0777)) {die ("Can't create output folder $varsDir. \n$!");};
	    }
	    $self->writeVars();
    }
    if ($self->enums()) {
		if (! -e $enumsDir) {
			unless (mkdir ("$enumsDir", 0777)) {die ("Can't create output folder $enumsDir. \n$!");};
	    }
	    $self->writeEnums();
    }

    if ($self->pDefines()) {
		if (! -e $pDefinesDir) {
			unless (mkdir ("$pDefinesDir", 0777)) {die ("Can't create output folder $pDefinesDir. \n$!");};
	    }
	    $self->writePDefines();
    }
}


sub writeHeaderElementsToManPage {
    my $self = shift;
    my $class = ref($self);
    my $compositePageName = $self->filename();
    my $localDebug = 0;

    $compositePageName =~ s/\.(h|i)$//o;
    $compositePageName .= ".mxml";
    my $rootOutputDir = $self->outputDir();
    my $tempOutputDir = $rootOutputDir."/mantemp";
    my $XMLPageString = $self->_getXMLPageString();

    mkdir($tempOutputDir);

    my $cwd = getcwd();
    chdir($tempOutputDir);

    open(OUTFILE, "|/usr/bin/hdxml2manxml");
    print OUTFILE $XMLPageString;
    print "WROTE: $XMLPageString\n" if ($localDebug);
    close(OUTFILE);

    my @files = <*.mxml>;

    foreach my $file (@files) {
	system("/usr/bin/xml2man $file");
	unlink($file);
    }

    chdir($cwd);

    @files = <${tempOutputDir}/*>;
    foreach my $file (@files) {
	my $filename = basename($file);
	print "RENAMING $file to $rootOutputDir/$filename\n" if ($localDebug);
	rename($file, "$rootOutputDir/$filename");
    }
    rmdir("$tempOutputDir");

}

sub writeHeaderElementsToXMLPage { # All API in a single XML page
    my $self = shift;
    my $class = ref($self);
    my $compositePageName = $self->filename();
    $compositePageName =~ s/\.(h|i)$//o;
    $compositePageName .= ".xml";
    my $rootOutputDir = $self->outputDir();
    my $name = $self->textToXML($self->name());
    my $XMLPageString = $self->_getXMLPageString();
    my $outputFile = $rootOutputDir.$pathSeparator.$compositePageName;
# print "cpn = $compositePageName\n";
    
	if (! -e $rootOutputDir) {
		unless (mkdir ("$rootOutputDir", 0777)) {die ("Can't create output folder $rootOutputDir. $!");};
    }
    $self->_createXMLOutputFile($outputFile, xml_fixup_links($self, $XMLPageString), "$name");
}

sub writeHeaderElementsToCompositePage { # All API in a single HTML page -- for printing
    my $self = shift;
    my $class = ref($self);
    my $compositePageName = $class->compositePageName();
    my $rootOutputDir = $self->outputDir();
    my $name = $self->name();
    my $compositePageString = $self->_getCompositePageString();
    # $compositePageString = $self->stripAppleRefs($compositePageString);
    my $outputFile = $rootOutputDir.$pathSeparator.$compositePageName;

	if (! -e $rootOutputDir) {
		unless (mkdir ("$rootOutputDir", 0777)) {die ("Can't create output folder $rootOutputDir. $!");};
    }
    my $processed_string = toplevel_html_fixup_links($self, $compositePageString);
    $self->_createHTMLOutputFile($outputFile, $processed_string, "$name");
}

sub _getXMLPageString {
    my $self = shift;
    my $name = $self->name();
    my $compositePageString;
    my $contentString;

    return $self->XMLdocumentationBlock(0);
    
    my $abstract = $self->XMLabstract();
    if (length($abstract)) {
	    $compositePageString .= "<abstract>";
	    $compositePageString .= $abstract;
	    $compositePageString .= "</abstract>\n";
    }

    my $discussion = $self->XMLdiscussion();
    if (length($discussion)) {
	    $compositePageString .= "<desc>";
	    $compositePageString .= $discussion;
	    $compositePageString .= "</desc>\n";
    }
    
    $contentString= $self->_getFunctionXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= "<functions>";
	    $compositePageString .= $contentString;
	    $compositePageString .= "</functions>\n";
    }
    $contentString= $self->_getMethodXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= "<methods>";
	    $compositePageString .= $contentString;
	    $compositePageString .= "</methods>\n";
    }
    
    $contentString= $self->_getConstantXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= "<constants>";
	    $compositePageString .= $contentString;
	    $compositePageString .= "</constants>\n";
    }
    
    $contentString= $self->_getTypedefXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= "<typedefs>";
	    $compositePageString .= $contentString;
	    $compositePageString .= "</typedefs>\n";
    }
    
    $contentString= $self->_getStructXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= "<structs_and_unions>";
	    $compositePageString .= $contentString;
	    $compositePageString .= "</structs_and_unions>\n";
    }
    
    $contentString= $self->_getVarXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= "<globals>";
	    $compositePageString .= $contentString;
	    $compositePageString .= "</globals>\n";
    }
    
    $contentString = $self->_getEnumXMLDetailString();
    if (length($contentString)) {
            $compositePageString .= "<enums>";
            $compositePageString .= $contentString;
            $compositePageString .= "</enums>\n";
    }
    
    $contentString= $self->_getPDefineXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= "<defines>";
	    $compositePageString .= $contentString;
	    $compositePageString .= "</defines>\n";
    }

    my $classContent = "";
    $contentString= $self->_getClassXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $classContent .= $contentString;
    }
    $contentString= $self->_getCategoryXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $classContent .= $contentString;
    }
    $contentString= $self->_getProtocolXMLDetailString();
    if (length($contentString)) {
		$contentString = $self->stripAppleRefs($contentString);
	    $classContent .= $contentString;
    }

    if (length($classContent)) {
	$compositePageString .= "<classes>\n$classContent</classes>\n"
    }


    return $compositePageString;


    # $compositePageString =~ s/^\<br\>\<br\>$//smog;
    # $compositePageString =~ s/\<br\>/<br\/>/smog;

    # global substitutions
    $compositePageString =~ s/\<h1\>//smigo;
    $compositePageString =~ s/\<\/h1\>//smigo;
    $compositePageString =~ s/\<h2\>//smigo;
    $compositePageString =~ s/\<\/h2\>//smigo;
    $compositePageString =~ s/\<h3\>//smigo;
    $compositePageString =~ s/\<\/h3\>//smigo;
    $compositePageString =~ s/\<hr\>//smigo;
    $compositePageString =~ s/\<br\>//smigo;
    $compositePageString =~ s/&lt;tt&gt;//smigo;
    $compositePageString =~ s/&lt;\/tt&gt;//smigo;
    $compositePageString =~ s/&lt;pre&gt;//smigo;
    $compositePageString =~ s/&lt;\/pre&gt;//smigo;
    $compositePageString =~ s/&nbsp;/ /smigo;

    # note: in theory, the paragraph tag can be left open,
    # which could break XML parsers.  While this is common
    # in web pages, it doesn't seem to be common in
    # headerdoc comments, so ignoring it for now.

    # case standardize tags.
    $compositePageString =~ s/<ul>/<ul>/smigo;
    $compositePageString =~ s/<\/ul>/<\/ul>/smigo;
    $compositePageString =~ s/<ol>/<ol>/smigo;
    $compositePageString =~ s/<\/ol>/<\/ol>/smigo;
    $compositePageString =~ s/<li>/<li>/smigo;
    $compositePageString =~ s/<\/li>/<\/li>/smigo;
    $compositePageString =~ s/<b>/<b>/smigo;
    $compositePageString =~ s/<\/b>/<\/b>/smigo;
    $compositePageString =~ s/<i>/<i>/smigo;
    $compositePageString =~ s/<\/i>/<\/i>/smigo;

    # Disable this fixup code.
    # $compositePageString = $newstring;
    
    return $compositePageString;
}

sub _getCompositePageString { 
    my $self = shift;
    my $name = $self->name();
    my $compositePageString;
    my $contentString;

    $compositePageString .= $self->compositePageAPIRef();

    my $abstract = $self->abstract();
    if (length($abstract)) {
	    $compositePageString .= "<h2>Abstract</h2>\n";
	    $compositePageString .= $abstract;
    }

    my $discussion = $self->discussion();
    if (length($discussion)) {
	    $compositePageString .= "<h2>Discussion</h2>\n";
	    $compositePageString .= $discussion;
    }
    
    # if ((length($abstract)) || (length($discussion))) {
    # ALWAYS....
	    $compositePageString .= "<hr><br>";
    # }

    my $etoc = $self->_getClassEmbeddedTOC(1);
    if (length($etoc)) {
	$compositePageString .= $etoc;
	$compositePageString .= "<hr><br>";
    }

    $contentString= $self->_getFunctionDetailString(1);
    if (length($contentString)) {
	    $compositePageString .= "<h2>Functions</h2>\n";
		# $contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= $contentString;
    }
    $contentString= $self->_getMethodDetailString(1);
    if (length($contentString)) {
	    $compositePageString .= "<h2>Methods</h2>\n";
		# $contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= $contentString;
    }
    
    $contentString= $self->_getConstantDetailString(1);
    if (length($contentString)) {
	    $compositePageString .= "<h2>Constants</h2>\n";
		# $contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= $contentString;
    }
    
    $contentString= $self->_getTypedefDetailString(1);
    if (length($contentString)) {
	    $compositePageString .= "<h2>Typedefs</h2>\n";
		# $contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= $contentString;
    }
    
    $contentString= $self->_getStructDetailString(1);
    if (length($contentString)) {
	    $compositePageString .= "<h2>Structs and Unions</h2>\n";
		# $contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= $contentString;
    }
    
    $contentString= $self->_getVarDetailString(1);
    if (length($contentString)) {
	    $compositePageString .= "<h2>Globals</h2>\n";
		# $contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= $contentString;
    }
    
    $contentString = $self->_getEnumDetailString(1);
    if (length($contentString)) {
            $compositePageString .= "<h2>Enumerations</h2>\n";
            $compositePageString .= $contentString;
    }
    
    $contentString= $self->_getPDefineDetailString(1);
    if (length($contentString)) {
	    $compositePageString .= "<h2>#defines</h2>\n";
		# $contentString = $self->stripAppleRefs($contentString);
	    $compositePageString .= $contentString;
    }
    return $compositePageString;
}

# apple_ref markup is a named anchor that uniquely identifies each API symbol.  For example, an Objective-C
# class named Foo would have the anchor <a name="//apple_ref/occ/cl/Foo"></a>.  This markup is already in the
# primary documentation pages, so we don't want duplicates in the composite pages, thus this method.  See
# the APIAnchors.html file in HeaderDoc's documentation to learn more about apple_ref markup.
sub stripAppleRefs {
    my $self = shift;
    my $string = shift;
    my $apiUIDPrefix = HeaderDoc::APIOwner->apiUIDPrefix();

	$apiUIDPrefix = quote($apiUIDPrefix);
	$string =~ s|<a\s+name\s*=\s*\"//$apiUIDPrefix/[^"]+?\">(.*?)<\s*/a\s*>|$1|g;
	return $string;
}

sub compositePageAPIRef
{
    my $self = shift;
    my $name = $self->name();

    my $uid = $self->compositePageAPIUID();
    my $apiref = "<a name=\"$uid\" title=\"$name\"></a>\n";

    return $apiref;
}

sub compositePageAPIUID
{
    my $self = shift;
    my $class = ref($self) || $self;
    my $apiUIDPrefix = HeaderDoc::APIOwner->apiUIDPrefix();
    my $type = "header";

    SWITCH : {
	($class eq "HeaderDoc::CPPClass") && do {
		$type = "class";
	    };
	($class eq "HeaderDoc::ObjCCategory") && do {
		$type = "class";
	    };
	($class eq "HeaderDoc::ObjCClass") && do {
		$type = "class";
	    };
	($class eq "HeaderDoc::ObjCContainer") && do {
		$type = "class";
	    };
	($class eq "HeaderDoc::ObjCProtocol") && do {
		$type = "protocol";
	    };
    }
    my $shortname = $self->name();
    if ($class eq "HeaderDoc::Header") {
	$shortname = $self->filename();
	$shortname =~ s/\.hdoc$//so;
    }
    $shortname = sanitize($shortname);

    my $apiuid = "//$apiUIDPrefix/doc/$type/$shortname";

    return $apiuid
}

sub writeFunctions {
    my $self = shift;
    my $functionFile = $self->functionsDir().$pathSeparator."Functions.html";
    $self->_createHTMLOutputFile($functionFile, $self->_getFunctionDetailString(0), "Functions");
}

sub _getFunctionDetailString {
    my $self = shift;
    my $composite = shift;
    my @funcObjs = $self->functions();
    my $contentString = "";

    $contentString .= $self->_getFunctionEmbeddedTOC($composite);

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @funcObjs;
    } else {
	@tempobjs = @funcObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getFunctionXMLDetailString {
    my $self = shift;
    my @funcObjs = $self->functions();
    my $contentString = "";

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @funcObjs;
    } else {
	@tempobjs = @funcObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}


sub _getClassXMLDetailString {
    my $self = shift;
    my @classObjs = $self->classes();
    my $contentString = "";

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @classObjs;
    } else {
	@tempobjs = @classObjs;
    }
    foreach my $obj (@tempobjs) {
	# print "outputting class ".$obj->name.".";
	my $documentationBlock = $obj->XMLdocumentationBlock();
	$contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getCategoryXMLDetailString {
    my $self = shift;
    my @classObjs = $self->categories();
    my $contentString = "";

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @classObjs;
    } else {
	@tempobjs = @classObjs;
    }
    foreach my $obj (@tempobjs) {
	# print "outputting category ".$obj->name.".";
	my $documentationBlock = $obj->XMLdocumentationBlock();
	$contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getProtocolXMLDetailString {
    my $self = shift;
    my @classObjs = $self->protocols();
    my $contentString = "";

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @classObjs;
    } else {
	@tempobjs = @classObjs;
    }
    foreach my $obj (@tempobjs) {
	# print "outputting protocol ".$obj->name.".";
	my $documentationBlock = $obj->XMLdocumentationBlock();
	$contentString .= $documentationBlock;
    }
    return $contentString;
}

sub writeMethods {
    my $self = shift;
    my $methodFile = $self->methodsDir().$pathSeparator."Methods.html";
    $self->_createHTMLOutputFile($methodFile, $self->_getMethodDetailString(0), "Methods");
}

sub _getEmbeddedTOC
{
    my $self = shift;
    my $listref = shift;
    my $typeFile = shift;
    my $tag = shift;
    my $compositePage = shift;
    my $includeObjectName = shift;
    my $localDebug = 0;

    print "CPAGE: $compositePage\n" if ($localDebug);

    my @objlist = @{ $listref };
    my $eTOCString = "";
    my $class = ref($self) || $self;
    my $localDebug = 0;
    my $compositePageName = $self->compositePageName();

    if ($includeObjectName) {
	$eTOCString .= "<h2>$tag</h2>\n";
    } else {
	$eTOCString .= "<a name=\"HeaderDoc_$tag\"></a>\n";
    }

    print "My class is $class\n" if ($localDebug);

    if (!scalar(@objlist)) {
	print "empty objlist\n" if ($localDebug);
	return "";
    }
    # if (!($#objlist)) {
	# print "empty objlist\n" if ($localDebug);
	# return "";
    # }

    $eTOCString .= "<dl>\n";
    foreach my $obj (@objlist) {
	# print "@objlist\n";
	# print "OBJ: $obj\n";
	my $name = $obj->name();
	my $abstract = $obj->abstract();
	my $url = "";

	my $target = "doc";
	my $composite = $HeaderDoc::ClassAsComposite;
	if ($class eq "HeaderDoc::Header") { $composite = 0; }
	if ($compositePage) { $composite = 1; $target = "_top"; }

	my $safeName = $name;
	$safeName = &safeName(filename => $name);

	my $urlname = $obj->apiuid(); # sanitize($name);
	if ($composite && !$HeaderDoc::ClassAsComposite) {
		$urlname = $obj->compositePageUID();
	}

	if ($includeObjectName && $composite) {
	    $url = "$typeFile/$safeName/$compositePageName#$urlname";
	} elsif ($includeObjectName) {
	    $url = "$typeFile/$safeName/index.html#$urlname";
	} elsif ($composite) {
	    $url = "$compositePageName#$urlname"
	} else {
	    $url = "$typeFile#$urlname"
	}

	my $parentclass = $obj->origClass();
	if (length($parentclass)) { $parentclass .= "::"; }
	if ($self->CClass()) {
		# Don't do this for pseudo-classes.
		$parentclass = "";
	}

	$eTOCString .= "<dt><tt><a href=\"$url\" target=\"$target\">$parentclass$name</a></tt></dt>\n";
	$eTOCString .= "<dd>$abstract</dd>\n";
    }
    $eTOCString .= "</dl>\n";

print "etoc: $eTOCString\n" if ($localDebug);

    return $eTOCString;
}

sub _getClassEmbeddedTOC
{
    my $self = shift;
    my $composite = shift;
    my @possclasses = $self->classes();
    my @protocols = $self->protocols();
    my @categories = $self->categories();
    my $localDebug = 0;

    my $retval = "";

    print "getClassEmbeddedTOC: processing ".$self->name()."\n" if ($localDebug);

    my @classes = ();
    my @comints = ();

    foreach my $class (@possclasses) {
	if ($class->isCOMInterface()) {
	    push(@comints, $class);
	} else  {
	    push(@classes, $class);
	}
    }

    if (scalar(@classes)) {
	print "getClassEmbeddedTOC: classes found.\n" if ($localDebug);
	my @tempobjs = ();
	if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @classes;
	} else {
		@tempobjs = @classes;
	}
	if ($localDebug) {
		foreach my $item(@tempobjs) {
			print "TO: $item : ".$item->name()."\n";
		}
	}
	$retval .= $self->_getEmbeddedTOC(\@tempobjs, "Classes", "Classes", $composite, 1);
    }
    if (scalar(@comints)) {
	print "getClassEmbeddedTOC: comints found.\n" if ($localDebug);
	my @tempobjs = ();
	if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @comints;
	} else {
		@tempobjs = @comints;
	}
	if ($localDebug) {
		foreach my $item(@tempobjs) {
			print "TO: $item : ".$item->name()."\n";
		}
	}
	$retval .= $self->_getEmbeddedTOC(\@tempobjs, "Classes", "COM Interfaces", $composite, 1);
    }
    if (scalar(@protocols)) {
	print "getClassEmbeddedTOC: protocols found.\n" if ($localDebug);
	my @tempobjs = ();
	if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @protocols;
	} else {
		@tempobjs = @protocols;
	}
	if ($localDebug) {
		foreach my $item(@tempobjs) {
			print "TO: $item : ".$item->name()."\n";
		}
	}
	$retval .= $self->_getEmbeddedTOC(\@tempobjs, "Protocols", "Protocols", $composite, 1);
    }
    if (scalar(@categories)) {
	print "getClassEmbeddedTOC: categories found.\n" if ($localDebug);
	my @tempobjs = ();
	if ($HeaderDoc::sort_entries) {
		@tempobjs = sort objName @categories;
	} else {
		@tempobjs = @categories;
	}
	if ($localDebug) {
		foreach my $item(@tempobjs) {
			print "TO: $item : ".$item->name()."\n";
		}
	}
	$retval .= $self->_getEmbeddedTOC(\@tempobjs, "Categories", "Categories", $composite, 1);
    }

    print "eClassTOC = $retval\n" if ($localDebug);

   return $retval;
}

sub _getFunctionEmbeddedTOC
{
   my $self = shift;
   my $composite = shift;
   my @functions = $self->functions();
   return $self->_getEmbeddedTOC(\@functions, "Functions.html", "functions", $composite, 0);
}

sub _getMethodEmbeddedTOC
{
   my $self = shift;
   my $composite = shift;
   my @methods = $self->methods();
   return $self->_getEmbeddedTOC(\@methods, "Methods.html", "methods", $composite, 0);
}

sub _getMethodDetailString {
    my $self = shift;
    my $composite = shift;
    my @methObjs = $self->methods();
    my $contentString = "";
    my $localDebug = 0;

    $contentString .= $self->_getMethodEmbeddedTOC($composite);

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @methObjs;
    } else {
	@tempobjs = @methObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getMethodXMLDetailString {
    my $self = shift;
    my @methObjs = $self->methods();
    my $contentString = "";

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @methObjs;
    } else {
	@tempobjs = @methObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub writeConstants {
    my $self = shift;
    my $constantsFile = $self->constantsDir().$pathSeparator."Constants.html";
    $self->_createHTMLOutputFile($constantsFile, $self->_getConstantDetailString(0), "Constants");
}

sub _getConstantDetailString {
    my $self = shift;
    my $composite = shift;
    my @constantObjs = $self->constants();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @constantObjs;
    } else {
	@tempobjs = @constantObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getConstantXMLDetailString {
    my $self = shift;
    my @constantObjs = $self->constants();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @constantObjs;
    } else {
	@tempobjs = @constantObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub writeTypedefs {
    my $self = shift;
    my $typedefsFile = $self->datatypesDir().$pathSeparator."DataTypes.html";
    $self->_createHTMLOutputFile($typedefsFile, $self->_getTypedefDetailString(0), "Defined Types");
}

sub _getTypedefDetailString {
    my $self = shift;
    my $composite = shift;
    my @typedefObjs = $self->typedefs();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @typedefObjs;
    } else {
	@tempobjs = @typedefObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getTypedefXMLDetailString {
    my $self = shift;
    my @typedefObjs = $self->typedefs();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @typedefObjs;
    } else {
	@tempobjs = @typedefObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub writeStructs {
    my $self = shift;
    my $structsFile = $self->structsDir().$pathSeparator."Structs.html";
    $self->_createHTMLOutputFile($structsFile, $self->_getStructDetailString(0), "Structs");
}

sub _getStructDetailString {
    my $self = shift;
    my $composite = shift;
    my @structObjs = $self->structs();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @structObjs;
    } else {
	@tempobjs = @structObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getStructXMLDetailString {
    my $self = shift;
    my @structObjs = $self->structs();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @structObjs;
    } else {
	@tempobjs = @structObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub writeVars {
    my $self = shift;
    my $varsFile = $self->varsDir().$pathSeparator."Vars.html";
    $self->_createHTMLOutputFile($varsFile, $self->_getVarDetailString(0), "Data Members");
}

sub _getVarDetailString {
    my $self = shift;
    my $composite = shift;
    my @varObjs = $self->vars();
    my $contentString;
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @varObjs;
    } else {
	@tempobjs = @varObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getVarXMLDetailString {
    my $self = shift;
    my @varObjs = $self->vars();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @varObjs;
    } else {
	@tempobjs = @varObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub writeEnums {
    my $self = shift;
    my $enumsFile = $self->enumsDir().$pathSeparator."Enums.html";
    $self->_createHTMLOutputFile($enumsFile, $self->_getEnumDetailString(0), "Enumerations");
}

sub _getEnumDetailString {
    my $self = shift;
    my $composite = shift;
    my @enumObjs = $self->enums();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @enumObjs;
    } else {
	@tempobjs = @enumObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getEnumXMLDetailString {
    my $self = shift;
    my @enumObjs = $self->enums();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @enumObjs;
    } else {
	@tempobjs = @enumObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub writePDefines {
    my $self = shift;
    my $pDefinesFile = $self->pDefinesDir().$pathSeparator."PDefines.html";
    $self->_createHTMLOutputFile($pDefinesFile, $self->_getPDefineDetailString(0), "#defines");
}

sub _getPDefineDetailString {
    my $self = shift;
    my $composite = shift;
    my @pDefineObjs = $self->pDefines();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @pDefineObjs;
    } else {
	@tempobjs = @pDefineObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->documentationBlock($composite);
        $contentString .= $documentationBlock;
    }
    return $contentString;
}

sub _getPDefineXMLDetailString {
    my $self = shift;
    my @pDefineObjs = $self->pDefines();
    my $contentString;

    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @pDefineObjs;
    } else {
	@tempobjs = @pDefineObjs;
    }
    foreach my $obj (@tempobjs) {
        my $documentationBlock = $obj->XMLdocumentationBlock();
        $contentString .= $documentationBlock;
    }
    return $contentString;
}


sub writeExportsWithName {
    my $self = shift;
    my $name = shift;
    my $exportsDir = $self->exportsDir();
    my $functionsFile = $exportsDir.$pathSeparator.$name.".ftab";
    my $methodsFile = $exportsDir.$pathSeparator.$name.".ftab";
    my $parametersFile = $exportsDir.$pathSeparator.$name.".ptab";
    my $structsFile = $exportsDir.$pathSeparator.$name.".stab";
    my $fieldsFile = $exportsDir.$pathSeparator.$name.".mtab";
    my $enumeratorsFile = $exportsDir.$pathSeparator.$name.".ktab";
    my $funcString;
    my $methString;
    my $paramString;
    my $dataTypeString;
    my $typesFieldString;
    my $enumeratorsString;
    
	if (! -e $exportsDir) {
		unless (mkdir ("$exportsDir", 0777)) {die ("Can't create output folder $exportsDir. $!");};
    }
    ($funcString, $paramString) = $self->_getFunctionsAndParamsExportString();
    ($methString, $paramString) = $self->_getMethodsAndParamsExportString();
    ($dataTypeString, $typesFieldString) = $self->_getDataTypesAndFieldsExportString();
    $enumeratorsString = $self->_getEnumeratorsExportString();
    
    $self->_createExportFile($functionsFile, $funcString);
    $self->_createExportFile($methodsFile, $methString);
    $self->_createExportFile($parametersFile, $paramString);
    $self->_createExportFile($structsFile, $dataTypeString);
    $self->_createExportFile($fieldsFile, $typesFieldString);
    $self->_createExportFile($enumeratorsFile, $enumeratorsString);
}

sub _getFunctionsAndParamsExportString {
    my $self = shift;
    my @funcObjs = $self->functions();
    my $tmpString = "";
    my @funcLines;
    my @paramLines;
    my $funcString;
    my $paramString;
    my $sep = "<tab>";       
    
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @funcObjs;
    } else {
	@tempobjs = @funcObjs;
    }
    foreach my $obj (@tempobjs) {
        my $funcName = $obj->name();
        my $desc = $obj->discussion();
        my $abstract = $obj->abstract();
		my $declaration = $obj->declaration();
        my @taggedParams = $obj->taggedParameters();
        my @parsedParams = $obj->parsedParameters();
        my $result = $obj->result();
        my $funcID = HeaderDoc::DBLookup->functionIDForName($funcName);
        # unused fields--declaring them for visibility in the string below
        my $managerID = "";
        my $funcEnglishName = "";
        my $specialConsiderations = "";
        my $versionNotes = "";
        my $groupName = "";
        my $order = "";
        
        # Replace single internal carriage returns in fields with one space
        # headerDoc2HTML already changes two \n's to \n<br><br>\n, so we'll
        # just remove the breaks
        foreach my $string ($desc, $abstract, $declaration, $result) {
     		$string =~ s/\n<br><br>\n/\n\n/go;
     		$string =~ s/([^\n])\n([^\n])/$1 $2/go;
        }
        $tmpString = $managerID.$sep.$funcID.$sep.$funcName.$sep.$funcEnglishName.$sep.$abstract.$sep.$desc.$sep.$result.$sep.$specialConsiderations.$sep.$versionNotes.$sep.$groupName.$sep.$order;
        $tmpString = &convertCharsForFileMaker($tmpString);
        $tmpString =~ s/$sep/\t/g;
        push (@funcLines, "$tmpString");
        
        if (@taggedParams) {
            my %parsedParmNameToObjHash;
        	# make lookup hash of parsed params
        	foreach my $parsedParam (@parsedParams) {
        		$parsedParmNameToObjHash{$parsedParam->name()} = $parsedParam;
        	}
        	foreach my $taggedParam (@taggedParams) {
        	    my $tName = $taggedParam->name();
        	    my $pObj;
		        my $pos = "UNKNOWN_POSITION";
		        my $type = "UNKNOWN_TYPE";

		        if (exists $parsedParmNameToObjHash{$tName}) {
		            $pObj = $parsedParmNameToObjHash{$tName};
		        	$pos = $pObj->position();
		        	$type = $pObj->type();
		        } else {

				# my $filename = $HeaderDoc::headerObject->name();
				my $filename = $self->filename();
				my $linenum = $self->linenum();
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	warn "$filename:$linenum:Tagged parameter '$tName' not found in declaration of function $funcName.\n";
		        	warn "$filename:$linenum:Parsed declaration for $funcName is:\n$declaration\n";
		        	warn "$filename:$linenum:Parsed params for $funcName are:\n";
		        	foreach my $pp (@parsedParams) {
		        	    my $n = $pp->name();
		        	    print "$filename:$linenum:$n\n";
		        	}
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        }
	        	my $paramName = $taggedParam->name();
	        	my $disc = $taggedParam->discussion();
	     		$disc =~ s/\n<br><br>\n/\n\n/go;
	     		$disc =~ s/([^\n])\n([^\n])/$1 $2/go;
	        	my $tmpParamString = "";
	        	
	        	$tmpParamString = $funcID.$sep.$funcName.$sep.$pos.$sep.$disc.$sep.$sep.$sep.$paramName.$sep.$type;
        		$tmpParamString = &convertCharsForFileMaker($tmpParamString);
        		$tmpParamString =~ s/$sep/\t/g;
	        	push (@paramLines, "$tmpParamString");
        	}
        }
    }
    $funcString = join ("\n", @funcLines);
    $paramString = join ("\n", @paramLines);
    $funcString .= "\n";
    $paramString .= "\n";
    return ($funcString, $paramString);
}

sub _getMethodsAndParamsExportString {
    my $self = shift;
    my @methObjs = $self->methods();
    my $tmpString = "";
    my @methLines;
    my @paramLines;
    my $methString;
    my $paramString;
    my $sep = "<tab>";       
    
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @methObjs;
    } else {
	@tempobjs = @methObjs;
    }
    foreach my $obj (@tempobjs) {
        my $methName = $obj->name();
        my $desc = $obj->discussion();
        my $abstract = $obj->abstract();
		my $declaration = $obj->declaration();
        my @taggedParams = $obj->taggedParameters();
        my @parsedParams = $obj->parsedParameters();
        my $result = $obj->result();
        my $methID = HeaderDoc::DBLookup->methodIDForName($methName);
        # unused fields--declaring them for visibility in the string below
        my $managerID = "";
        my $methEnglishName = "";
        my $specialConsiderations = "";
        my $versionNotes = "";
        my $groupName = "";
        my $order = "";
        
        # Replace single internal carriage returns in fields with one space
        # headerDoc2HTML already changes two \n's to \n<br><br>\n, so we'll
        # just remove the breaks
        foreach my $string ($desc, $abstract, $declaration, $result) {
     		$string =~ s/\n<br><br>\n/\n\n/go;
     		$string =~ s/([^\n])\n([^\n])/$1 $2/go;
        }
        $tmpString = $managerID.$sep.$methID.$sep.$methName.$sep.$methEnglishName.$sep.$abstract.$sep.$desc.$sep.$result.$sep.$specialConsiderations.$sep.$versionNotes.$sep.$groupName.$sep.$order;
        $tmpString = &convertCharsForFileMaker($tmpString);
        $tmpString =~ s/$sep/\t/g;
        push (@methLines, "$tmpString");
        
        if (@taggedParams) {
            my %parsedParmNameToObjHash;
        	# make lookup hash of parsed params
        	foreach my $parsedParam (@parsedParams) {
        		$parsedParmNameToObjHash{$parsedParam->name()} = $parsedParam;
        	}
        	foreach my $taggedParam (@taggedParams) {
        	    my $tName = $taggedParam->name();
        	    my $pObj;
		        my $pos = "UNKNOWN_POSITION";
		        my $type = "UNKNOWN_TYPE";

		        if (exists $parsedParmNameToObjHash{$tName}) {
		            $pObj = $parsedParmNameToObjHash{$tName};
		        	$pos = $pObj->position();
		        	$type = $pObj->type();
		        } else {
				# my $filename = $HeaderDoc::headerObject->name();
				my $filename = $self->filename();
				my $linenum = $self->linenum();
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	warn "$filename:$linenum:Tagged parameter '$tName' not found in declaration of method $methName.\n";
		        	warn "$filename:$linenum:Parsed declaration for $methName is:\n$declaration\n";
		        	warn "$filename:$linenum:Parsed params for $methName are:\n";
		        	foreach my $pp (@parsedParams) {
		        	    my $n = $pp->name();
		        	    print "$filename:$linenum:$n\n";
		        	}
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        }
	        	my $paramName = $taggedParam->name();
	        	my $disc = $taggedParam->discussion();
	     		$disc =~ s/\n<br><br>\n/\n\n/go;
	     		$disc =~ s/([^\n])\n([^\n])/$1 $2/go;
	        	my $tmpParamString = "";
	        	
	        	$tmpParamString = $methID.$sep.$methName.$sep.$pos.$sep.$disc.$sep.$sep.$sep.$paramName.$sep.$type;
        		$tmpParamString = &convertCharsForFileMaker($tmpParamString);
        		$tmpParamString =~ s/$sep/\t/g;
	        	push (@paramLines, "$tmpParamString");
        	}
        }
    }
    $methString = join ("\n", @methLines);
    $paramString = join ("\n", @paramLines);
    $methString .= "\n";
    $paramString .= "\n";
    return ($methString, $paramString);
}


sub _getDataTypesAndFieldsExportString {
    my $self = shift;
    my @structObjs = $self->structs();
    my @typedefs = $self->typedefs();
    my @constants = $self->constants();
    my @enums = $self->enums();
    my @dataTypeLines;
    my @fieldLines;
    my $dataTypeString;
    my $fieldString;

    my $sep = "<tab>";       
    my $tmpString = "";
    my $contentString = "";
    
    # unused fields -- here for clarity
    my $englishName = "";
    my $specialConsiderations = "";
    my $versionNotes = "";
    
    # get Enumerations
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @enums;
    } else {
	@tempobjs = @enums;
    }
    foreach my $obj (@tempobjs) {
        my $name = $obj->name();
        my $desc = $obj->discussion();
        my $abstract = $obj->abstract();
        my $declaration = $obj->declaration();
        my $enumID = HeaderDoc::DBLookup->typeIDForName($name);
        
        # Replace single internal carriage returns in fields with one space
        # headerDoc2HTML already changes two \n's to \n<br><br>\n, so we'll
        # just remove the breaks
        foreach my $string ($desc, $abstract, $declaration) {
     		$string =~ s/\n<br><br>\n/\n\n/go;
     		$string =~ s/([^\n])\n([^\n])/$1 $2/go;
        }
        $tmpString = $enumID.$sep.$name.$sep.$englishName.$sep.$abstract.$sep.$desc.$sep.$specialConsiderations.$sep.$versionNotes."\n";
        $tmpString = &convertCharsForFileMaker($tmpString);
        $tmpString =~ s/$sep/\t/g;
        push (@dataTypeLines, "$tmpString");
    }
    # get Constants
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @constants;
    } else {
	@tempobjs = @constants;
    }
    foreach my $obj (@tempobjs) {
        my $name = $obj->name();
        my $desc = $obj->discussion();
        my $abstract = $obj->abstract();
        my $constID = HeaderDoc::DBLookup->typeIDForName($name);
        
        # Replace single internal carriage returns in fields with one space
        # headerDoc2HTML already changes two \n's to \n<br><br>\n, so we'll
        # just remove the breaks
        foreach my $string ($desc, $abstract) {
     		$string =~ s/\n<br><br>\n/\n\n/go;
     		$string =~ s/([^\n])\n([^\n])/$1 $2/go;
        }
        $tmpString = $constID.$sep.$name.$sep.$englishName.$sep.$abstract.$sep.$desc.$sep.$specialConsiderations.$sep.$versionNotes."\n";
        $tmpString = &convertCharsForFileMaker($tmpString);
        $tmpString =~ s/$sep/\t/g;
        push (@dataTypeLines, "$tmpString");
    }
    # get Structs and Unions
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @structObjs;
    } else {
	@tempobjs = @structObjs;
    }
    foreach my $obj (@tempobjs) {
        my $name = $obj->name();
        my $desc = $obj->discussion();
        my $abstract = $obj->abstract();
        my $declaration = $obj->declaration();
        my @fields = $obj->fields();
        my $structID = HeaderDoc::DBLookup->typeIDForName($name);
        
        # Replace single internal carriage returns in fields with one space
        # headerDoc2HTML already changes two \n's to \n<br><br>\n, so we'll
        # just remove the breaks
        foreach my $string ($desc, $abstract, $declaration) {
     		$string =~ s/\n<br><br>\n/\n\n/go;
     		$string =~ s/([^\n])\n([^\n])/$1 $2/go;
        }
        $tmpString = $structID.$sep.$name.$sep.$englishName.$sep.$abstract.$sep.$desc.$sep.$specialConsiderations.$sep.$versionNotes."\n";
        $tmpString = &convertCharsForFileMaker($tmpString);
        $tmpString =~ s/$sep/\t/g;
        push (@dataTypeLines, "$tmpString");
        
        if (@fields) {
        	foreach my $field (@fields) {
        	    my $fName = $field->name();
        	    my $discussion = $field->discussion();
	     		$discussion =~ s/\n<br><br>\n/\n\n/go;
	     		$discussion =~ s/([^\n])\n([^\n])/$1 $2/go;
        	    my $pos = 0;
        	    
        	    $pos = $self->_positionOfNameInBlock($fName, $declaration);
		        if (!$pos) {
				# my $filename = $HeaderDoc::headerObject->name();
				my $filename = $self->filename();
				my $linenum = $self->linenum();
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	warn "$filename:$linenum:Tagged parameter '$fName' not found in declaration of struct $name.\n";
		        	warn "$filename:$linenum:Declaration for $name is:\n$declaration\n";
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	$pos = "UNKNOWN_POSITION";
		        }
	        	my $tmpFieldString = "";
	        	$tmpFieldString = $structID.$sep.$name.$sep.$pos.$sep.$discussion.$sep.$sep.$sep.$fName;
        		$tmpFieldString = &convertCharsForFileMaker($tmpFieldString);
        		$tmpFieldString =~ s/$sep/\t/g;
	        	push (@fieldLines, "$tmpFieldString");
        	}
        }
    }
    # get Typedefs
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @typedefs;
    } else {
	@tempobjs = @typedefs;
    }
    foreach my $obj (@tempobjs) {
        my $name = $obj->name();
        my $desc = $obj->discussion();
        my $abstract = $obj->abstract();
        my $declaration = $obj->declaration();
        my @fields = $obj->fields();
        my $isFunctionPointer = $obj->isFunctionPointer();
        my $typedefID = HeaderDoc::DBLookup->typeIDForName($name);
        
        # Replace single internal carriage returns in fields with one space
        # headerDoc2HTML already changes two \n's to \n<br><br>\n, so we'll
        # just remove the breaks
        foreach my $string ($desc, $abstract, $declaration) {
     		$string =~ s/\n<br><br>\n/\n\n/go;
     		$string =~ s/([^\n])\n([^\n])/$1 $2/go;
        }
        $tmpString = $typedefID.$sep.$name.$sep.$englishName.$sep.$abstract.$sep.$desc.$sep.$specialConsiderations.$sep.$versionNotes."\n";
        $tmpString = &convertCharsForFileMaker($tmpString);
        $tmpString =~ s/$sep/\t/g;
        push (@dataTypeLines, "$tmpString");
        if (@fields) {
        	foreach my $field (@fields) {
        	    my $fName = $field->name();
        	    my $discussion = $field->discussion();
	     		$discussion =~ s/\n<br><br>\n/\n\n/go;
	     		$discussion =~ s/([^\n])\n([^\n])/$1 $2/go;
        	    my $pos = 0;
        	    
        	    if ($isFunctionPointer) {
        	        $pos = $self->_positionOfNameInFuncPtrDec($fName, $declaration);
        	    } else {
        	        $pos = $self->_positionOfNameInBlock($fName, $declaration);
        	    }
		        if (!$pos) {
				# my $filename = $HeaderDoc::headerObject->name();
				my $filename = $self->filename();
				my $linenum = $self->linenum();
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	warn "$filename:$linenum:Tagged parameter '$fName' not found in declaration of struct $name.\n";
		        	warn "$filename:$linenum:Declaration for $name is:\n$declaration\n";
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	$pos = "UNKNOWN_POSITION";
		        }
	        	my $tmpFieldString = "";
	        	$tmpFieldString = $typedefID.$sep.$name.$sep.$pos.$sep.$discussion.$sep.$sep.$sep.$fName;
        		$tmpFieldString = &convertCharsForFileMaker($tmpFieldString);
        		$tmpFieldString =~ s/$sep/\t/g;
	        	push (@fieldLines, "$tmpFieldString");
        	}
        }
    }
    $dataTypeString = join ("\n", @dataTypeLines);
    $fieldString = join ("\n", @fieldLines);
	$dataTypeString .= "\n";
	$fieldString .= "\n";
    return ($dataTypeString, $fieldString);
}


sub _getEnumeratorsExportString {
    my $self = shift;
    my @enums = $self->enums();
    my @fieldLines;
    my $fieldString;

    my $sep = "<tab>";       
    my $tmpString = "";
    my $contentString = "";
    
    # get Enumerations
    my @tempobjs = ();
    if ($HeaderDoc::sort_entries) {
	@tempobjs = sort objName @enums;
    } else {
	@tempobjs = @enums;
    }
    foreach my $obj (@tempobjs) {
        my $name = $obj->name();
        my @constants = $obj->constants();
        my $declaration = $obj->declaration();
        my $enumID = HeaderDoc::DBLookup->typeIDForName($name);
        
        if (@constants) {
        	foreach my $enumerator (@constants) {
        	    my $fName = $enumerator->name();
        	    my $discussion = $enumerator->discussion();
        	    my $pos = 0;
        	    
	     		$discussion =~ s/\n<br><br>\n/\n\n/go;
	     		$discussion =~ s/([^\n])\n([^\n])/$1 $2/go;
        	    $pos = $self->_positionOfNameInEnum($fName, $declaration);
		        if (!$pos) {
				# my $filename = $HeaderDoc::headerObject->name();
				my $filename = $self->filename();
				my $linenum = $self->linenum();
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	warn "$filename:$linenum:Tagged parameter '$fName' not found in declaration of enum $name.\n";
		        	warn "$filename:$linenum:Declaration for $name is:\n$declaration\n";
		        	print "$filename:$linenum:---------------------------------------------------------------------------\n";
		        	$pos = "UNKNOWN_POSITION";
		        }
	        	my $tmpFieldString = "";
	        	$tmpFieldString = $enumID.$sep.$name.$sep.$pos.$sep.$discussion.$sep.$sep.$sep.$fName;
        		$tmpFieldString = &convertCharsForFileMaker($tmpFieldString);
        		$tmpFieldString =~ s/$sep/\t/g;
	        	push (@fieldLines, "$tmpFieldString");
        	}
        }
    }
    $fieldString = join ("\n", @fieldLines);
	$fieldString .= "\n";
    return $fieldString;
}

# this is simplistic is various ways--should be made more robust.
sub _positionOfNameInBlock {
    my $self = shift;
    my $name = shift;    
    my $block = shift;
    $block =~ s/\n/ /go;
    
    my $pos = 0;
    my $i = 0;
    my @chunks = split (/;/, $block);
    foreach my $string (@chunks) {
        $i++;
        $string = quotemeta($string);
        if ($string =~ /$name/) {
            $pos = $i;
            last;
        }
    }
    return $pos;
}

sub _positionOfNameInEnum {
    my $self = shift;
    my $name = shift;    
    my $block = shift;
    $block =~ s/\n/ /go;
    
    my $pos = 0;
    my $i = 0;
    my @chunks = split (/,/, $block);
    foreach my $string (@chunks) {
        $i++;
        $string = quotemeta($string);
        if ($string =~ /$name/) {
            $pos = $i;
            last;
        }
    }
    return $pos;
}

sub _positionOfNameInFuncPtrDec {
    my $self = shift;
    my $name = shift;    
    my $dec = shift;
    $dec =~ s/\n/ /go;
    
    my @decParts = split (/\(/, $dec);
    my $paramList = pop @decParts;
    
    
    my $pos = 0;
    my $i = 0;
    my @chunks = split (/,/, $paramList);
    foreach my $string (@chunks) {
        $i++;
        $string = quotemeta($string);
        if ($string =~ /$name/) {
            $pos = $i;
            last;
        }
    }
    return $pos;
}

sub _positionOfNameInMethPtrDec {
    my $self = shift;
    my $name = shift;    
    my $dec = shift;
    $dec =~ s/\n/ /go;
    
    my @decParts = split (/\(/, $dec);
    my $paramList = pop @decParts;
    
    my $pos = 0;
    my $i = 0;
    my @chunks = split (/,/, $paramList);
    foreach my $string (@chunks) {
        $i++;
        $string = quotemeta($string);
        if ($string =~ /$name/) {
            $pos = $i;
            last;
        }
    }
    return $pos;
}

sub _createExportFile {
    my $self = shift;
    my $outputFile = shift;    
    my $fileString = shift;    

	open(OUTFILE, ">$outputFile") || die "Can't write $outputFile.\n";
    if ($^O =~ /MacOS/io) {MacPerl::SetFileInfo('R*ch', 'TEXT', "$outputFile");};
	print OUTFILE $fileString;
	close OUTFILE;
}

sub _createXMLOutputFile {
    my $self = shift;
    my $class = ref($self);
    # my $copyrightOwner = $self->htmlToXML($class->copyrightOwner());
    my $outputFile = shift;    
    my $orig_fileString = shift;    
    my $heading = shift;
    my $fullpath = $self->fullpath();

    # if ($class eq "HeaderDoc::Header") {
	# my $headercopyright = $self->htmlToXML($self->headerCopyrightOwner());
	# if (!($headercopyright eq "")) {
	    # $copyrightOwner = $headercopyright;
	# }
    # }

    my $HTMLmeta = "";
    if ($class eq "HeaderDoc::Header") {
	$HTMLmeta = $self->HTMLmeta();
    }

        calcDepth($outputFile);
	my $fileString = $self->xml_fixup_links($orig_fileString);

	open(OUTFILE, ">$outputFile") || die "Can't write $outputFile.\n";
    if ($^O =~ /MacOS/io) {MacPerl::SetFileInfo('MSIE', 'TEXT', "$outputFile");};
	print OUTFILE "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
	# print OUTFILE "<!DOCTYPE header PUBLIC \"-//Apple Computer//DTD HEADERDOC 1.0//EN\" \"http://www.apple.com/DTDs/HeaderDoc-1.0.dtd\">\n";
	print OUTFILE "<!DOCTYPE header PUBLIC \"-//Apple Computer//DTD HEADERDOC 1.0//EN\" \"/System/Library/DTDs/HeaderDoc-1.0.dtd\">\n";
	# print OUTFILE "<header filename=\"$heading\" headerpath=\"$fullpath\" headerclass=\"\">";
	# print OUTFILE "<name>$heading</name>\n";

	# Need to get the C++ Class Abstract and Discussion....
	# my $headerDiscussion = $self->discussion();   
	# my $headerAbstract = $self->abstract(); 

	# print OUTFILE "<abstract>$headerAbstract</abstract>\n";
	# print OUTFILE "<discussion>$headerDiscussion</discussion>\n";

	print OUTFILE $fileString;
	# print OUTFILE "<copyrightinfo>&#169; $copyrightOwner</copyrightinfo>" if (length($copyrightOwner));
	# print OUTFILE "<timestamp>$dateStamp</timestamp>\n";
	# print OUTFILE "</header>";
	close OUTFILE;
}

sub _createHTMLOutputFile {
    my $self = shift;
    my $class = ref($self);
    my $copyrightOwner = $class->copyrightOwner();
    my $outputFile = shift;    
    my $orig_fileString = shift;    
    my $heading = shift;    

    if ($class eq "HeaderDoc::Header") {
	my $headercopyright = $self->headerCopyrightOwner();
	if (!($headercopyright eq "")) {
	    $copyrightOwner = $headercopyright;
	}
    }

    my $HTMLmeta = "";
    if ($class eq "HeaderDoc::Header") {
	$HTMLmeta = $self->HTMLmeta();
    }

        calcDepth($outputFile);
	my $fileString = html_fixup_links($self, $orig_fileString);

	open(OUTFILE, ">$outputFile") || die "Can't write $outputFile.\n";
    if ($^O =~ /MacOS/io) {MacPerl::SetFileInfo('MSIE', 'TEXT', "$outputFile");};
	print OUTFILE "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\"\n    \"http://www.w3.org/TR/1998/REC-html40-19980424/loose.dtd\">\n";
	print OUTFILE "<html>";

	print OUTFILE $self->styleSheet(0);

	print OUTFILE "<head>\n    <title>$heading</title>\n	$HTMLmeta <meta name=\"generator\" content=\"HeaderDoc\">\n";
	print OUTFILE "</head><body bgcolor=\"#ffffff\">\n";
	if ($HeaderDoc::insert_header) {
		print OUTFILE "<!-- start of header -->\n";
		print OUTFILE $self->htmlHeader()."\n";
		print OUTFILE "<!-- end of header -->\n";
	}
	print OUTFILE "<h1><font face=\"Geneva,Arial,Helvtica\">$heading</font></h1><br>\n";
	print OUTFILE $fileString;
    print OUTFILE "<p>";
    print OUTFILE "<p>&#169; $copyrightOwner " if (length($copyrightOwner));
    # print OUTFILE "(Last Updated $dateStamp)\n";
    my $filedate = $self->updated();
    if (length($filedate)) {
	    print OUTFILE "(Last Updated $filedate)\n";
    } else {
	    print OUTFILE "(Last Updated $dateStamp)\n";
    }
    print OUTFILE "</p>";
	print OUTFILE "</body></html>\n";
	close OUTFILE;
}

sub objGroup { # used for sorting
   my $obj1 = $a;
   my $obj2 = $b;
    return ($obj1->group() cmp $obj2->group());
}

sub objName { # used for sorting
   my $obj1 = $a;
   my $obj2 = $b;
   return ($obj1->name() cmp $obj2->name());
}

sub byLinkage { # used for sorting
    my $obj1 = $a;
    my $obj2 = $b;
    return ($obj1->linkageState() cmp $obj2->linkageState());
}

sub byAccessControl { # used for sorting
    my $obj1 = $a;
    my $obj2 = $b;
    return ($obj1->accessControl() cmp $obj2->accessControl());
}

sub linkageAndObjName { # used for sorting
   my $obj1 = $a;
   my $obj2 = $b;
   my $linkAndName1 = $obj1->linkageState() . $obj1->name();
   my $linkAndName2 = $obj2->linkageState() . $obj2->name();
   if ($HeaderDoc::sort_entries) {
        return ($linkAndName1 cmp $linkAndName2);
   } else {
        return byLinkage($obj1, $obj2); # (1 cmp 2);
   }
}

sub byMethodType { # used for sorting
   my $obj1 = $a;
   my $obj2 = $b;
   if ($HeaderDoc::sort_entries) {
	return ($obj1->isInstanceMethod() cmp $obj2->isInstanceMethod());
   } else {
	return (1 cmp 2);
   }
}

##################### Debugging ####################################

sub printObject {
    my $self = shift;
 
    print "------------------------------------\n";
    print "APIOwner\n";
    print "outputDir: $self->{OUTPUTDIR}\n";
    print "constantsDir: $self->{CONSTANTSDIR}\n";
    print "datatypesDir: $self->{DATATYPESDIR}\n";
    print "functionsDir: $self->{FUNCTIONSDIR}\n";
    print "methodsDir: $self->{METHODSDIR}\n";
    print "typedefsDir: $self->{TYPEDEFSDIR}\n";
    print "constants:\n";
    &printArray(@{$self->{CONSTANTS}});
    print "functions:\n";
    &printArray(@{$self->{FUNCTIONS}});
    print "methods:\n";
    &printArray(@{$self->{METHODS}});
    print "typedefs:\n";
    &printArray(@{$self->{TYPEDEFS}});
    print "structs:\n";
    &printArray(@{$self->{STRUCTS}});
    print "Inherits from:\n";
    $self->SUPER::printObject();
}

sub fixup_links
{
    my $self = shift;
    my $string = shift;
    my $mode = shift;
    my $ret = "";
    my $localDebug = 0;
    my $toplevel = 0;

    if ($mode > 1) {
	$mode = $mode - 2;
	$toplevel = 1;
    }

    my $linkprefix = "";
    my $count = $depth;
    while ($count) {
	$linkprefix .= "../";
	$count--;
    }
    $linkprefix =~ s/\/$//o;
    $string =~ s/\@\@docroot/$linkprefix/sgo;

    my @elements = split(/</, $string);
    foreach my $element (@elements) {
	if ($element =~ /^hd_link posstarget=\"(.*?)\">/o) {
	    # print "found.\n";
	    my $oldtarget = $1;
	    my $newtarget = $oldtarget;
	    my $prefix = $self->apiUIDPrefix();

	    if (!($oldtarget =~ /\/\/$prefix/)) {
		warn("link needs to be resolved.\n") if ($localDebug);
		warn("target is $oldtarget\n") if ($localDebug);
		$newtarget = resolveLink($oldtarget);
		warn("new target is $newtarget\n") if ($localDebug);
	    }

	    # print "element is $element\n";
	    $element =~ s/^hd_link.*?>\s?//o;
	    # print "link name is $element\n";
	    if ($mode) {
		if ($newtarget =~ /logicalPath=\".*\"/o) {
			$ret .= "<hd_link $newtarget>";
		} else {
			$ret .= "<hd_link logicalPath=\"$newtarget\">";
		}
		$ret .= $element;
		# $ret .= "</hd_link>";
	    } else {
		# if ($newtarget eq $oldtarget) {
		    $ret .= "<!-- a logicalPath=\"$newtarget\" -->";
		    $ret .= $element;
		    # $ret .= "<!-- /a -->";
		# } else {
		    # if ($toplevel) {
			# $ret .= "<a href=\"CompositePage.html#$newtarget\">";
		    # } else {
			# $ret .= "<a href=\"../CompositePage.html#$newtarget\">";
		    # }
		    # $ret .= $element;
		    # $ret .= "</a>\n";
		# }
	    }
	} else {
	    if ($element =~ s/^\/hd_link>//o) {
		if ($mode) {
		    $ret .= "</hd_link>";
		} else {
		    $ret .= "<!-- /a -->";
		}
		$ret .= $element;
	    } else {
		$ret .= "<$element";
	    }
	}
    }
    $ret =~ s/^<//o;

    return $ret;
}

sub toplevel_html_fixup_links
{
    my $self = shift;
    my $string = shift;
    my $resolver_output = fixup_links($self, $string, 2);

    return $resolver_output;
}

sub html_fixup_links
{
    my $self = shift;
    my $string = shift;
    my $resolver_output = fixup_links($self, $string, 0);

    return $resolver_output;
}

sub xml_fixup_links
{
    my $self = shift;
    my $string = shift;
    my $resolver_output = fixup_links($self, $string, 1);

    return $resolver_output;
}

1;

