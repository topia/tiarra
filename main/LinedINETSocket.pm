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

# 行単位の入出力を行うINET-tcpソケットです。
# read, writeはRunLoopによって自動的に行われる他、
# pop_queueの実行前とflushによっても実行されます。

# newでeolを指定することによって、
# CRLF,LF,CR,またはNULLなど、さまざまな行終端文字が使用できます。
# 省略した場合はCRLFを使用します。

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
    # 接続先ホストとポートを指定して接続を行なう。
    my ($this, $host, $port) = @_;
    return if $this->connected;

    # ソケットを開く。開けなかったらundef。
    my $sock = new IO::Socket::INET(PeerAddr => $host,
				  PeerPort => $port,
				  Proto => 'tcp',
				  Timeout => 5);
    $this->attach($sock);
}

sub attach {
  # 既に開かれているソケットをLinedINETSocketの処理対象に設定する。
  # 通常このメソッドはLinedINETSocket#connectから呼ばれるが、
  # リスニングして受け付けた接続を対象にしたい時などはこのメソッドを使う。
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
    $this->{esock}->uninstall; # 有り得ないとは思うが念のため。
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
  # 送るべきデータがあれば1、無ければundefを返します。
  $_[0]->{sendbuf} eq '' ? undef : 1;
}

sub send_reserve {
  my ($this, $string) = @_;
  # 文字列を送るように予約する。ソケットの送信の準備が整っていなくてもブロックしない。
  # CRLFはつけてはならない。

  if ($this->{sock}) {
    $this->{sendbuf} .= $string . $this->{eol};
  } else {
    die "LinedINETSocket::send_reserve : socket is not connected.";
  }
}

sub send {
  my ($this) = @_;
  # このメソッドはソケットに送れるだけのメッセージを送ります。
  # 送信の準備が整っていなかった場合は、このメソッドは操作をブロックします。
  # それがまずいのなら予めselectで書き込める事を確認しておいて下さい。
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
  # ソケットに読めるデータが来ていなかった場合、このメソッドは読めるようになるまで
  # 操作をブロックします。それがまずい場合は予めselectで読める事を確認しておいて下さい。
  # このメソッドを実行したことで始めてソケットが閉じられた事が分かった場合は、
  # メソッド実行後からはconnectedメソッドが偽を返すようになります。
  if (!defined($this->{sock}) || !$this->connected) {
    # die "IrcIO::receive : socket is not connected.\n";
    $this->disconnect;
    return ();
  }

  my $recvbuf = '';
  sysread($this->{sock},$recvbuf,4096); # とりあえず最大で4096バイトを読む
  if ($recvbuf eq '') {
    # ソケットが閉じられていた。
    $this->disconnect;
  }
  else {
    $this->{recvbuf} .= $recvbuf;
  }

  while (1) {
    my $eol_pos = index($this->{recvbuf}, $this->{eol});
    if ($eol_pos == -1) {
      # 一行分のデータが届いていない。
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
  # このメソッドは受信キュー内の最も古いものを取り出します。
  # キューが空ならundefを返します。
  my ($this) = @_;
  $this->flush(); # 念のためflushをしてbufferを更新しておく。
  if (@{$this->{recv_queue}} == 0) {
    return undef;
  } else {
    return splice @{$this->{recv_queue}},0,1;
  }
}

1;
