# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IrcIOはIRCサーバー又はクライアントと接続し、IRCメッセージをやり取りする抽象クラスです。
# -----------------------------------------------------------------------------
package IrcIO;
use strict;
use warnings;
use Carp;
use Configuration;
use IRCMessage;
use Exception;
use Tiarra::ShorthandConfMixin;
use Tiarra::Utils;
use Tiarra::Socket::Buffered;
use base qw(Tiarra::Socket::Buffered);
utils->define_attr_getter(0, [qw(_runloop runloop)]);

sub new {
    my ($class, $runloop, %opts) = @_;
    carp 'runloop is not specified!' unless defined $runloop;
    $class->_increment_caller('ircio', \%opts);
    my $this = $class->SUPER::new(runloop => $runloop, %opts);
    $this->{recv_queue} = [];
    $this->{remarks} = {};
    $this;
}

sub server_p {
    shift->isa('IrcIO::Server');
}

sub client_p {
    shift->isa('IrcIO::Client');
}

*remarks = \&remark;
sub remark {
    my ($this,$key,$newvalue) = @_;
    if (!defined $key) {
	croak "IrcIO->remark, Arg[1] is undef.\n";
    }
    elsif (defined $newvalue) {
	$this->{remarks}->{$key} = $newvalue;
    }
    elsif (@_ >= 3) {
	delete $this->{remarks}{$key};
    }
    $this->{remarks}->{$key};
}

sub send_message {
    my ($this,$msg,$encoding) = @_;
    # データを送るように予約する。ソケットの送信の準備が整っていなくてもブロックしない。

    # msgは生の文字列でも良いしIRCMessageのインスタンスでも良い。
    # 生の文字列を渡す時には、末尾にCRLFを付けてはならない。
    # また、生の文字列については文字コードの変換が行なわれない。
    my $data_to_send = '';
    if (ref($msg) eq '') {
	# deprecated.
	# FIXME: warnすべきだろうか。
	$data_to_send = "$msg\x0d\x0a";
    }
    elsif ($msg->isa('IRCMessage')) {
	# message_io_hook
	my $filtered = $this->_runloop->apply_filters(
	    [$msg], 'message_io_hook', $this, 'out');
	foreach (@$filtered) {
	    $data_to_send .= $_->serialize($encoding)."\x0d\x0a";
	}
	#$data_to_send = $msg->serialize($encoding)."\x0d\x0a";
    }
    else {
	die "IrcIO::send_message : parameter msg was invalid; $msg\n";
    }
    
    if ($this->connected) {
	$this->append($data_to_send);
    }
    else {
	die "IrcIO::send_message : socket is not connected.\n";
    }
}

sub read {
    my ($this,$encoding) = @_;
    # このメソッドはIRCメッセージを一行ずつ受け取り、IRCMessageのインスタンスをキューに溜めます。
    # ソケットに読めるデータが来ていなかった場合、このメソッドは読めるようになるまで
    # 操作をブロックします。それがまずい場合は予めselectで読める事を確認しておいて下さい。
    # このメソッドを実行したことで始めてソケットが閉じられた事が分かった場合は、
    # メソッド実行後からはconnectedメソッドが偽を返すようになります。

    $this->SUPER::read;

    while (1) {
	# CRLFまたはLFが行の終わり。
	my $newline_pos = index($this->recvbuf,"\x0a");
	if ($newline_pos == -1) {
	    # 一行分のデータが届いていない。
	    last;
	}

	my $current_line = substr($this->recvbuf,0,$newline_pos);
	$this->recvbuf(substr($this->recvbuf,$newline_pos+1));

	# CRLFだった場合、末尾にCRが付いているので取る。
	$current_line =~ s/\x0d$//;

	if (CORE::length($current_line) == 0) {
	    # 空行はスキップ
	    next;
	}

	# message_io_hook
	my $msg = IRCMessage->new(
	    Line => $current_line, Encoding => $encoding);
	my $filtered = $this->_runloop->apply_filters(
	    [$msg], 'message_io_hook', $this, 'in');

	foreach (@$filtered) {
	    $_->purge_raw_params;
	    push @{$this->{recv_queue}}, $_;
	}
    }
}

sub pop_queue {
    # このメソッドは受信キュー内の最も古いものを取り出します。
    # キューが空ならQueueIsEmptyExceptionを投げます。
    my ($this) = @_;
    if (@{$this->{recv_queue}} == 0) {
	QueueIsEmptyException->new->throw;
    }
    else {
	return shift @{$this->{recv_queue}};
    }
}

1;
