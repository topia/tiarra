# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Lined IO Socket
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.
# this module based IrcIO.pm, thanks phonohawk!
package LinedINETSocket;
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use RunLoop;
use Tiarra::Utils;
use Tiarra::Socket::Buffered;
use base qw(Tiarra::Socket::Buffered);
use base qw(Tiarra::Utils);
__PACKAGE__->define_attr_accessor(0, qw(eol));

use SelfLoader;
SelfLoader->load_stubs;
1;
__DATA__

# ��ñ�̤������Ϥ�Ԥ�INET-tcp�����åȤǤ���
# read, write��RunLoop�ˤ�äƼ�ưŪ�˹Ԥ���¾��
# pop_queue�μ¹�����flush�ˤ�äƤ�¹Ԥ���ޤ���

# new��eol����ꤹ�뤳�Ȥˤ�äơ�
# CRLF,LF,CR,�ޤ���NULL�ʤɡ����ޤ��ޤʹԽ�üʸ�������ѤǤ��ޤ���
# ��ά��������CRLF����Ѥ��ޤ���

sub new {
    my ($class, $eol) = @_;

    my $this = $class->SUPER::new(
	_caller => 1,
	_subject => 'lined-inet-socket');
    $this->eol($this->get_first_defined(
	$eol,
	"\x0d\x0a"));
    $this->{recvqueue} = [];
    $this;
}

sub disconnect_after_writing {
    shift->{disconnect_after_writing} = 1;
}

sub connect {
    # ��³��ۥ��Ȥȥݡ��Ȥ���ꤷ����³��Ԥʤ���
    my ($this, $host, $port) = @_;
    return if $this->connected;

    # �����åȤ򳫤��������ʤ��ä���undef��
    my $sock = new IO::Socket::INET(PeerAddr => $host,
				    PeerPort => $port,
				    Proto => 'tcp',
				    Timeout => 5);
    $this->attach($sock);
}

sub length { shift->write_length; }

sub send_reserve {
    my ($this, $string) = @_;
    # ʸ���������褦��ͽ�󤹤롣�����åȤ������ν��������äƤ��ʤ��Ƥ�֥�å����ʤ���
    # CRLF�ϤĤ��ƤϤʤ�ʤ���

    if ($this->sock) {
	$this->append($string . $this->eol);
    } else {
	die "LinedINETSocket::send_reserve : socket is not connected.";
    }
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
