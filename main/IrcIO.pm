# -----------------------------------------------------------------------------
# $Id: IrcIO.pm,v 1.22 2004/03/19 13:21:06 topia Exp $
# -----------------------------------------------------------------------------
# IrcIOはIRCサーバー又はクライアントと接続し、IRCメッセージをやり取りする抽象クラスです。
# -----------------------------------------------------------------------------
package IrcIO;
use strict;
use warnings;
use Carp;
use IO::Socket::INET;
use Configuration;
use IRCMessage;
use Exception;

sub new {
    my $class = shift;
    my $obj = {
	sock => undef, # IO::Socket::INET
	connected => undef, # どうも$sock->connectedは信用出来ない。
	sendbuf => '',
	recvbuf => '',
	recv_queue => [],
	disconnect_after_writing => 0,
	remarks => {},
    };
    bless $obj,$class;
}

sub server_p {
    shift->isa('IrcIO::Server');
}

sub client_p {
    shift->isa('IrcIO::Client');
}

sub disconnect_after_writing {
    shift->{disconnect_after_writing} = 1;
}

sub disconnect {
    my $this = shift;
    $this->{sock}->shutdown(2);
    $this->{connected} = undef;
}

sub sock {
    $_[0]->{sock};
}

sub connected {
    #defined $_[0]->{sock} && $_[0]->{sock}->connected;
    shift->{connected};
}

sub need_to_send {
    # 送るべきデータがあれば1、無ければundefを返します。
    $_[0]->{sendbuf} eq '' ? undef : 1;
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
	my $filtered = RunLoop->shared->apply_filters(
	    [$msg], 'message_io_hook', $this, 'out');
	foreach (@$filtered) {
	    $data_to_send .= $_->serialize($encoding)."\x0d\x0a";
	}
	#$data_to_send = $msg->serialize($encoding)."\x0d\x0a";
    }
    else {
	die "IrcIO::send_message : parameter msg was invalid; $msg\n";
    }
    
    if ($this->{sock}) {
	$this->{sendbuf} .= $data_to_send;
    }
    else {
	die "IrcIO::send_message : socket is not connected.\n";
    }
}

sub send {
    my $this = shift;
    # このメソッドはソケットに送れるだけのメッセージを送ります。
    # 送信の準備が整っていなかった場合は、このメソッドは操作をブロックします。
    # それがまずいのなら予めselectで書き込める事を確認しておいて下さい。
    if (!defined $this->{sock} || !$this->connected || !$this->{sock}->connected) {
	#die "Irc::send : socket is not connected.\n";
	return;
    }

    #my $bytes_sent = $this->{sock}->send($this->{sendbuf}) || 0;
    my $bytes_sent = $this->{sock}->syswrite($this->{sendbuf}, length($this->{sendbuf})) || 0;
    $this->{sendbuf} = substr($this->{sendbuf},$bytes_sent);

    if ($this->{disconnect_after_writing} &&
	$this->{sendbuf} eq '') {
	$this->disconnect;
    }
}

sub receive {
    my ($this,$encoding) = @_;
    # このメソッドはIRCメッセージを一行ずつ受け取り、IRCMessageのインスタンスをキューに溜めます。
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
	# CRLFまたはLFが行の終わり。	
	my $newline_pos = index($this->{recvbuf},"\x0a");
	if ($newline_pos == -1) {
	    # 一行分のデータが届いていない。
	    last;
	}

	my $current_line = substr($this->{recvbuf},0,$newline_pos);
	$this->{recvbuf} = substr($this->{recvbuf},$newline_pos+1);

	# CRLFだった場合、末尾にCRが付いているので取る。
	$current_line =~ s/\x0d$//;

	# message_io_hook
	my $msg = IRCMessage->new(
	    Line => $current_line, Encoding => $encoding);
	my $filtered = RunLoop->shared->apply_filters(
	    [$msg], 'message_io_hook', $this, 'in');
	
	foreach (@$filtered) {
	    push @{$this->{recv_queue}}, $_;
	}
	#push @{$this->{recv_queue}},IRCMessage->new(
	#    Line => $current_line, Encoding => $encoding);
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
	return splice @{$this->{recv_queue}},0,1;
    }
}

1;
