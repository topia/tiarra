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
	_subject => 'lined-inet-socket',
	eol => $eol,
       );
    $this;
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
    my $this = shift;
    $this->SUPER::attach(@_);
    $this->install;
}

sub length { shift->write_length; }

sub send_reserve {
    my ($this, $string) = @_;
    # 文字列を送るように予約する。ソケットの送信の準備が整っていなくてもブロックしない。
    # CRLFはつけてはならない。

    if ($this->sock) {
	$this->append_line($string);
    } else {
	die "LinedINETSocket::send_reserve : socket is not connected.";
    }
}

1;
