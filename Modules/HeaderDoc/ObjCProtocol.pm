#! /usr/bin/perl -w
#
# Class name: ObjCProtocol
# Synopsis: Holds comments pertaining to an ObjC protocol, as parsed by HeaderDoc
# from an objC header
#
# Initial modifications: SKoT McDonald <skot@tomandandy.com> Aug 2001
#
# Based on CPPClass by Matt Morse (matt@apple.com)
# Last Updated: $Date: 2004/06/10 22:12:16 $
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
BEGIN {
	foreach (qw(Mac::Files)) {
	    $MOD_AVAIL{$_} = eval "use $_; 1";
    }
}
package HeaderDoc::ObjCProtocol;

use HeaderDoc::Utilities qw(findRelativePath safeName getAPINameAndDisc printArray printHash);
use HeaderDoc::ObjCContainer;

# Inheritance
@ISA = qw( HeaderDoc::ObjCContainer );

use strict;
use vars qw($VERSION @ISA);
$VERSION = '1.20';

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
my $tracing = 0;
my $outputExtension = ".html";
my $tocFrameName = "toc.html";
# my $theTime = time();
# my ($sec, $min, $hour, $dom, $moy, $year, @rest);
# ($sec, $min, $hour, $dom, $moy, $year, @rest) = localtime($theTime);
# $moy++;
# $year += 1900;
# my $dateStamp = "$moy/$dom/$year";
######################################################################

sub _initialize {
    my($self) = shift;
    $self->SUPER::_initialize();
    $self->tocTitlePrefix('Protocol:');
    $self->{CLASS} = "HeaderDoc::ObjCProtocol";
}

sub getMethodType {
	return "intfm";
}

# we add the apple_ref markup to the navigator comment to identify
# to Project Builder and other applications indexing the documentation
# that this is the entry point for documentation for this protocol
sub docNavigatorComment {
    my $self = shift;
    my $name = $self->name();
    $name =~ s/;//sgo;
    my $uid = $self->apiuid("intf"); # "//apple_ref/occ/intf/$name";
    my $navComment = "<!-- headerDoc=intf; uid=$uid; name=$name-->";
    my $appleRef = "<a name=\"$uid\"></a>";
    
    return "$navComment\n$appleRef";
}

################## Misc Functions ###################################
sub objName { # used for sorting
    my $obj1 = $a;
    my $obj2 = $b;
    return ($obj1->name() cmp $obj2->name());
}

1;

