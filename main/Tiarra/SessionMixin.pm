# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Session Mixin
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::SessionMixin;
use strict;
use warnings;
use Tiarra::Utils;
use Carp;
use base qw(Tiarra::Utils);

our $use_threads;
BEGIN {
    my $threads_enabled = eval { &::threads_enabled };
    if (defined $threads_enabled) {
	$use_threads = $threads_enabled;
    } else {
	# あがいても仕方ないと思うが試してみる。
	eval q{
	    use threads;
	    use threads::shared;
	};
	$use_threads = ($@ ? 0 : 1);
    }
    if ($use_threads) {
	eval 'use Thread::Queue;';
    }
}


# usage:
#  use Tiarra::SessionMixin;
#  sub new {
#    ...
#    $this->_session_init;
#  }

__PACKAGE__->define_attr_accessor(0, qw(session_level));
sub _session_init {
    my $this = shift;
    $this->session_level(0);
    if ($use_threads) {
	my $lock : shared;
	$this->{lock} = \$lock;
    }
}

sub session_start {
    my $this = shift;
    if ($this->session_level) {
	carp 'this object already started...';
    }
    eval { $this->_before_session_start; };
    ++$this->session_level;
    eval { $this->_after_session_start; };
    1;
}

sub session_finish {
    my $this = shift;
    if (!$this->session_level) {
	carp 'this object already finished!';
	$this->session_level = 1;
    }
    eval { $this->_before_session_finish; };
    --$this->session_level;
    eval { $this->_after_session_finish; };
    1;
}

sub with_session {
    my ($this, $closure) = @_;
    my $wantarray = wantarray;
    my $level = $this->session_level;
    $this->session_start unless $level;
    lock $this->{lock} if $use_threads;
    $this->do_with_ensure(
	sub { $this->call_with_wantarray($wantarray, $closure); },
	sub { $this->session_finish unless $level; });
}

sub define_session_wrap {
    my $pkg = shift;
    my $class_method_p = shift;
    foreach (@_) {
	my ($funcname, $proxyname);
	if (ref($_) eq 'ARRAY') {
	    $funcname = $_->[0];
	    $proxyname = $_->[1];
	} else {
	    $funcname = $_;
	    $proxyname = "_$_";
	}
	$pkg->define_function(
	    $pkg->get_package,
	    ($class_method_p ? sub {
		 my $class_or_this = shift;
		 my $this = $class_or_this->_this;
		 $this->with_session(
		     sub { $this->$proxyname(@_) }
		    );
	     } : sub {
		 my $this = shift;
		 $this->with_session(
		     sub { $this->$proxyname(@_) }
		    );
	     }),
	    $funcname);
    }
}

1;
