# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Misc Utilities
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils;
use strict;
use warnings;
our $ExportLevel = 0;

# please do { local $Tiarra::Utils::ExportLevel; ++$Tiarra::Utils::ExportLevel; }
# in define_*s' wrapper function.

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

sub _parse_attr_define {
    shift; # drop
    shift; # drop
    my $value = shift;

    if (ref($value) eq 'ARRAY') {
	$value;
    } else {
	[$value, $value];
    }
}

sub define_attr_accessor {
    my $pkg = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package;
    foreach (@_) {
	my ($funcname, $valname) = @{$pkg->_parse_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    ($class_method_p ? sub : lvalue {
		 my ($class_or_this, $value) = @_;
		 my $this = $class_or_this->_this;
		 $this->{$valname} = $value if $#_ >= 1;
		 $this->{$valname};
	     } : sub : lvalue {
		 my ($this, $value) = @_;
		 $this->{$valname} = $value if $#_ >= 1;
		 $this->{$valname};
	     }),
	    $funcname);
    }
    undef;
}

sub define_attr_getter {
    my $pkg = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package;
    foreach (@_) {
	my ($funcname, $valname) = @{$pkg->_parse_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    ($class_method_p ? sub {
		 shift->_this->{$valname};
	     } : sub {
		 shift->{$valname};
	     }),
	    $funcname);
    }
}

sub define_attr_setter {
    my $pkg = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package;
    foreach (@_) {
	my ($funcname, $valname) = @{$pkg->_parse_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    ($class_method_p ? sub {
		 shift->_this->{$valname} = shift;
	     } : sub {
		 shift->{$valname} = shift;
	     }),
	    $funcname);
    }
}

sub _parse_array_attr_define {
    shift; # drop
    my $call_pkg = shift;

    my $value = shift;
    if (ref($value) eq 'ARRAY') {
	$value;
    } else {
	my $funcname = $value;
	my $index = uc($funcname);
	$index = $call_pkg->$index;
	[$funcname, $index];
    }
}

sub define_array_attr_accessor {
    my $pkg = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package;
    foreach (@_) {
	my ($funcname, $index) =
	    @{$pkg->_parse_array_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    ($class_method_p ? sub : lvalue {
		 my ($class_or_this, $value) = @_;
		 my $this = $class_or_this->_this;
		 $this->[$index] = $value if $#_ >= 1;
		 $this->[$index];
	     } : sub : lvalue {
		 my ($this, $value) = @_;
		 $this->[$index] = $value if $#_ >= 1;
		 $this->[$index];
	     }),
	    $funcname);
    }
    undef;
}

sub define_array_attr_getter {
    my $pkg = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package;
    foreach (@_) {
	my ($funcname, $index) =
	    @{$pkg->_parse_array_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    ($class_method_p ? sub {
		 shift->_this->[$index];
	     } : sub {
		 shift->[$index];
	     }),
	    $funcname);
    }
}

sub define_array_attr_setter {
    my $pkg = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package;
    foreach (@_) {
	my ($funcname, $index) =
	    @{$pkg->_parse_array_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    ($class_method_p ? sub {
		 shift->_this->[$index] = shift;
	     } : sub {
		 shift->[$index] = shift;
	     }),
	    $funcname);
    }
}

sub define_proxy {
    my $pkg = shift;
    my $proxy_target_funcname = shift;
    my $class_method_p = shift;
    foreach (@_) {
	my ($funcname, $proxyname);
	if (ref($_) eq 'ARRAY') {
	    $funcname = $_->[0];
	    $proxyname = $_->[1];
	} else {
	    $funcname = $proxyname = $_;
	}
	$pkg->define_function(
	    $pkg->get_package,
	    ($class_method_p ? sub {
		 shift->_this->$proxy_target_funcname->$proxyname(@_);
	     } : sub {
		 shift->$proxy_target_funcname->$proxyname(@_);
	     }),
	    $funcname);
    }
}

sub define_enum {
    my $pkg = shift;
    my $i = 0;
    foreach (@_) {
	my (@funcnames);
	if (ref($_) eq 'ARRAY') {
	    @funcnames = @$_;
	} else {
	    @funcnames = $_;
	}
	$pkg->define_function(
	    $pkg->get_package,
	    sub () { $i; },
	    @funcnames);
	++$i;
    }
}

sub get_package {
    my $pkg = shift;
    my $caller_level = shift || 0;
    (caller($caller_level + 1 + $ExportLevel))[0];
}

# utilities

sub cond_yesno {
    shift; # drop
    my ($value, $default) = @_;

    return $default || 0 unless defined $value;
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # ¿ôÃÍÈ½Äê
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

sub call_with_wantarray {
    shift; # drop
    my ($wantarray, $closure, @args) = @_;

    if (!defined $wantarray) {
	# void context
	$closure->(@args);
	return undef;
    } elsif (!$wantarray) {
	# scalar context
	my $ret = $closure->(@args);
	return $ret;
    } else {
	# list context
	my $ret = [$closure->(@args)];
	return @$ret;
    }
}

sub do_with_ensure {
    shift; # drop
    my ($closure, $ensure, @args) = @_;
    my $retval;

    eval {
	$retval = [$closure->(@args)];
    };
    my $error = $@;
    $ensure->($retval, $error);
    if ($error) {
	die $error;
    } else {
	return @$retval;
    }
}

1;
