# -----------------------------------------------------------------------------
# $Id: Freeze.pm,v 1.5 2004/02/20 18:09:12 admin Exp $
# -----------------------------------------------------------------------------
# このモジュールは再起動しても凍結設定を失なわないようにする為、
# 設定をBulletinBoardのfrost-channelsに保存します。
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
	# 既にタイマーが入っている。
	return;
    }

    if (!$this->config->reminder_interval) {
	# 報告しないやうに設定されている。
	return;
    }

    my $channels = BulletinBoard->shared->frost_channels;
    if (defined $channels && keys(%$channels) > 0) {
	# 掲示板に情報が有る。
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
	# 報告内容を作る
	my $msg = "These channels are frost: ".join(', ',keys %$channels);
	if (length($msg) > 400) {
	    # 400バイトを越えたら切り詰める。
	    $msg = substr($msg, 0, 400)."...";
	}
	
	# 報告
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
	# コマンドの入力か？
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
	    # 凍結
	    if (my @frost = $this->freeze($msg->param(0))) {
		$notify->("Channel ".join(', ', @frost)." frost.");
	    }
	    $msg = undef; # 捨て
	}
	elsif ($msg->command eq uc($this->config->defrost_command || 'defrost')) {
	    # 解凍
	    if (my @defrost = $this->defrost($msg->param(0))) {
		$notify->("Channel ".join(', ', @defrost)." defrost.");
	    }
	    $msg = undef; # 捨て
	}
    }
    else {
	# PRIVMSGやNOTICEか？
	if ($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE') {
	    # 凍結されてゐるチャンネルが存在するか？
	    my $board = BulletinBoard->shared;
	    my $channels = $board->frost_channels;
	    if (defined $channels) {
		# 凍結されてゐるチャンネルか？
		if ($channels->{$msg->param(0)}) {
		    # do-not-send-to-clientsを付ける。
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
	# チャンネル名として許される。
	Multicast::attach($ch_short, $network_name);
    }
    else {
	# 許されない。
	undef;
    }
}

sub freeze {
    # 今囘のfreezeの呼出しでフリーズされたチャンネル名の配列を返す。
    my ($this, $ch_mask) = @_;

    if (!defined $ch_mask) {
	# リスト表示
	$this->notify_list_of_frost_channels;
	return ();
    }

    if (defined $ch_mask) {
	my $board = BulletinBoard->shared;
	my $channels = $board->frost_channels;
	
	if (!defined $channels) {
	    # まだ掲示板に入つてゐない。
	    $channels = {}; # {フルチャンネル名 => 1}
	    $board->frost_channels($channels);
	}
	
	# 全てのサーバーの、全てのjoinしているチャンネルの中から、
	# このマスクに該当するチャンネル名を探し、全てfreezeする。
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

	# 必要ならタイマー起動。
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
	    return; # 何も凍結されていない。
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
	    # 凍結されたチャンネルはもう無い。
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
