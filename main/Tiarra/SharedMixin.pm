# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Shared Instance Mixin
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::SharedMixin;
use strict;
use warnings;
our $ExportLevel = 0;

# use $_shared_instance variable.
# import shared and _this functions.

sub import {
    my $pkg = shift;
    my $call_pkg = caller($ExportLevel);
    my $instance_name = $call_pkg.'::_shared_instance';

    no strict 'refs';
    *{$call_pkg.'::shared'} = sub {
	if (!defined ${$instance_name}) {
	    ${$instance_name} = $call_pkg->_new;
	    eval {
		# safe initialize with ->shared.
		${$instance_name}->_initialize;
	    };
	}
	${$instance_name};
    };
    *{$call_pkg.'::_this'} = \&_this;
}

sub _this {
    my $class_or_this = shift;

    if (!ref($class_or_this)) {
	# fetch shared
	$class_or_this = $class_or_this->shared;
    }

    return $class_or_this;
}

1;

