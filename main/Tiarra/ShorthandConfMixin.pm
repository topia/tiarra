# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Shorthand writing conf Mixin
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::ShorthandConfMixin;
use strict;
use warnings;
use Exporter;
use base qw(Exporter);
our @EXPORT = qw(_conf _conf_general _conf_networks _conf_messages);

# usage:
#  use Tiarra::ShorthandConfMixin;
#  use base qw(Tiarra::ShorthandConfMixin)

# use _runloop function.

# shorthand for Configuration->shared->...
sub _conf { shift->_runloop->{conf}; }
sub _conf_general { shift->_conf->general; }
sub _conf_networks { shift->_conf->networks; }
sub _conf_messages { shift->_conf_general->messages; }

1;
