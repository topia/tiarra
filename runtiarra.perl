#!/usr/opt/bin/perl
# $Clovery: tiarra/runtiarra.perl,v 1.3 2003/07/24 02:37:40 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

use strict;
use warnings;

my $incpath;

if ($0 =~ /^(.*)[\\\/][^\\\/]*$/) {
    $incpath = $1;
} else {
    $incpath = '.';
}

exec $^X, "-w", "$incpath/tiarra", @ARGV;
#exec $^X, "-w", "-I$incpath/main", "-I$incpath/module", "$incpath/tiarra", @ARGV;
#exec $^X, "-w", "-d:DProf", "-I$incpath/main", "-I$incpath/module", "$incpath/tiarra", @ARGV;
