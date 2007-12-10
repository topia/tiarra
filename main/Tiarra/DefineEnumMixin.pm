# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Definition Enum Mixin
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::DefineEnumMixin;
use strict;
use warnings;
use Tiarra::Utils::DefineHelper;
use base qw(Tiarra::Utils::DefineHelper);


# usage:
#  use Tiarra::DefineEnumMixin qw(enum1 enum2 enum3...);

# this import is equivalent as:
#   BEGIN {
#     use Tiarra::Utils;
#     Tiarra::Utils->define_enum(qw(enum1 enum2 enum3...);
#   }

# this module is deprecated.
# please use enum.pm instead.

sub import {
    my $pkg = shift;
    my @args = @_;
    $pkg->do_with_define_exportlevel(
	0,
	sub {
	    $pkg->define_enum(@args);
	});
}

1;
