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

sub cond_yesno {
    shift; # drop
    my ($value, $default) = @_;

    return $default || 0 unless defined $value;
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # ¿ôÃÍÈ½Äê
    return 0;
}

1;
