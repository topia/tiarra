# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Define Helper Utilities
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils::DefineHelper;
use strict;
use warnings;
use Tiarra::Utils::Core;
use base qw(Tiarra::Utils::Core);
our $ExportLevel = 0;

# please do {
#     Tiarra::Utils::DefineHelper->do_with_define_exportlevel(
#         0,
#         sub {
#             Tiarra::Utils::DefineHelper->define_enum(qw(...));
#         });
# in define_*s' wrapper function.

# all function is class method.
# please use package->method(...);
# maybe all functions can use with Tiarra::Utils->...

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

sub _define_attr_common {
    my $pkg = shift;
    my $type = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package(1);
    foreach (@_) {
	my ($funcname, $valname) = @{$pkg->_parse_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    $pkg->_generate_attr_closure($class_method_p, $type,
					 "{$valname}", $funcname),
	    $funcname);
    }
    undef;
}

sub define_attr_accessor {
    shift->_define_attr_common('accessor', @_);
}

sub define_attr_getter {
    shift->_define_attr_common('getter', @_);
}

sub _define_attr_hook_common {
    my $pkg = shift;
    my $type = shift;
    my $class_method_p = shift;
    my $hook = shift;
    my $call_pkg = $pkg->get_package(1);
    foreach (@_) {
	my ($funcname, $valname) = @{$pkg->_parse_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    $pkg->_generate_attr_hooked_closure($class_method_p, $type,
						"{$valname}", $hook, $funcname),
	    $funcname);
    }
    undef;
}

sub _define_attr_translate_accessor {
    shift->_define_attr_hook_common('translate', @_);
}

sub _define_attr_notify_accessor {
    shift->_define_attr_hook_common('notify', @_);
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

sub _define_array_attr_common {
    my $pkg = shift;
    my $type = shift;
    my $class_method_p = shift;
    my $call_pkg = $pkg->get_package(1);
    foreach (@_) {
	my ($funcname, $index) =
	    @{$pkg->_parse_array_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    $pkg->_generate_attr_closure($class_method_p, $type,
					 "[$index]", $funcname),
	    $funcname);
    }
    undef;
}

sub define_array_attr_accessor {
    shift->_define_array_attr_common('accessor', @_);
}

sub define_array_attr_getter {
    shift->_define_array_attr_common('getter', @_);
}

sub _define_array_attr_hook_common {
    my $pkg = shift;
    my $type = shift;
    my $class_method_p = shift;
    my $hook = shift;
    my $call_pkg = $pkg->get_package(1);
    foreach (@_) {
	my ($funcname, $index) =
	    @{$pkg->_parse_array_attr_define($call_pkg, $_)};
	$pkg->define_function(
	    $call_pkg,
	    $pkg->_generate_attr_hooked_closure($class_method_p, $type,
						"[$index]", $hook, $funcname),
	    $funcname);
    }
    undef;
}

sub define_array_attr_translate_accessor {
    shift->_define_array_attr_hook_common('translate', @_);
}

sub define_array_attr_notify_accessor {
    shift->_define_array_attr_hook_common('notify', @_);
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
	    eval '(sub {
		 my $this = shift;
		 $this->$attr_name($value) if defined shift;
		 $this->$attr_name '.$match_type.' $value;
	     })',
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
    ($pkg->get_caller($caller_level + 1))[0];
}

sub get_caller {
    my $pkg = shift;
    my $caller_level = shift || 0;
    caller($caller_level + 1 + $ExportLevel);
}

sub do_with_define_exportlevel {
    my $pkg = shift;
    my $level = shift || 0;

    local $ExportLevel;
    $ExportLevel += 3 + $level;
    shift->(@_);
}


# generator
sub _generate_attr_closure {
    my $pkg = shift;
    my $class_method_p = shift;
    my $type = shift;
    my $attr = shift;
    my $funcname = shift;
    # outside parentheses for context
    my $str = join('',
		   "\n# line 1 \"",
		   (defined $funcname ? "->$funcname\: " : ''),
		   "attr $type\"\n",
		   '(sub',
		   ({
		       accessor => ' : lvalue',
		       getter   => '',
		   }->{$type}),
		   ' {',
		   ' die "too many args" if $#_ >= ',
		   ({
		       accessor => '2',
		       getter   => '1',
		   }->{$type}),
		   ';',
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
    no strict 'refs';
    no warnings;
    eval $str ||
	(print STDERR __PACKAGE__."/generator error: \n$str\n$@", undef);
}

sub _generate_attr_hooked_closure {
    my $pkg = shift;
    my $class_method_p = shift;
    my $type = shift;
    my $attr = shift;
    my $update_hook = shift;
    my $funcname = shift;
    # outside parentheses for context
    my $str = join('',
		   "\n# line 1 \"",
		   (defined $funcname ? "->$funcname\: " : ''),
		   "attr $type\"\n",
		   '(sub {',
		   ' die "too many args" if $#_ >= 2;',
		   ' my $this = shift',
		   ($class_method_p ? '->_this' : ''),
		   ';',
		   ' if ($#_ >=0) {',
		   (sub {
			if ($type eq 'translate') {
			    '  '.$update_hook->('shift', "\$this->$attr");
			} elsif ($type eq 'notify') {
			    "  \$this->$attr = shift; $update_hook;";
			}
		    }->($type)),
		   ' }',
		   " \$this->$attr;",
		   ' })');
    no strict 'refs';
    no warnings;
    eval $str ||
	(print STDERR __PACKAGE__."/generator error: \n$str\n$@", undef);
}


1;
