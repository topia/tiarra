# -----------------------------------------------------------------------------
# $Id: Cache.pm,v 1.9 2004/04/18 07:44:47 topia Exp $
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::Cache;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use NumericReply;

sub MODE_CACHE_FORCE_SENDED (){0;}
sub MODE_CACHE_SENDED (){1;}

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{hook} = IrcIO::Client::Hook->new(
	sub {
	    my ($hook, $client, $ch_name, $network, $ch) = @_;
	    if ($ch->remark('switches-are-known') &&
		    $this->_yesno($this->config->use_mode_cache)) {
		# �����Ǥ�����϶���Ū���������Ƥߤ�
		my $remark = $client->remark('mode-cache-state') || {};
		_send_mode_cache($client,$ch_name,$ch);
		$remark->{
		    Multicast::attach($ch->name, $network)
		       }->[MODE_CACHE_FORCE_SENDED] = 1;
		$client->remark('mode-cache-state', $remark);
	    }
	})->install('channel-info');
    $this;
}

sub destruct {
    my ($this) = shift;

    # hook ����
    $this->{hook} and $this->{hook}->uninstall;

    # �����ͥ�ˤĤ��Ƥ��� remark ������
    foreach my $network (RunLoop->shared_loop->networks_list) {
	foreach my $ch ($network->channels_list) {
	    $ch->remark(__PACKAGE__."/fetching-switches", undef, 'delete');
	    $ch->remark(__PACKAGE__."/fetching-who", undef, 'delete');
	}
    }

    # ���饤����ȤˤĤ��Ƥ�ΤϺ�����ʤ���
}

sub _yesno {
    my ($this, $value, $default) = @_;

    return $default || 0 if (!defined $value);
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # ����Ƚ��
    return 0;
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Server')) {
	if ($type eq 'out' &&
		$msg->command eq 'MODE' &&
		    Multicast::channel_p($msg->param(0)) &&
			    !defined $msg->param(1)) {
	    my $ch = $io->channel($msg->param(0));
	    if (defined $ch) {
		$ch->remark(__PACKAGE__."/fetching-switches", 1);
	    }
	} elsif ($type eq 'in' &&
		     $msg->command eq RPL_CHANNELMODEIS &&
			 Multicast::channel_p($msg->param(1))) {
	    my $ch = $io->channel($msg->param(1));
	    if (defined $ch) {
		$ch->remark(__PACKAGE__."/fetching-switches", undef, 'delete');
	    }
	} elsif ($type eq 'out' &&
		     $msg->command eq 'WHO' &&
			 Multicast::channel_p($msg->param(0))) {
	    my $ch = $io->channel($msg->param(0));
	    if (defined $ch) {
		$ch->remark(__PACKAGE__."/fetching-who", 1);
	    }
	} elsif ($type eq 'in' &&
		     $msg->command eq RPL_WHOREPLY &&
			 Multicast::channel_p($msg->param(1))) {
	    # �������Թ�塢��ĤǤⵢ�äƤ��������Ǽ��ä���
	    my $ch = $io->channel($msg->param(1));
	    if (defined $ch) {
		$ch->remark(__PACKAGE__."/fetching-who", undef, 'delete');
	    }
	}
    }
    return $msg;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # ����Ϥ���Ƥ����� last ��ȴ����
    while (1) {
	# ���饤����Ȥ���Υ�å���������
	last unless ($sender->isa('IrcIO::Client'));
	# ư��ϵ��Ĥ���Ƥ��뤫?
	last unless ((!defined $sender->option('no-cache')) ||
			 !$this->_yesno($sender->option('no-cache')));
	my $fetch_channel_info = sub {
	    my %ret;
	    $ret{chan_long} = shift;
	    ($ret{chan_short}, $ret{network_name}) =
		Multicast::detach($ret{chan_long});
	    $ret{network} = RunLoop->shared_loop->network($ret{network_name});
	    unless (defined $ret{network}) {
	    } else {
		$ret{ch} = $ret{network}->channel($ret{chan_short});
		$ret{chan_send} = RunLoop->shared_loop->multi_server_mode_p ?
		    $ret{chan_long} : $ret{chan_short};
	    }
	    return %ret;
	};
	if ($msg->command eq 'MODE' &&
		$this->_yesno($this->config->use_mode_cache) &&
		    Multicast::channel_p($msg->param(0)) &&
			    !defined $msg->param(1)) {
	    my %info = $fetch_channel_info->($msg->param(0));
	    unless (defined $info{network}){
		::debug_printmsg(
		    __PACKAGE__.': "'.$info{network_name}.
			'" network is not found in tiarra.'
		       );
		last;
	    }
	    last if !defined $info{ch};
	    if ($info{ch}->remark('switches-are-known')) {
		my $remark = $sender->remark('mode-cache-state') || {};
		my $ch_remark = $remark->{$info{chan_long}};
		if (!$ch_remark->[MODE_CACHE_SENDED]) {
		    _send_mode_cache($sender,
				     $info{chan_send},
				     $info{ch})
			if (!$ch_remark->[MODE_CACHE_FORCE_SENDED]);
		    $ch_remark->[MODE_CACHE_SENDED] = 1;
		    $sender->remark('mode-cache-state', $remark);
		    return undef;
		}
	    } else {
		if ($info{ch}->remark(__PACKAGE__."/fetching-switches")) {
		    # �������Ƥ��륯�饤����Ȥ�����ʤ顢����Ͼä���
		    return undef;
		}
		# �������ˤ��äƤ�餦��
	    }
	} elsif ($msg->command eq 'WHO' &&
		     $this->_yesno($this->config->use_who_cache) &&
			 Multicast::channel_p($msg->param(0))) {
	    my %info = $fetch_channel_info->($msg->param(0));
	    unless (defined $info{network}){
		::debug_printmsg(
		    __PACKAGE__.': "'.$info{network_name}.
			'" network is not found in tiarra.'
		       );
		last;
	    }
	    last if !defined $info{ch};
	    my $remark = $sender->remark('who-cache-used') || {};
	    if (!exists $remark->{$info{chan_long}}) {
		# cache ������äƤ��뤫�狼��ʤ����ᡢ
		# �Ȥꤢ������äƤߤơ�­��ʤ��ä��餢�����롣
		my $message_tmpl = IRCMessage->new(
		    Prefix => RunLoop->shared_loop->sysmsg_prefix('system'),
		    Command => RPL_WHOREPLY,
		    Params => [
			RunLoop->shared_loop->current_nick,
			$info{chan_send},
		       ],
		   );
		my @messages;
		eval {
		    foreach (values %{$info{ch}->names}) {
			my $p_ch = $_;
			my $p = $p_ch->person;

			# �������ƽ��פǤʤ��塢
			# ��¤����ñ�ʥǡ�������¤���ޤ���
			# ��դ��Ƥ���������
			if (!$p->username || !$p->userhost ||
				!$p->realname || !$p->server) {
			    # �ǡ�����­���������롣
			    die 'cache data not enough';
			}

			my $message = $message_tmpl->clone(deep => 1);
			$message->param(2, $p->username);
			$message->param(3, $p->userhost);
			$message->param(4, $p->server);
			$message->param(5,
					Multicast::global_to_local($p->nick,
								   $info{network}));
			$message->param(6,
					(length($p->away) ? 'G' : 'H') .
					    $p_ch->priv_symbol);
			$message->param(7,
					$info{network}->remark('server-hops')
					    ->{$p->server}.' '.
						$p->realname);
			push(@messages, $message);
		    }
		};
		if (!$@) {
		    my $message = $message_tmpl->clone(deep => 1);
		    $message->command(RPL_ENDOFWHO);
		    $message->param(2, 'End of WHO list.');
		    push(@messages, $message);
		    map {
			$sender->send_message($_);
		    } @messages;
		    $remark->{$info{chan_long}} = 1;
		    $sender->remark('who-cache-used', $remark);
		    return undef;
		} else {
		    if ($info{ch}->remark(__PACKAGE__."/fetching-who")) {
			# �������Ƥ��륯�饤����Ȥ�����ʤ顢����Ͼä����ؾ衣
			return undef;
		    }
		    # �������ˤ��äƤ�餦��
		}
	    }
	}
	last;
    }

    return $msg;
}


sub _send_mode_cache {
    my ($sendto,$ch_name,$ch) = @_;

    $sendto->send_message(
	IRCMessage->new(
	    Prefix => RunLoop->shared_loop->sysmsg_prefix('system'),
	    Command => RPL_CHANNELMODEIS,
	    Params => [
		RunLoop->shared_loop->current_nick,
		$ch_name,
		$ch->mode_string,
	       ],
	    Remarks => {
		'fill-prefix-when-sending-to-client' => 1,
	    },
	   )
       );
    if (defined $ch->remark('creation-time')) {
	$sendto->send_message(
	    IRCMessage->new(
		Prefix => RunLoop->shared_loop->sysmsg_prefix('system'),
		Command => RPL_CREATIONTIME,
		Params => [
		    RunLoop->shared_loop->current_nick,
		    $ch_name,
		    $ch->remark('creation-time'),
		   ],
		Remarks => {
		    'fill-prefix-when-sending-to-client' => 1,
		},
	       )
	   );
    }
}

1;
=pod
info: �ǡ����򥭥�å��夷�ƥ����Ф��䤤��碌�ʤ��褦�ˤ���
default: off

# ����å������Ѥ��Ƥ⡢�Ȥ���Τ���³��ǽ�ΰ��٤����Ǥ���
# �����ܤ�����̾��̤�˥����Ф��䤤��碌�ޤ���
# �ޤ������饤����ȥ��ץ����� no-cache ����ꤹ���ư���ޤ���

# mode ����å������Ѥ��뤫
use-mode-cache: 1

# who ����å������Ѥ��뤫
use-who-cache: 1
=cut
