# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Misc Utilities
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils;
use strict;
use warnings;

# can't use; because this module referred by SharedMixin.
#use Tiarra::SharedMixin;


# all function is class method.
# please use package->method(...);

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

sub define_function {
    shift; #package
    my $package = shift;
    my $code = shift;
    my $funcname;
    no strict 'refs';
    foreach (@_) {
	$funcname = $package.'::'.$_;
	undef *{$funcname};
	*{$funcname} = $code;
    }
    undef;
}

sub define_attr_accessor {
    my $pkg = shift;
    my $class_method = shift;
    foreach (@_) {
	my ($valname, $funcname);
	if (ref($_) eq 'ARRAY') {
	    $funcname = $_->[0];
	    $valname = $_->[1];
	} else {
	    $funcname = $valname = $_;
	}
	$pkg->define_function(
	    $pkg->get_package,
	    ($class_method ? sub {
		 my ($class_or_this, $value) = @_;
		 my $this = $class_or_this->_this;
		 $this->{$valname} = $value if defined $value;
		 return $this->{$valname};
	     } : sub {
		 my ($this, $value) = @_;
		 $this->{$valname} = $value if defined $value;
		 return $this->{$valname};
	     }),
	    $funcname);
    }
    undef;
}

sub define_attr_getter {
    my $pkg = shift;
    my $class_method = shift;
    foreach (@_) {
	my ($valname, $funcname);
	if (ref($_) eq 'ARRAY') {
	    $funcname = $_->[0];
	    $valname = $_->[1];
	} else {
	    $funcname = $valname = $_;
	}
	$pkg->define_function(
	    $pkg->get_package,
	    ($class_method ? sub {
		 shift->_this->{$valname};
	     } : sub {
		 shift->{$valname};
	     }),
	    $funcname);
    }
}

sub define_attr_setter {
    my $pkg = shift;
    my $class_method = shift;
    foreach (@_) {
	my ($valname, $funcname);
	if (ref($_) eq 'ARRAY') {
	    $funcname = $_->[0];
	    $valname = $_->[1];
	} else {
	    $funcname = $valname = $_;
	}
	$pkg->define_function(
	    $pkg->get_package,
	    ($class_method ? sub {
		 shift->_this->{$valname} = shift;
	     } : sub {
		 shift->{$valname} = shift;
	     }),
	    $funcname);
    }
}

sub get_package {
    my $pkg = shift;
    my $caller_level = shift || 0;
    (caller($caller_level + 1))[0];
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
    return undef;
}

1;
