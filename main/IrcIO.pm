# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IrcIO��IRC�����С����ϥ��饤����Ȥ���³����IRC��å����������ꤹ����ݥ��饹�Ǥ���
# -----------------------------------------------------------------------------
package IrcIO;
use strict;
use warnings;
use Carp;
use IO::Socket::INET;
use Configuration;
use IRCMessage;
use Exception;
use Tiarra::ShorthandConfMixin;
use Tiarra::Utils;

sub new {
    my ($class, $runloop) = @_;
    carp 'runloop is not specified!' unless defined $runloop;
    my $obj = {
	runloop => $runloop,
	sock => undef, # IO::Socket::INET
	connected => undef, # �ɤ���$sock->connected�Ͽ��ѽ���ʤ���
	sendbuf => '',
	recvbuf => '',
	recv_queue => [],
	disconnect_after_writing => 0,
	remarks => {},
    };
    bless $obj,$class;
}

Tiarra::Utils->define_attr_getter(0, qw(sock connected sendbuf recvbuf),
				  [qw(_runloop runloop)]);

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
    $this->sock->shutdown(2);
    $this->{connected} = undef;
    $this->_runloop->unregister_receive_socket($this->{sock});
    $this->{sock} = undef;
}

sub length { length(shift->sendbuf); }
# ����٤��ǡ����������1��̵�����0���֤��ޤ���
sub need_to_send { (shift->length > 0); }

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
    # �ǡ���������褦��ͽ�󤹤롣�����åȤ������ν��������äƤ��ʤ��Ƥ�֥�å����ʤ���
    
    # msg������ʸ����Ǥ��ɤ���IRCMessage�Υ��󥹥��󥹤Ǥ��ɤ���
    # ����ʸ������Ϥ����ˤϡ�������CRLF���դ��ƤϤʤ�ʤ���
    # �ޤ�������ʸ����ˤĤ��Ƥ�ʸ�������ɤ��Ѵ����Ԥʤ��ʤ���
    my $data_to_send = '';
    if (ref($msg) eq '') {
	# deprecated.
	# FIXME: warn���٤���������
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
    
    if ($this->{sock}) {
	$this->{sendbuf} .= $data_to_send;
    }
    else {
	die "IrcIO::send_message : socket is not connected.\n";
    }
}

sub send {
    my $this = shift;
    # ���Υ᥽�åɤϥ����åȤ����������Υ�å�����������ޤ���
    # �����ν��������äƤ��ʤ��ä����ϡ����Υ᥽�åɤ�����֥�å����ޤ���
    # ���줬�ޤ����Τʤ�ͽ��select�ǽ񤭹��������ǧ���Ƥ����Ʋ�������
    if (!defined $this->{sock} || !$this->connected || !$this->{sock}->connected) {
	#die "Irc::send : socket is not connected.\n";
	return;
    }

    #my $bytes_sent = $this->{sock}->send($this->{sendbuf}) || 0;
    my $bytes_sent = $this->sock->syswrite($this->sendbuf, $this->length) || 0;
    substr($this->{sendbuf}, 0, $bytes_sent) = '';

    if ($this->{disconnect_after_writing} &&
	    !$this->need_to_send) {
	$this->disconnect;
    }
}

sub receive {
    my ($this,$encoding) = @_;
    # ���Υ᥽�åɤ�IRC��å��������Ԥ��ļ�����ꡢIRCMessage�Υ��󥹥��󥹤򥭥塼��ί��ޤ���
    # �����åȤ��ɤ��ǡ�������Ƥ��ʤ��ä���硢���Υ᥽�åɤ��ɤ��褦�ˤʤ�ޤ�
    # ����֥�å����ޤ������줬�ޤ�������ͽ��select���ɤ������ǧ���Ƥ����Ʋ�������
    # ���Υ᥽�åɤ�¹Ԥ������ȤǻϤ�ƥ����åȤ��Ĥ���줿����ʬ���ä����ϡ�
    # �᥽�åɼ¹Ը夫���connected�᥽�åɤ������֤��褦�ˤʤ�ޤ���
    if (!defined($this->sock) || !$this->connected) {
	# die "IrcIO::receive : socket is not connected.\n";
	$this->disconnect;
	return ();
    }
    
    my $recvbuf = '';
    sysread($this->sock,$recvbuf,4096); # �Ȥꤢ���������4096�Х��Ȥ��ɤ�
    if ($recvbuf eq '') {
	# �����åȤ��Ĥ����Ƥ�����
	$this->disconnect;
    }
    else {
	$this->{recvbuf} .= $recvbuf;
    }
    
    while (1) {
	# CRLF�ޤ���LF���Ԥν���ꡣ	
	my $newline_pos = index($this->recvbuf,"\x0a");
	if ($newline_pos == -1) {
	    # ���ʬ�Υǡ������Ϥ��Ƥ��ʤ���
	    last;
	}

	my $current_line = substr($this->recvbuf,0,$newline_pos);
	$this->{recvbuf} = substr($this->recvbuf,$newline_pos+1);

	# CRLF���ä���硢������CR���դ��Ƥ���ΤǼ�롣
	$current_line =~ s/\x0d$//;

	if (CORE::length($current_line) == 0) {
	    # ���Ԥϥ����å�
	    next;
	}

	# message_io_hook
	my $msg = IRCMessage->new(
	    Line => $current_line, Encoding => $encoding);
	my $filtered = $this->_runloop->apply_filters(
	    [$msg], 'message_io_hook', $this, 'in');
	
	foreach (@$filtered) {
	    push @{$this->{recv_queue}}, $_;
	}
	#push @{$this->{recv_queue}},IRCMessage->new(
	#    Line => $current_line, Encoding => $encoding);
    }
}

sub pop_queue {
    # ���Υ᥽�åɤϼ������塼��κǤ�Ť���Τ���Ф��ޤ���
    # ���塼�����ʤ�QueueIsEmptyException���ꤲ�ޤ���
    my ($this) = @_;
    if (@{$this->{recv_queue}} == 0) {
	QueueIsEmptyException->new->throw;
    }
    else {
	return splice @{$this->{recv_queue}},0,1;
    }
}

1;
