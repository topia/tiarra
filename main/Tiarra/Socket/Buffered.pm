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
    my $this = shift;

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
    $this->{recvbuf} = '';
    $this->SUPER::detach;
}

sub write_length { length shift->sendbuf }
# ����٤��ǡ����������1��̵�����0���֤��ޤ���
sub want_to_write { shift->write_length > 0 }
sub read_length { length shift->recvbuf }
sub has_data { shift->read_length > 0 }

sub append {
    my ($this, $str) = @_;

    $this->sendbuf .= $str;
}

sub write {
    my ($this) = @_;
    # ���Υ᥽�åɤϥ����åȤ����������Υ�å�����������ޤ���
    # �����ν��������äƤ��ʤ��ä����ϡ����Υ᥽�åɤ�����֥�å����ޤ���
    # ���줬�ޤ����Τʤ�ͽ��select�ǽ񤭹��������ǧ���Ƥ����Ʋ�������
    if (!$this->connected) {
	die "write : socket is not connected.\n";
    }

    my $bytes_sent = $this->sock->syswrite($this->sendbuf, $this->write_length) || 0;
    substr($this->sendbuf, 0, $bytes_sent) = '';

    if ($this->{disconnect_after_writing} &&
	    !$this->want_to_write) {
	$this->disconnect;
    }
}

sub read {
    my $this = shift;
    # �����åȤ��ɤ��ǡ�������Ƥ��ʤ��ä���硢���Υ᥽�åɤ��ɤ��褦�ˤʤ�ޤ�
    # ����֥�å����ޤ������줬�ޤ�������ͽ��select���ɤ������ǧ���Ƥ����Ʋ�������
    # ���Υ᥽�åɤ�¹Ԥ������ȤǻϤ�ƥ����åȤ��Ĥ���줿����ʬ���ä����ϡ�
    # �᥽�åɼ¹Ը夫���connected�᥽�åɤ������֤��褦�ˤʤ�ޤ���
    if (!$this->connected) {
	$this->disconnect;
	return ();
    }

    my $recvbuf = '';
    $this->sock->sysread($recvbuf,4096); # �Ȥꤢ���������4096�Х��Ȥ��ɤ�
    if ($recvbuf eq '') {
	# �����åȤ��Ĥ����Ƥ�����
	$this->disconnect;
    } else {
	$this->recvbuf .= $recvbuf;
    }
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
