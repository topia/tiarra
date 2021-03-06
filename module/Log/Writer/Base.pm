# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Log::Writer::Base;
use strict;
use warnings;
use Carp;
use Tiarra::Utils;
use base qw(Tiarra::Utils);

# pure virtual function helper
sub not_implemented_error {
    my ($class_or_this) = shift;

    die $class_or_this->name . '/' . (caller(1))[3] .
	': Please Implement this!';
}

# need override
sub new {
    my ($class, $parent, $uri, %options) = @_;

    carp 'Cannot use undef on class, parent, and uri.'
	if (grep {(!defined $_) ? 1 : ()} ($class, $parent, $uri));

    my $this = {
	refcount => 0,
	parent => $parent,

	buffer => '',
	always_flush => $class->first_defined($options{always_flush}, 1),
	uri => $uri,
	notify_cache => {},
       };

    bless $this, $class;
    $this;
}

sub capability {
    my ($class, $type, @args) = @_;

    # $type:
    #   - fallback: protocol support fallback
    return 0;
}

sub scheme {
    my $class_or_this = shift;

    # please return scheme string(such as 'file')
    '';
}

sub name {
    my $class_or_this = shift;

    # please return protocol name
    'base (cannot use this directly)';
}

sub supported_schemes {
    my $class_or_this = shift;

    # please return supported schemes
    ();
}

sub real_flush {
    my $this = shift;

    $this->not_implemented_error;
    0; # please return bool(1: successful, 0: failed)
}

sub real_destruct {
    my ($this, $force) = @_;

    $this->not_implemented_error;
    # optionally, you can warning if losing data.
    # probably $force is useless, because usually does NOT call this
    #  on (!$this->can_remove && !$force).
    # when $force is true, we will destroy instance even if return failed.
    0; # please return bool(1: successful, 0: failed)
}

# base definition
sub first_defined {
    shift->get_first_defined(@_);
}

sub define_accessor {
    # backward compat
    shift->define_attr_accessor(0, @_);
}

__PACKAGE__->define_attr_accessor(0, qw(buffer always_flush uri));
__PACKAGE__->define_attr_getter(0, qw(refcount parent));

sub add_ref { ++(shift->{refcount}); }
sub release { --(shift->{refcount}); }
sub length { CORE::length(shift->buffer); }
sub clear { shift->buffer(''); }
sub has_data { shift->length > 0; }

sub path {
    my $this = shift;

    if (!defined $this->{path}) {
	return undef if (!defined $this->{uri});
	my $scheme = $this->scheme;
	return undef if (!defined $scheme);
	($this->{path} = $this->{uri}) =~ s|^\Q$scheme\E://||;
    }
    $this->{path};
}

sub register {
    my $this = shift;

    $this->add_ref;
    $this;
}

sub unregister {
    my $this = shift;

    $this->release;
    if ($this->can_remove) {
	return $this->destruct;
    } else {
	return 1;
    }
}

sub can_remove {
    my $this = shift;

    return ($this->refcount <= 0 && !$this->has_data);
}

sub reserve {
    my ($this, $str) = @_;

    $this->{buffer} .= $str;
    $this->flush if ($this->always_flush);
}
*write = \&reserve;
*print = \&reserve;

sub flush {
    my $this = shift;

    return 1 if !$this->has_data;
    if ($this->real_flush) {
	$this->destruct if ($this->can_remove);
	return 1;
    } else {
	return 0;
    }
}

sub destruct {
    my ($this, $force) = @_;

    if (!ref($this)) {
	return 0; # ignore calls from ModuleManager
    }

    my $ret = $this->real_destruct($force);
    $this->parent->object_release($this->uri) if ($ret || $force);
    $ret;
}


# util

sub _notify_warn {
    my ($this, $str) = @_;

    if ($this->_check_notify_cache($str)) {
	$this->parent->notify_warn($this->_notify_prefix(1).$str);
    }
}

sub _notify_error {
    my ($this, $str) = @_;

    if ($this->_check_notify_cache($str)) {
	$this->parent->notify_error($this->_notify_prefix(1).$str);
    }
}

sub _notify_msg {
    my ($this, $str) = @_;

    if ($this->_check_notify_cache($str)) {
	$this->parent->notify_msg($this->_notify_prefix(1).$str);
    }
}

sub _check_notify_cache {
    # check cache and return true if can notify
    my ($this, $str) = @_;

    if (%{$this->{notify_cache}}) {
	grep {
	    if ($this->{notify_cache}->{$_} < time) {
		# expire
		delete $this->{notify_cache};
	    }
	    0;
	} keys %{$this->{notify_cache}};
    }
    if ($this->{notify_cache}->{$str}) {
	return 0;
    } else {
	# ignore 15sec
	$this->{notify_cache}->{$str} = time + 15;
	return 1;
    }
}

sub _notify_prefix {
    my ($this, $stack_level) = @_;

    $stack_level = 0 if !defined $stack_level;
    $this->name.'/'.(caller(1 + $stack_level))[3].'('
	.$this->uri.'): ';
}

1;
