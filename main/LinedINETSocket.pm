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

# 行単位の入出力を行うINET-tcpソケットです。
# read, writeはRunLoopによって自動的に行われる他、
# pop_queueの実行前とflushによっても実行されます。

# newでeolを指定することによって、
# CRLF,LF,CR,またはNULLなど、さまざまな行終端文字が使用できます。
# 省略した場合はCRLFを使用します。

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

sub length { shift->write_length; }

sub send_reserve {
    my ($this, $string) = @_;
    # 文字列を送るように予約する。ソケットの送信の準備が整っていなくてもブロックしない。
    # CRLFはつけてはならない。

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
	    # 一行分のデータが届いていない。
	    last;
	}

	my $current_line = substr($this->recvbuf, 0, $eol_pos);
	substr($this->recvbuf, 0, $eol_pos + CORE::length($this->eol)) = '';

	push @{$this->{recv_queue}}, $current_line;
    }
}

sub pop_queue {
    # このメソッドは受信キュー内の最も古いものを取り出します。
    # キューが空ならundefを返します。
    my ($this) = @_;
    $this->flush;	   # 念のためflushをしてbufferを更新しておく。
    if (@{$this->{recv_queue}} == 0) {
	return undef;
    } else {
	return splice @{$this->{recv_queue}},0,1;
    }
}

1;
