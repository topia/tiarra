#!/usr/opt/bin/perl
# $Id$
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

use strict;
use warnings;

my $incpath;

if ($0 =~ /^(.*)[\\\/][^\\\/]*$/) {
    $incpath = $1;
} else {
    $incpath = '.';
}

exec $^X, "-wt", "$incpath/tiarra", @ARGV;
#exec $^X, "-w", "-I$incpath/main", "-I$incpath/module", "$incpath/tiarra", @ARGV;
#exec $^X, "-w", "-d:DProf", "-I$incpath/main", "-I$incpath/module", "$incpath/tiarra", @ARGV;
