# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Tiarra Encoding Manager
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Encoding;
use strict;
use warnings;
use Carp;
our %modules = (
    qr/(uni-?jp|unicode(::|-)japanese)/i => 'UniJP',
    qr/encode/i => 'Encode',
   );
our %tried_providers;

sub new {
    my ($class, $str, $icode, $encode, %options) = @_;

    if ($class eq __PACKAGE__) {
	if (!defined $options{provider}) {
	    if ($class->_is_supported('encode')) {
		$options{provider} = 'encode';
	    } elsif ($class->_is_supported('unijp')) {
		$options{provider} = 'unijp';
	    } else {
		die 'supported provider not found!';
	    }
	}
	croak "encoding provider($options{provider}) isn't supported"
	    unless $class->_is_supported($options{provider});
	$class->_get_module_name($options{provider})->new(
	    $str, $icode, $encode, %options);
    } else {
	my $this = {};
	bless $this, $class;
	$this->_init(%options) if $this->can('_init');
	$this->set($str, $icode, $encode, %options);
    }
}

sub from_to {
    my $this = shift;
    my $str = shift;
    my $from_code = shift;
    my $to_code = shift;

    if ((defined $from_code && $from_code eq 'binary') ||
	    (defined $to_code && $to_code eq 'binary')) {
	$str;
    } else {
	$this->set($str, $from_code);
	$this->conv($to_code);
    }
}

sub _is_supported {
    my $modname = shift->_get_module_name(@_);
    return $tried_providers{$modname} if defined $tried_providers{$modname};
    my $retval = eval 'require ' . $modname;
    warn $@ if $@;
    $tried_providers{$modname} = $retval;
    return $retval;
}

sub _get_module_name {
    my ($this, $charset) = @_;
    foreach (keys %modules) {
	if ($charset =~ /$_/) {
	    $charset = $modules{$_};
	    last;
	}
    }
    return __PACKAGE__ . '::' . $charset;
}

1;
