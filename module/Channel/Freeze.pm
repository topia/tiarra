# -----------------------------------------------------------------------------
# $Id: Freeze.pm,v 1.5 2004/02/20 18:09:12 admin Exp $
# -----------------------------------------------------------------------------
# ���Υ⥸�塼��ϺƵ�ư���Ƥ��������򼺤ʤ�ʤ��褦�ˤ���١�
# �����BulletinBoard��frost-channels����¸���ޤ���
# -----------------------------------------------------------------------------
package Channel::Freeze;
use strict;
use warnings;
use base qw/Module/;
use Multicast;
use Timer;
use BulletinBoard;
use Mask;
use Configuration;

sub new {
    my $class = shift;
    
    my $this = $class->SUPER::new;
    $this->{reminder_timer} = undef; # Timer
    $this->set_timer_if_required;
    
    $this;
}

sub destruct {
    my $this = shift;
    if (defined $this->{reminder_timer}) {
	$this->{reminder_timer}->uninstall;
	$this->{reminder_timer} = undef;
    }
}

sub set_timer_if_required {
    my $this = shift;
    if (defined $this->{reminder_timer}) {
	# ���˥����ޡ������äƤ��롣
	return;
    }

    if (!$this->config->reminder_interval) {
	# ��𤷤ʤ��䤦�����ꤵ��Ƥ��롣
	return;
    }

    my $channels = BulletinBoard->shared->frost_channels;
    if (defined $channels && keys(%$channels) > 0) {
	# �Ǽ��Ĥ˾���ͭ�롣
	$this->{reminder_timer} = Timer->new(
	    Interval => 60 * $this->config->reminder_interval,
	    Repeat => 1,
	    Code => sub {
		$this->notify_list_of_frost_channels;
	    })->install;
	#::printmsg("Channel::Freeze - timer installed");
    }
}

sub notify_list_of_frost_channels {
    my ($this) = @_;
    my $channels = BulletinBoard->shared->frost_channels;
    if (defined $channels && keys(%$channels) > 0) {
	# ������Ƥ���
	my $msg = "These channels are frost: ".join(', ',keys %$channels);
	if (length($msg) > 400) {
	    # 400�Х��Ȥ�ۤ������ڤ�ͤ�롣
	    $msg = substr($msg, 0, 400)."...";
	}
	
	# ���
	RunLoop->shared->broadcast_to_clients(
	    IRCMessage->new(
		do {
		    if (Configuration->shared->general->omit_sysmsg_prefix_when_possible) {
			();
		    }
		    else {
			(Prefix => Configuration->shared_conf->general->sysmsg_prefix);
		    }
		},
		Command => 'NOTICE',
		Params => [
		    RunLoop->shared->current_nick,
		    $msg]
	    )
	);
    }
}

sub message_arrived {
    my ($this, $msg, $sender) = @_;
    
    if ($sender->client_p) {
	# ���ޥ�ɤ����Ϥ���
	my $notify = sub {
	    my $notice = shift;
	    RunLoop->shared->broadcast_to_clients(
		IRCMessage->new(
		    do {
			if (Configuration->shared->general->omit_sysmsg_prefix_when_possible) {
			    ();
			}
			else {
			    (Prefix => Configuration->shared_conf->general->sysmsg_prefix);
			}
		    },
		    Command => 'NOTICE',
		    Params => [
			RunLoop->shared->current_nick,
			$notice]
		)
	    );
	};
	
	if ($msg->command eq uc($this->config->freeze_command || 'freeze')) {
	    # ���
	    if (my @frost = $this->freeze($msg->param(0))) {
		$notify->("Channel ".join(', ', @frost)." frost.");
	    }
	    $msg = undef; # �Τ�
	}
	elsif ($msg->command eq uc($this->config->defrost_command || 'defrost')) {
	    # ����
	    if (my @defrost = $this->defrost($msg->param(0))) {
		$notify->("Channel ".join(', ', @defrost)." defrost.");
	    }
	    $msg = undef; # �Τ�
	}
    }
    else {
	# PRIVMSG��NOTICE����
	if ($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE') {
	    # ��뤵��Ƥ������ͥ뤬¸�ߤ��뤫��
	    my $board = BulletinBoard->shared;
	    my $channels = $board->frost_channels;
	    if (defined $channels) {
		# ��뤵��Ƥ������ͥ뤫��
		if ($channels->{$msg->param(0)}) {
		    # do-not-send-to-clients���դ��롣
		    $msg->remark('do-not-send-to-clients', 1);
		}
	    }
	}
    }

    $msg;
}

sub normalize {
    my ($ch_full) = @_;
    my ($ch_short, $network_name) = Multicast::detach($ch_full);
    if (Multicast::channel_p($ch_short)) {
	# �����ͥ�̾�Ȥ��Ƶ�����롣
	Multicast::attach($ch_short, $network_name);
    }
    else {
	# ������ʤ���
	undef;
    }
}

sub freeze {
    # ���Ť�freeze�θƽФ��ǥե꡼�����줿�����ͥ�̾��������֤���
    my ($this, $ch_mask) = @_;

    if (!defined $ch_mask) {
	# �ꥹ��ɽ��
	$this->notify_list_of_frost_channels;
	return ();
    }

    if (defined $ch_mask) {
	my $board = BulletinBoard->shared;
	my $channels = $board->frost_channels;
	
	if (!defined $channels) {
	    # �ޤ��Ǽ��Ĥ����ĤƤ�ʤ���
	    $channels = {}; # {�ե�����ͥ�̾ => 1}
	    $board->frost_channels($channels);
	}
	
	# ���ƤΥ����С��Ρ����Ƥ�join���Ƥ�������ͥ���椫�顢
	# ���Υޥ����˳�����������ͥ�̾��õ��������freeze���롣
	my @ch_to_freeze;
	foreach my $network (RunLoop->shared->networks_list) {
	    foreach my $ch ($network->channels_list) {
		my $longname = Multicast::attach($ch, $network);
		if (Mask::match($ch_mask, $longname)) {
		    if (!$channels->{$longname}) {
			$channels->{$longname} = 1;
			push @ch_to_freeze, $longname;
		    }
		}
	    }
	}

	# ɬ�פʤ饿���ޡ���ư��
	$this->set_timer_if_required;

	return @ch_to_freeze;
    }
    else {
	return ();
    }
}

sub defrost {
    my ($this, $ch_mask) = @_;
    if (!defined $ch_mask) {
	return ();
    }

    my @result;

    if (defined $ch_mask) {
	my $board = BulletinBoard->shared;
	my $channels = $board->frost_channels;

	if (!defined $channels) {
	    return; # ������뤵��Ƥ��ʤ���
	}

	%$channels = map {
	    $_ => 1;
	} grep {
	    my $ch_full = $_;
	    if (Mask::match($ch_mask, $ch_full)) {
		push @result, $ch_full;
		0;
	    }
	    else {
		1;
	    }
	} keys %$channels;

	if (keys(%$channels) == 0) {
	    # ��뤵�줿�����ͥ�Ϥ⤦̵����
	    if (defined $this->{reminder_timer}) {
		$this->{reminder_timer}->uninstall;
		$this->{reminder_timer} = undef;
	    }
	    #::printmsg("Channel::Freeze - timer DELETED");
	}
    }

    @result;
}

1;
