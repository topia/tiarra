# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Call Wrapping Helper
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils::CallWrapper;
use strict;
use warnings;
use Tiarra::Utils::Core;
use base qw(Tiarra::Utils::Core);
use Carp;

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
    my $cleaner = Tiarra::Utils::CallWrapper::EnsureCleaner->new($ensure);
    $closure->(@args);
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
    $this->do_with_errmsg('ensure', $this);
}

1;
