# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Misc Utilities
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils;
use strict;
use warnings;
use Tiarra::SharedMixin;

# all function is class method.
# please use package->method(...);

sub _new {
    # don't need instance present
    return shift;
}

sub to_str {
    shift; # drop
    # undef(and so on) to str without warning
    no warnings 'uninitialized';
    return map {
	"$_"
    } @_;
}

sub get_first_defined {
    shift; # drop
    foreach (@_) {
	return $_ if defined $_;
    }
    return undef;
}

1;
