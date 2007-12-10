# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Call Wrapping Helper
# -----------------------------------------------------------------------------
# copyright (C) 2004-2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils::CallWrapper;
use strict;
use warnings;
use Carp;
use base qw(Tiarra::Utils::Core);

=head1 NAME

Tiarra::Utils::CallWrapper - Tiarra misc Utility Functions: Call Wrappers

=head1 SYNOPSIS

  use Tiarra::Utils; # import master
  utils->do_with_ensure(..., ...);

=head1 DESCRIPTION

Tiarra::Utils is misc helper functions class. this class is implement call
wrapping helpers.

class splitting is maintainer issue only. please require/use Tiarra::Utils.

=head1 METHODS

=over 4

=cut

sub _wantarray_to_type {
    shift; # drop

    grep {
	if (!wantarray) {
	    return $_;
	} else {
	    1;
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

=item call_with_wantarray

  utils->call_with_wantarray(wantarray, $closure, @args);

call closure with wantarray value of you want.

=over 4

=item * wantarray

wantarray value at context.

=item * $closure

closure of want to call.

=item * @args

args to call closure.

=back

=cut

sub call_with_wantarray {
    my $pkg = shift;
    my ($wantarray, $closure, @args) = @_;
    my $type = $pkg->_wantarray_to_type($wantarray);

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

=item do_with_ensure

  utils->do_with_ensure($closure, $ensure, @args);

call closure with ensure feature.

=over 4

=item * $closure

closure of want to call.

=item * $ensure

ensure closure (call on return/exit from this function).

=item * @args

args to call closure.

=back

=cut

sub do_with_ensure {
    my $pkg = shift;
    my ($closure, $ensure, @args) = @_;
    my $cleaner = Tiarra::Utils::CallWrapper::EnsureCleaner->new($ensure);
    $closure->(@args);
}

=item sighandler_or_default

  utils->sighandler_or_default($name[, $func]);

return coderef of current signal handler.

=cut

sub sighandler_or_default {
    my ($pkg, $name, $func) = @_;

    $name = "__\U$name\E__" if $name =~ /^(die|warn)$/i;
    if (!defined $func) {
	if ($name =~ /^__(DIE|WARN)__$/) {
	    no strict 'refs';
	    $func = \&{"__real_\L$1\E"};
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

sub __real_die  { die  @_ }
sub __real_warn { warn @_ }

=item do_with_errmsg

  utils->do_with_errmsg($name, $closure, @args);

call closure with adding "inside foo" annotation to error message.

=over 4

=item * $name

subject (such as "Timer: foo timer").

=item * $closure

closure of want to call.

=item * @args

args to call closure.

=back

=cut

sub do_with_errmsg {
    my $pkg = shift;
    my ($name, $closure, @args) = @_;

    my $str = "    inside $name;\n";
    do {
	no strict 'refs';
	local ($SIG{__WARN__}, $SIG{__DIE__}) =
	    (map {
		my $signame = "__\U$_\E__";
		my $handler = $pkg->sighandler_or_default($_);
		sub {
		    my $msg = shift;
		    if (!ref($msg)) {
			$handler->(($msg).$str);
		    } else {
			#FIXME...
			$handler->($msg);
		    }
		};
	    } qw(warn die));

	$closure->(@args);
    };
}

package Tiarra::Utils::CallWrapper::EnsureCleaner;
use strict;
use warnings;
use base qw(Tiarra::Utils::CallWrapper);

sub new {
    my ($class, $closure) = @_;
    bless $closure, $class;
}

sub DESTROY {
    my $this = shift;
    local $@; # FIXME: we can't know ensure _die_...
    $this->do_with_errmsg('ensure', $this);
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
