# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Modified Flag Mixin
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::ModifiedFlagMixin;
use strict;
use warnings;
use Tiarra::Utils;
use Exporter;
use base qw(Exporter);
our @EXPORT = qw(set_modified clear_modified modified);

# usage:
#  use Tiarra::ModifiedFlagMixin;

Tiarra::Utils->define_attr_accessor(0, qw(modified));

sub set_modified   { shift->modified(1); }
sub clear_modified { shift->modified(0); }

1;
