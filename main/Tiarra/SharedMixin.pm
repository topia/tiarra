# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Shared Instance(Singleton) Mixin
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::SharedMixin;
use strict;
use warnings;
use Tiarra::Utils;
use base qw(Tiarra::Utils);
our $ExportLevel = 0;


# usage:
#  use Tiarra::SharedMixin qw(shared shared_module);
#  our $_shared_instance; # optional, but useful for documentation.
#  sub _new {
#      my $class = shift;
#      my ($this) = {};
#      bless $this, $class;
#      #__PACKAGE__->shared->some_func; # can't use
#      return $this;
#  }
#  sub _initialize { # optional
#      my $this = shift;
#      __PACKAGE__->shared->some_func; # OK
#  }

# use $_shared_instance variable.
# import shared and _this functions.

sub import {
    my $pkg = shift;
    my $call_pkg = caller($ExportLevel);
    my $instance_name = $call_pkg.'::_shared_instance';
    if ($#_ != 0) {
	push(@_, 'shared');
    }
    my @funcnames = @_;

    no strict 'refs';

    $pkg->define_function(
	$call_pkg,
	sub {
	    my $class = shift;
	    ${$instance_name} = $call_pkg->_new(@_);
	    $pkg->define_function(
		$call_pkg,
		sub () { ${$instance_name} },
		@funcnames);
	    eval {
		# safe initialize with ->shared.
		${$instance_name}->_initialize(@_);
	    };
	    ${$instance_name};
	},
	@funcnames);

    $pkg->define_function(
	$call_pkg,
	\&Tiarra::Utils::_this,
	'_this');
}

1;
