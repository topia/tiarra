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

sub _generate_attr_closure {
    my $pkg = shift;
    my $class_method_p = shift;
    my $type = shift;
    my $attr = shift;
    # outside parentheses for context
    my $str = join('',
	      '(sub',
	      ({
		  accessor => ' : lvalue',
		  getter   => '',
	      }->{$type}),
	      ' {',
	      ({
		  accessor => ' my $this = shift',
		  getter   => ' shift',
	      }->{$type}),
	      ($class_method_p ? '->_this' : ''),
	      ({
		  accessor => "; \$this->$attr = shift if \$#_ >= 0; \$this",
		  getter   => '',
	      }->{$type}),
	      "->$attr;",
	      ' })');
    eval $str;
}

sub define_attr_accessor {
    my $pkg = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package;
    foreach (@_) {
	my ($funcname, $valname) = @{$pkg->_parse_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    $pkg->_generate_attr_closure($class_method_p, 'accessor',
					 "{$valname}"),
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
	    $pkg->_generate_attr_closure($class_method_p, 'getter',
					 "{$valname}"),
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
	    $pkg->_generate_attr_closure($class_method_p, 'accessor',
					 "[$index]"),
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
	    $pkg->_generate_attr_closure($class_method_p, 'getter',
					 "[$index]"),
	    $funcname);
    }
}

sub define_attr_enum_accessor {
    my $pkg = shift;
    my $attr_name = shift;
    my $match_type = shift || 'eq';
    foreach (@_) {
	my ($funcname, $value);
	if (ref($_) eq 'ARRAY') {
	    $funcname = $_->[0];
	    $value = $_->[1];
	} else {
	    $funcname = $attr_name . '_' . $_;
	    $value = $_;
	}
	$pkg->define_function(
	    $pkg->get_package,
	    eval 'sub {
		 my $this = shift;
		 $this->$attr_name($value) if defined shift;
		 $this->$attr_name '.$match_type.' $value;
	     }',
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

sub simple_caller_formatter {
    my $pkg = shift;
    my $msg = $pkg->get_first_defined(shift, 'called');
    my $caller_level = shift || 0;

    sprintf('%s at %s line %s', $msg,
	    (caller($caller_level + 1 + $ExportLevel))[1,2]);
}

# utilities

sub cond_yesno {
    shift; # drop
    my ($value, $default) = @_;

    return $default || 0 unless defined $value;
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # ����Ƚ��
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
    return ();
}

sub _wantarray_to_type {
    shift; # drop

    grep {
	if (!wantarray) {
	    return $_;
	} else {
	    $_;
	}
    } map {
	if (!defined $_) {
	    'void';
	} elsif (!$_) {
	    'scalar';
	} else {
	    'list';
	}
    } @_;
}
sub call_with_wantarray {
    my $class_or_this = shift;
    my ($wantarray, $closure, @args) = @_;
    my $type = $class_or_this->_wantarray_to_type($wantarray);

    if ($type eq 'void') {
	# void context
	$closure->(@args);
	return undef;
    } elsif ($type eq 'scalar') {
	# scalar context
	my $ret = $closure->(@args);
	return $ret;
    } elsif ($type eq 'list') {
	# list context
	my $ret = [$closure->(@args)];
	return @$ret;
    } else {
	croak "unsupported wantarray type: $type";
    }
}

sub do_with_ensure {
    my $pkg = shift;
    my ($closure, $ensure, @args) = @_;
    my $retval;
    my $type = $pkg->_wantarray_to_type(wantarray);

    do {
	my $die = $pkg->sighandler_or_default('die');
	local $SIG{__DIE__} = sub {
	    local $SIG{__DIE__} = $die;
	    if (!$^S) {
		# outside eval (FIXME, but without false-positive die)
		$pkg->do_with_errmsg('ensure/die',
				     $ensure, undef, @_);
	    }
	    die(@_);
	};
	$retval = [$closure->(@args)];
    };
    $pkg->do_with_errmsg('ensure',
			 $ensure, $retval);
    if ($type eq 'scalar') {
	return $retval->[0];
    } else {
	return @$retval;
    }
}

sub sighandler_or_default {
    my ($pkg, $name, $func) = @_;

    $name = "__\U$name\E__" if $name =~ /^(die|warn)$/i;
    if (!defined $func) {
	if ($name =~ /^__(DIE|WARN)__$/) {
	    no strict 'refs';
	    $func = \&{"CORE::GLOBAL::\L$1\E"};
	}
    }

    my $value = $SIG{$name};
    $value = $func if !defined $value || length($value) == 0 ||
	$value =~ /^DEFAULT$/i;
    if (ref($value) ne 'CODE') {
	no strict 'refs';
	$value = \&{$value};
    }
    $value;
}

sub _add_lf {
    my $pkg = shift;

    my $str = join('', $pkg->to_str(@_));
    if ($str !~ /\n\z/) {
	"$str\n";
    } else {
	$str;
    }
}

sub do_with_errmsg {
    my $pkg = shift;
    my ($name, $closure, @args) = @_;

    my $str = "    inside $name;\n";
    do {
	no strict 'refs';
	local ($SIG{__WARN__}, $SIG{__DIE__}) =
	    (map {
		my $signame = "__\U$_\E__";
		my $handler = $pkg->sighandler_or_default($_, 'DEFAULT');
		sub {
		    $handler->($pkg->_add_lf(@_).$str);
		};
	    } qw(warn die));

	$closure->(@args);
    };

}

1;
