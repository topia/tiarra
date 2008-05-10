# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Tools::FileCache::EachFile;
use strict;
use warnings;
use Carp;
use Module::Use qw(Tools::LinedDB);
use Tools::LinedDB;
use Tiarra::Utils;
our $AUTOLOAD;

my $timeout = 2.5 * 60;

sub new {
    my ($class, $parent, $fpath, $mode, $charset) = @_;

    my ($this) = {
	parent => $parent,
	mode => undef,
	database => undef,
	refcount => 0,
	expire => undef,
    };

    if ($mode =~ /raw/i) {
	$this->{mode} = 'raw';
	$this->{database} = 
	    Tools::LinedDB->new(
		FilePath => $fpath,
		Charset => $charset,
	       );
    } elsif ($mode =~ /std/i) {
	$this->{mode} = 'std';
	$this->{database} = 
	    Tools::LinedDB->new(
		FilePath => $fpath,
		Charset => $charset,
		Parse => sub {
		    my ($line) = @_;
		    $line =~ s/^\s+//;
		    return () if $line =~ /^[\#\;]/;
		    $line =~ s/\s+$//;
		    return () if $line eq '';
		    return $line;
		},
	       );
    } else {
	croak 'can\'t understand type "' . $mode . '"';
    }

    bless $this, $class;

    return $this;
}


sub register {
    my $this = shift;

    $this->add_ref;
    $this;
}

sub unregister {
    my $this = shift;

    $this->release;
    $this;
}

Tiarra::Utils->define_attr_getter(0, qw(refcount expire));

sub add_ref { ++(shift->{refcount}); }
sub release { --(shift->{refcount}); }
sub can_remove { (shift->refcount <= 0); }

sub set_expire {
    my ($this) = @_;

    $this->{expire} = time() + $timeout;
    return $this;
}

sub clean {
    my ($this) = @_;

    $this->{database} = undef;
}

sub AUTOLOAD {
    my ($this, @args) = @_;

    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROYは伝達させない。
	return;
    }

    (my $method = $AUTOLOAD) =~ s/.+?:://g;

    # define method
    eval "sub $method { shift->{database}->$method(\@_); }";

    no strict 'refs';
    goto &$AUTOLOAD;
}

1;
