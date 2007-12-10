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
use Tiarra::Utils;
use Tiarra::Socket::Lined;
use base qw(Tiarra::Socket::Lined);

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
# callback ����ꤹ��� disconnect ���� callback method ���ƤФ�ޤ���
# $callback->($genre, $errno), $genre �� read, write, exception, eof, �⤷����
# undef �ǡ� eof �� undef �λ��ˤ� errno �Ϥ���ޤ���

sub new {
    my ($class, $eol, $callback) = @_;

    my $this = $class->SUPER::new(
	_caller => 1,
	_subject => 'lined-inet-socket',
	eol => $eol,
       );
    $this->{disconnect_callback} = $callback
	if defined ref($callback) &&
	    ref($callback) eq 'CODE';
    $this;
}

sub disconnect {
    my ($this, $errno, $genre, @params) = @_;
    $this->SUPER::disconnect($errno, $genre, @params);
    if (defined $this->{disconnect_callback}) {
	$this->{disconnect_callback}->($errno, $genre);
    }
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

sub attach {
    my $this = shift;
    $this->SUPER::attach(@_);
    $this->install;
}

sub length { shift->write_length; }

sub send_reserve {
    my ($this, $string) = @_;
    # ʸ���������褦��ͽ�󤹤롣�����åȤ������ν��������äƤ��ʤ��Ƥ�֥�å����ʤ���
    # CRLF�ϤĤ��ƤϤʤ�ʤ���

    if ($this->sock) {
	$this->append_line($string);
    } else {
	die "LinedINETSocket::send_reserve : socket is not connected.";
    }
}

1;
