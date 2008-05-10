# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Buffered Socket
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket::Buffered;
use strict;
use warnings;
use Carp;
use Tiarra::Socket;
use base qw(Tiarra::Socket);
use Tiarra::Utils;
utils->define_attr_getter(0, qw(connected));
utils->define_attr_accessor(0, qw(recvbuf sendbuf));

sub new {
    my ($class, %opts) = @_;

    $class->_increment_caller('buffered-socket', \%opts);
    my $this = $class->SUPER::new(%opts);
    $this->{connected} = undef;
    $this->{sendbuf} = '';
    $this->{recvbuf} = '';
    $this->{disconnect_after_writing} = 0;
    $this;
}

sub DESTROY {
    my $this = shift;

    $this->disconnect if $this->connected;
}

sub disconnect_after_writing {
    shift->{disconnect_after_writing} = 1;
}

sub disconnect {
    my ($this, $errno, $genre, @params) = @_;

    $this->uninstall if $this->installed;
    $this->close;
}

sub attach {
    my ($this, $sock) = @_;
    return undef if $this->connected;
    return undef unless defined $sock;

    $this->SUPER::attach($sock);
    $this->{connected} = 1;

    return $this;
}

sub detach {
    my $this = shift;

    if (!defined $this->sock) {
	croak "already detached; can't detach!";
    }
    if ($this->installed) {
	carp "installed; anyway detach...";
	$this->uninstall;
    }

    $this->{connected} = 0;
    $this->{sendbuf} = '';
    #$this->{recvbuf} = '';
    $this->SUPER::detach;
}

sub write_length { length shift->sendbuf }
# 送るべきデータがあれば1、無ければ0を返します。
sub want_to_write { shift->write_length > 0 }
sub read_length { length shift->recvbuf }
sub has_data { shift->read_length > 0 }

sub append {
    my ($this, $str) = @_;

    $this->sendbuf .= $str;
}

sub write {
    my ($this) = @_;
    # このメソッドはソケットに送れるだけのメッセージを送ります。
    # 送信の準備が整っていなかった場合は、このメソッドは操作をブロックします。
    # それがまずいのなら予めselectで書き込める事を確認しておいて下さい。
    if (!$this->connected) {
	die "write : socket is not connected.\n";
    }

    my $bytes_sent = $this->sock->syswrite($this->sendbuf, $this->write_length);
    if (defined $bytes_sent) {
	substr($this->sendbuf, 0, $bytes_sent) = '';

	if ($this->{disconnect_after_writing} &&
		!$this->want_to_write) {
	    $this->disconnect;
	}
    } else {
	# write error
	$this->handle_io_error('write', $!);
    }
}

sub read {
    my $this = shift;
    # ソケットに読めるデータが来ていなかった場合、このメソッドは読めるようになるまで
    # 操作をブロックします。それがまずい場合は予めselectで読める事を確認しておいて下さい。
    # このメソッドを実行したことで始めてソケットが閉じられた事が分かった場合は、
    # メソッド実行後からはconnectedメソッドが偽を返すようになります。
    if (!$this->connected) {
	$this->disconnect;
	return ();
    }

    my $recvbuf = '';
    my $retval = $this->sock->sysread($recvbuf,4096); # とりあえず最大で4096バイトを読む
    if (defined $retval) {
	if ($retval == 0) {
	    # EOF
	    $this->disconnect('eof');
	} else {
	    $this->recvbuf .= $recvbuf;
	}
    } else {
	# read error
	$this->handle_io_error('read', $!);
    }
}

sub handle_io_error {
    my ($this, $genre, $errno) = @_;

    local $! = $errno;
    if ($!{EWOULDBLOCK} || $!{EINPROGRESS} || $!{EALREADY} || $!{ENOBUFS}) {
	$this->runloop->notify_warn($this->sock_errno_to_msg($errno, "$genre error"));
    } else {
	# maybe couldn't continue
	$this->disconnect($genre, $errno);
    }
}

sub exception {
    my $this = shift;

    $this->handle_io_error('exception', $this->errno);
}

sub flush {
    my $this = shift;

    return undef unless $this->connected;

    my ($select) = IO::Select->new($this->sock);

    if ($this->want_to_write && $select->can_write(0)) {
	$this->write;
    }

    return undef unless $this->connected;

    if ($select->can_read(0)) {
	$this->read;
    }

    return 1;
}

1;
