# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IrcIO��IRC�����С����ϥ��饤����Ȥ���³����IRC��å����������ꤹ����ݥ��饹�Ǥ���
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
    
    if ($this->connected) {
	$this->append($data_to_send);
    }
    else {
	die "IrcIO::send_message : socket is not connected.\n";
    }
}

sub read {
    my ($this,$encoding) = @_;
    # ���Υ᥽�åɤ�IRC��å��������Ԥ��ļ�����ꡢIRCMessage�Υ��󥹥��󥹤򥭥塼��ί��ޤ���
    # �����åȤ��ɤ��ǡ�������Ƥ��ʤ��ä���硢���Υ᥽�åɤ��ɤ��褦�ˤʤ�ޤ�
    # ����֥�å����ޤ������줬�ޤ�������ͽ��select���ɤ������ǧ���Ƥ����Ʋ�������
    # ���Υ᥽�åɤ�¹Ԥ������ȤǻϤ�ƥ����åȤ��Ĥ���줿����ʬ���ä����ϡ�
    # �᥽�åɼ¹Ը夫���connected�᥽�åɤ������֤��褦�ˤʤ�ޤ���

    $this->SUPER::read;

    while (1) {
	# CRLF�ޤ���LF���Ԥν���ꡣ
	my $newline_pos = index($this->recvbuf,"\x0a");
	if ($newline_pos == -1) {
	    # ���ʬ�Υǡ������Ϥ��Ƥ��ʤ���
	    last;
	}

	my $current_line = substr($this->recvbuf,0,$newline_pos);
	$this->recvbuf(substr($this->recvbuf,$newline_pos+1));

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
	    $_->purge_raw_params;
	    push @{$this->{recv_queue}}, $_;
	}
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
	return shift @{$this->{recv_queue}};
    }
}

1;
