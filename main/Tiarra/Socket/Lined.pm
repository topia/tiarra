# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Lined Socket
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket::Lined;
use strict;
use warnings;
use Carp;
use Tiarra::Socket::Buffered;
use base qw(Tiarra::Socket::Buffered);
use Tiarra::Utils;
utils->define_attr_accessor(0, qw(eol));

sub new {
    my ($class, %opts) = @_;

    $class->_increment_caller('lined-socket', \%opts);
    my $this = $class->SUPER::new(%opts);
    $this->eol(utils->get_first_defined(
	$opts{eol},
	"\x0d\x0a"));
    $this->{recvqueue} = [];
    $this;
}

sub append_line {
    my ($this, $line) = @_;

    $this->append($line . $this->eol);
}

sub read {
    my $this = shift;

    $this->SUPER::read;

    while (1) {
	my $eol_pos = index($this->recvbuf, $this->eol);
	if ($eol_pos == -1) {
	    # ���ʬ�Υǡ������Ϥ��Ƥ��ʤ���
	    last;
	}

	my $current_line = substr($this->recvbuf, 0, $eol_pos);
	substr($this->recvbuf, 0, $eol_pos + CORE::length($this->eol)) = '';

	push @{$this->{recv_queue}}, $current_line;
    }
}

sub pop_queue {
    # ���Υ᥽�åɤϼ������塼��κǤ�Ť���Τ���Ф��ޤ���
    # ���塼�����ʤ�undef���֤��ޤ���
    my ($this) = @_;
    $this->flush;	   # ǰ�Τ���flush�򤷤�buffer�򹹿����Ƥ�����
    if (@{$this->{recv_queue}} == 0) {
	return undef;
    } else {
	return splice @{$this->{recv_queue}},0,1;
    }
}

1;
