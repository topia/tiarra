# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Tiarra::
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::IRC::Prefix;
use strict;
use warnings;
use enum qw(PREFIX NICK NAME HOST);
use Tiarra::Utils;

utils->define_array_attr_notify_accessor(
    0, '$this->_update_prefix', qw(nick name host));
utils->define_array_attr_notify_accessor(
    0, '$this->_parse_prefix', qw(prefix));

sub new {
    my ($class,%args) = @_;
    my $obj = bless [] => $class;
    $obj->[PREFIX] = undef;
    $obj->[NICK] = undef;
    $obj->[NAME] = undef;
    $obj->[HOST] = undef;

    foreach (qw(Prefix Nick User Host)) {
	if (exists $args{$_}) {
	    my $method = lc($_);
	    $obj->$method($args{$_});
	}
    }
    $obj;
}

sub _parse_prefix {
    my $this = shift;
    delete $this->[NICK];
    delete $this->[NAME];
    delete $this->[HOST];
    if (defined $this->[PREFIX]) {
	if ($this->[PREFIX] !~ /@/) {
	    $this->[NICK] = $this->[PREFIX];
	} elsif ($this->[PREFIX] =~ m/^(.+?)!(.+?)@(.+)$/) {
	    $this->[NICK] = $1;
	    $this->[NAME] = $2;
	    $this->[HOST] = $3;
	} elsif ($this->[PREFIX] =~ m/^(.+?)@(.+)$/) {
	    $this->[NICK] = $1;
	    $this->[HOST] = $2;
	}
    } else {
	delete $this->[PREFIX];
    }
}

sub _update_prefix {
    my $this = shift;
    if (defined $this->[NICK]) {
	$this->[PREFIX] = $this->[NICK];
	if (defined $this->[HOST]) {
	    if (defined $this->[NAME]) {
		$this->[PREFIX] .= '!'.$this->[NAME];
		$this->[PREFIX] .= '@'.$this->[HOST];
	    } else {
		$this->[PREFIX] .= '@'.$this->[HOST];
		delete $this->[NAME];
	    }
	} else {
	    delete $this->[NAME];
	    delete $this->[HOST];
	}
    } else {
	delete $this->[NICK];
	delete $this->[NAME];
	delete $this->[HOST];
    }
}

1;
