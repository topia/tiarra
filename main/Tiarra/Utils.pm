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
use Exporter;
use base qw(Exporter);
our @EXPORT = qw(utils);

sub utils {
    __PACKAGE__->shared;
}

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

    return $default unless defined $value;
    return 0 if $value =~ /[fn]/i; # false/no
    return 1 if $value =~ /[ty]/i; # true/yes
    return 1 if $value; # øÙ√Õ»ΩƒÍ
    return 0;
}

sub to_str {
    shift; # drop
    # undef(and so on) to str without warning
    no warnings 'uninitialized';
    grep {
	if (!wantarray) {
	    return $_;
	} else {
	    1;
	}
    } map {
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

sub to_ordinal_number {
    shift; # drop
    grep {
	if (!wantarray) {
	    return $_;
	} else {
	    1;
	}
    } map {
	if (/1$/) {
	    $_ . 'st';
	} elsif (/(?:[^1]|^)([23])$/) {
	    $_ . ($2 eq '2' ? 'nd' : 'rd');
	} else {
	    $_ . 'th';
	}
    } @_;
}

1;
