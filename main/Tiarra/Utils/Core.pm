# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Tiarra::Utils Core feature
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils::Core;
use strict;
use warnings;

sub shared {
    # don't need instance present
    return shift;
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
