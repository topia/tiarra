# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Definition Enum Mixin
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::DefineEnumMixin;
use strict;
use warnings;
use Tiarra::Utils;
use base qw(Tiarra::Utils);


# usage:
#  use Tiarra::DefineEnumMixin qw(enum1 enum2 enum3...);

# this import is equivalent as:
#   BEGIN {
#     use Tiarra::Utils;
#     Tiarra::Utils->define_enum(qw(enum1 enum2 enum3...);
#   }

sub import {
    my $pkg = shift;
    local $Tiarra::Utils::ExportLevel;
    ++$Tiarra::Utils::ExportLevel;

    $pkg->define_enum(@_);
}

1;
