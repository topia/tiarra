# -*- cperl -*-
# $Id: LinedINETSocket.pm,v 1.6 2003/06/03 15:27:42 admin Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
# this module based IrcIO.pm, thanks phonohawk!
package LinedINETSocket;
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use RunLoop;
use ExternalSocket;

use SelfLoader;
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

  $eol = "\x0d\x0a" unless defined $eol;

  my $obj = 
    {
     esock => undef, # ExternalSocket
     eol => $eol,
     sock => undef,
     connected => undef,
     sendbuf => '',
     recvbuf => '',
     recv_queue => [],
     disconnect_after_writing => 0,
   };
  bless $obj,$class;
}

sub DESTROY {
  my ($this) = @_;

  $this->disconnect if $this->connected;
}

sub disconnect_after_writing {
  $_[0]->{disconnect_after_writing} = 1;
}

sub disconnect {
  my ($this) = @_;

  $this->{sock}->shutdown(2) if defined($this->{sock});
  $this->{connected} = undef;
  if (defined($this->{esock})) {
    $this->{esock}->uninstall;
    $this->{esock} = undef;
  }
}

sub sock {
  $_[0]->{sock};
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
  # ���˳�����Ƥ��륽���åȤ�LinedINETSocket�ν����оݤ����ꤹ�롣
  # �̾盧�Υ᥽�åɤ�LinedINETSocket#connect����ƤФ�뤬��
  # �ꥹ�˥󥰤��Ƽ����դ�����³���оݤˤ��������ʤɤϤ��Υ᥽�åɤ�Ȥ���
  my ($this, $sock) = @_;
  return if $this->connected;

  if (defined $sock) {
    $sock->autoflush(1);
    $this->{sock} = $sock;
    $this->{connected} = 1;
  } else {
    return undef;
  }

  if (defined($this->{esock})) {
    $this->{esock}->uninstall; # ͭ�����ʤ��Ȥϻפ���ǰ�Τ��ᡣ
  }
  $this->{esock} = 
    ExternalSocket->new(
			Socket => $sock,
			Read => sub {
			  my ($esock) = @_;
			  $this->receive();
			},
			Write => sub {
			  my ($esock) = @_;
			  $this->send();
			},
			WantToWrite => sub {
			  my ($esock) = @_;
			  $this->need_to_send();
			}
		       );
  $this->{esock}->install();

  return $this;
}

sub connected {
  #defined $_[0]->{sock} && $_[0]->{sock}->connected;
  $_[0]->{connected};
}

sub need_to_send {
  # ����٤��ǡ����������1��̵�����undef���֤��ޤ���
  $_[0]->{sendbuf} eq '' ? undef : 1;
}

sub send_reserve {
  my ($this, $string) = @_;
  # ʸ���������褦��ͽ�󤹤롣�����åȤ������ν��������äƤ��ʤ��Ƥ�֥�å����ʤ���
  # CRLF�ϤĤ��ƤϤʤ�ʤ���

  if ($this->{sock}) {
    $this->{sendbuf} .= $string . $this->{eol};
  } else {
    die "LinedINETSocket::send_reserve : socket is not connected.";
  }
}

sub send {
  my ($this) = @_;
  # ���Υ᥽�åɤϥ����åȤ����������Υ�å�����������ޤ���
  # �����ν��������äƤ��ʤ��ä����ϡ����Υ᥽�åɤ�����֥�å����ޤ���
  # ���줬�ޤ����Τʤ�ͽ��select�ǽ񤭹��������ǧ���Ƥ����Ʋ�������
  unless ($this->{sock}) {
    die "LinedINETSocket::send : socket is not connected.\n";
  }

  #my $bytes_sent = $this->{sock}->send($this->{sendbuf}) || 0;
  my $bytes_sent = $this->{sock}->syswrite($this->{sendbuf}) || 0;
  substr($this->{sendbuf}, 0, $bytes_sent) = '';

  if ($this->{disconnect_after_writing} &&
      $this->{sendbuf} eq '') {
    $this->disconnect;
  }
}

sub receive {
  my ($this) = @_;
  # �����åȤ��ɤ��ǡ�������Ƥ��ʤ��ä���硢���Υ᥽�åɤ��ɤ��褦�ˤʤ�ޤ�
  # ����֥�å����ޤ������줬�ޤ�������ͽ��select���ɤ������ǧ���Ƥ����Ʋ�������
  # ���Υ᥽�åɤ�¹Ԥ������ȤǻϤ�ƥ����åȤ��Ĥ���줿����ʬ���ä����ϡ�
  # �᥽�åɼ¹Ը夫���connected�᥽�åɤ������֤��褦�ˤʤ�ޤ���
  if (!defined($this->{sock}) || !$this->connected) {
    # die "IrcIO::receive : socket is not connected.\n";
    $this->disconnect;
    return ();
  }

  my $recvbuf = '';
  sysread($this->{sock},$recvbuf,4096); # �Ȥꤢ���������4096�Х��Ȥ��ɤ�
  if ($recvbuf eq '') {
    # �����åȤ��Ĥ����Ƥ�����
    $this->disconnect;
  }
  else {
    $this->{recvbuf} .= $recvbuf;
  }

  while (1) {
    my $eol_pos = index($this->{recvbuf}, $this->{eol});
    if ($eol_pos == -1) {
      # ���ʬ�Υǡ������Ϥ��Ƥ��ʤ���
      last;
    }

    my $current_line = substr($this->{recvbuf}, 0, $eol_pos);
    substr($this->{recvbuf}, 0, $eol_pos + length($this->{eol})) = '';

    push @{$this->{recv_queue}}, $current_line;
  }
}

sub flush {
  my ($this) = @_;

  return undef unless $this->connected;
  my ($select) = IO::Select->new($this->{sock});

  if ($this->connected && $this->need_to_send() && $select->can_write(0)) {
    $this->send();
  }

  if ($this->connected && $select->can_read(0)) {
    $this->receive();
  }

  return 1;
}

sub pop_queue {
  # ���Υ᥽�åɤϼ������塼��κǤ�Ť���Τ���Ф��ޤ���
  # ���塼�����ʤ�undef���֤��ޤ���
  my ($this) = @_;
  $this->flush(); # ǰ�Τ���flush�򤷤�buffer�򹹿����Ƥ�����
  if (@{$this->{recv_queue}} == 0) {
    return undef;
  } else {
    return splice @{$this->{recv_queue}},0,1;
  }
}

1;
