# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Define Helper Utilities
# -----------------------------------------------------------------------------
# copyright (C) 2004-2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils::DefineHelper;
use strict;
use warnings;
use base qw(Tiarra::Utils::Core);
our $ExportLevel = 0;

# please do {
#     Tiarra::Utils::DefineHelper->do_with_define_exportlevel(
#         0,
#         sub {
#             Tiarra::Utils::DefineHelper->define_enum(qw(...));
#         });
# in define_*s' wrapper function.


=head1 NAME

Tiarra::Utils::DefineHelper - Tiarra misc Utility Functions: Define Helper

=head1 SYNOPSIS

  use Tiarra::Utils; # import master

=head1 DESCRIPTION

Tiarra::Utils is misc helper functions class. this class is implement define
helpers. (accessors, proxys, ...)

class splitting is maintainer issue only. please require/use Tiarra::Utils.

all function is class method; please use package->method(...);

maybe all functions can use with utils->...

=head1 METHODS

=over 4

=cut

=item define_function

  utils->define_function($package, $code, @funcnames)

define function with some package, code, funcnames.

=over 4

=item * $package

package name. such as C<< utils->get_package($some_level) >>.

=item * $code

coderef(closure) of function. such as C<< sub { shift->foo_func('bar') } >>.

=item * @funcnames

function names to define.

=back

=cut

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

=item define_attr_accessor

  utils->define_attr_accessor($class_method_p, @defines)

define attribute accessor.

=over 4

=item * $class_method_p

these accessor is called as class method, pass true; otherwise false.

=item * @defines

accessor defines array.

=over 4

=item * scalar value ($valname)

define ->$valname for accessor of ->{$valname}.

=item * array ref value ([$funcname, $valname])

define ->$funcname for accessor of ->{$valname}.

=back

=back

=cut

sub define_attr_accessor {
    shift->_define_attr_common('accessor', @_);
}

=item define_attr_getter

  utils->define_attr_getter($class_method_p, @defines)

define attribute getter.

all params is same as L</define_attr_accessor>, except s/accessor/getter/.

=cut

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

=item define_array_attr_accessor

  utils->define_attr_accessor($class_method_p, @defines)

define attribute accessor for array type object.

=over 4

=item * $class_method_p

these accessor is called as class method, pass true; otherwise false.

=item * @defines

accessor defines array.

=over 4

=item * scalar value (value)

define ->value for accessor of ->[VALUE].

example: ->define_attr

=item * array ref value ([$funcname, $valname])

define ->$funcname for accessor of ->{$valname}.

=back

=back

=cut

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
    # this function is deprecated.
    # please use enum.pm instead.
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
		   ' die "too many args: @_" if $#_ >= ',
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
		   ' die "too many args: @_" if $#_ >= 2;',
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

__END__
=back

=head1 SEE ALSO

L<Tiarra::Utils>

=head1 AUTHOR

Topia E<lt>topia@clovery.jpE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Topia.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
