# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# MainLoop wrapper for write Portable Module
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::WrapMainLoop;
use strict;
use warnings;
use Carp;
use Tiarra::Utils;
utils->define_attr_accessor(0,
			    qw(installed name),
			    map { ["_$_", $_] }
				qw(closure type interval object));

# lazy load
#use RunLoop;
#use Timer;

sub new {
    my ($class, %opt) = @_;

    my $this = {
	installed => 0,
    };
    bless $this, $class;
    $this->type(utils->get_first_defined($opt{type}, 'timer'));
    $this->interval(utils->get_first_defined($opt{interval}, 5));
    $this->_closure(utils->get_first_defined($opt{closure}, undef));
    $this->name(utils->get_first_defined(
	$opt{name},
	utils->simple_caller_formatter('wrapmainloop registered')));
    $this;
}

sub _check_uninstalled {
    my $this = shift;

    croak "hook/timer installed; before uninstall this."
	if $this->installed;
}

sub _check_installed {
    my $this = shift;

    croak "hook/timer uninstalled; before install this."
	unless $this->installed;
}

sub type {
    my ($this, $value) = @_;

    $this->_check_uninstalled;
    if (defined $value) {
	croak "unsupported mainloop type: $value."
	    if (!scalar(grep { $value eq $_; } qw(timer mainloop)));
	$this->_type($value);
    }
    $this->_type;
}

sub interval {
    my ($this, $value, $option) = @_;

    if (defined $value) {
	if ($this->_type eq 'timer') {
	    if ($value < 1 &&
		    !(defined $option && $option eq 'permit_toofast')) {
		croak "interval is too fast! if without program bug, ".
		    "pass 'permit_toofast' option.";
	    }
	    $this->_interval($value);
	    $this->_object->interval($value) if ($this->installed);
	} elsif ($this->_type eq 'mainloop') {
	    croak "interval is not used in this type; fix code.";
	} else {
	    die 'internal error! unknown type('.$this->_type.').';
	}
    }
    $this->_interval;
}

sub install {
    my $this = shift;
    $this->_check_uninstalled;
    $this->_install;
}

sub uninstall {
    my $this = shift;
    $this->_check_installed;
    $this->_uninstall;
}

sub lazy_install {
    my $this = shift;
    $this->_install unless $this->installed;
}

sub lazy_uninstall {
    my $this = shift;
    $this->_uninstall if $this->installed;
}

sub _install {
    my $this = shift;
    croak "closure is not defined;"
	unless defined $this->_closure;
    if ($this->_type eq 'timer') {
	if (require Timer) {
	    $this->_object(Timer->new(
		Name => 'WrapMainLoop: '.$this->name,
		Repeat => 1,
		Interval => $this->_interval,
		Code => $this->_closure)->install);
	} else {
	    die 'Timer cannot load';
	}
    } elsif ($this->_type eq 'mainloop') {
	if (require RunLoop) {
	    $this->_object(RunLoop::Hook->new($this->_closure)->install('after-select'));
	} else {
	    die 'RunLoop cannot load';
	}
    } else {
	die 'internal error! unknown type('.$this->_type.').';
    }
    $this->installed(1);
    $this;
}

sub _uninstall {
    my $this = shift;
    $this->_object->uninstall;
    $this->_object(undef);
    $this->installed(0);
    $this;
}

1;
