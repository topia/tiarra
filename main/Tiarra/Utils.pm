# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Misc Utilities
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils;
use strict;
use warnings;
use Carp;
use Tiarra::Utils::Core;
use base qw(Tiarra::Utils::Core);
use Tiarra::Utils::DefineHelper;
use base qw(Tiarra::Utils::DefineHelper);
use Tiarra::Utils::CallWrapper;
use base qw(Tiarra::Utils::CallWrapper);

sub simple_caller_formatter {
    my $pkg = shift;
    my $msg = $pkg->get_first_defined(shift, 'called');
    my $caller_level = shift || 0;

    sprintf('%s at %s line %s', $msg,
	    ($pkg->get_caller($caller_level + 1))[1,2]);
}

# utilities

sub cond_yesno {
    shift; # drop
    my ($value, $default) = @_;

    return $default || 0 unless defined $value;
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # øÙ√Õ»ΩƒÍ
    return 0;
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
    return ();
}

1;
