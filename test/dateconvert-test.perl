#!/usr/bin/perl
# $Clovery: tiarra/test/dateconvert-test.perl,v 1.2 2003/07/27 06:51:35 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# This perl script for testing System::DateConvert module.
#   please run on Tiarra Root Directory.
#     ex. perl test/dateconvert-test.perl

use strict;
use warnings;
use lib qw(module);

my $testdata = 
"
A:%A
a:%a
B:%B
b:%b
h:%h
C:%C
c:%c
D:%D
d:%d
e:%e
F:%F
G:%G
g:%g
H:%H
I:%I
j:%j
k:%k
l:%l
M:%M
m:%m
n:%n
p:%p
R:%R
r:%r
S:%S
s:%s
T:%T
t:%t
U:%U
u:%u
V:%V
W:%W
w:%w
X:%X
x:%x
Y:%Y
y:%y
Z:%Z
z:%z
:%%
";

sub main {
    my $time = time();
    use Data::Dumper;
    my @mine;
    my @posix;
    use Tools::DateConvert qw(PurePerl);
	{
	    @mine = split(/\n/, Tools::DateConvert::replace($testdata, $time));
	}
	eval qq{
	    no Tools::DateConvert qw(PurePerl);
	    #use Tools::DateConvert;
	    \@posix = split(/\n/, Tools::DateConvert::replace(\$testdata, \$time));
	};

    print "diffing....\n";
    while (1) {
	my ($posix) = shift(@posix);
	my ($mine) = shift(@mine);

	last if (!defined $posix) && (!defined $mine);
	if ($posix ne $mine) {
	    print <<"END";
POSIX:  $posix
MINE :  $mine
END
	    if ($mine =~ /^[GgV]:$/) {
		print "STAT :  this diff is ok...\n";
	    } else {
		print "STAT :  this diff is ERROR...\n";
	    }
	}
    }

    return 0;
}

exit main();
