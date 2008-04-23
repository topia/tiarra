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
    $this;
}

sub append_line {
    my ($this, $line) = @_;

    $this->append($line . $this->eol);
}

sub pop_queue {
    # このメソッドは受信キュー内の最も古いものを取り出します。
    # キューが空ならundefを返します。
    # 行単位でないI/Oが必要ならrecvbufを直接操作してください。
    my ($this) = @_;
    $this->flush;	   # 念のためflushをしてbufferを更新しておく。

    my $eol_pos = index($this->recvbuf, $this->eol);
    if ($eol_pos == -1) {
	# 一行分のデータが届いていない。
	return undef;
    }

    my $line = substr($this->recvbuf, 0, $eol_pos);
    substr($this->recvbuf, 0, $eol_pos + CORE::length($this->eol)) = '';

    return $line;
}

1;
