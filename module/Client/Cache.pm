# -----------------------------------------------------------------------------
# $Id: Cache.pm,v 1.6 2004/03/09 07:48:12 topia Exp $
# -----------------------------------------------------------------------------
package Client::Cache;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use NumericReply;

sub _yesno {
    my ($this, $value, $default) = @_;

    return $default || 0 if (!defined $value);
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # ����Ƚ��
    return 0;
}

sub destruct {
    my ($this) = shift;
    # cleaning remarks

    # �����ͥ�ˤĤ��Ƥ��� remark ������
    foreach my $network (RunLoop->shared_loop->networks_list) {
	foreach my $ch ($network->channels_list) {
	    $ch->remark("__PACKAGE__/fetching-switches", undef, 'delete');
	    $ch->remark("__PACKAGE__/fetching-who", undef, 'delete');
	}
    }

    # ���饤����ȤˤĤ��Ƥ�ΤϺ�����ʤ���
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
		$ch->remark("__PACKAGE__/fetching-switches", 1);
	    }
	} elsif ($type eq 'in' &&
		     $msg->command eq RPL_CHANNELMODEIS &&
			 Multicast::channel_p($msg->param(1))) {
	    my $ch = $io->channel($msg->param(1));
	    if (defined $ch) {
		$ch->remark("__PACKAGE__/fetching-switches", undef, 'delete');
	    }
	} elsif ($type eq 'out' &&
		     $msg->command eq 'WHO' &&
			 Multicast::channel_p($msg->param(0))) {
	    my $ch = $io->channel($msg->param(0));
	    if (defined $ch) {
		$ch->remark("__PACKAGE__/fetching-who", 1);
	    }
	} elsif ($type eq 'in' &&
		     $msg->command eq RPL_WHOREPLY &&
			 Multicast::channel_p($msg->param(1))) {
	    # �������Թ�塢��ĤǤⵢ�äƤ��������Ǽ��ä���
	    my $ch = $io->channel($msg->param(1));
	    if (defined $ch) {
		$ch->remark("__PACKAGE__/fetching-who", undef, 'delete');
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
	if ($msg->command eq 'MODE' &&
		$this->_yesno($this->config->use_mode_cache) &&
		    Multicast::channel_p($msg->param(0)) &&
			    !defined $msg->param(1)) {
	    my $chan_long = $msg->param(0);
	    my ($chan_short, $network_name) = Multicast::detach($chan_long);
	    my $network = RunLoop->shared_loop->network($network_name);
	    unless (defined $network) {
		::debug_printmsg(
		    __PACKAGE__.': "'.$network_name.
			'" network is not found in tiarra.'
		       );
		last;
	    }
	    my $ch = $network->channel($chan_short);
	    last if !defined $ch;
	    if ($ch->remark('switches-are-known')) {
		my $remark = $sender->remark('mode-cache-used') || {};
		if (!exists $remark->{$chan_long}) {
		    $sender->send_message(
			IRCMessage->new(
			    Prefix => RunLoop->shared_loop->sysmsg_prefix('system'),
			    Command => RPL_CHANNELMODEIS,
			    Params => [
				RunLoop->shared_loop->current_nick,
				$chan_long,
				$ch->mode_string,
			       ],
			    Remarks => {
				'fill-prefix-when-sending-to-client' => 1,
			    },
			   )
		       );
		    $remark->{$chan_long} = 1;
		    $sender->remark('mode-cache-used', $remark);
		    return undef;
		}
	    } else {
		if ($ch->remark("__PACKAGE__/fetching-switches")) {
		    # �������Ƥ��륯�饤����Ȥ�����ʤ顢����Ͼä���
		    return undef;
		}
		# �������ˤ��äƤ�餦��
	    }
	} elsif ($msg->command eq 'WHO' &&
		     $this->_yesno($this->config->use_who_cache) &&
			 Multicast::channel_p($msg->param(0))) {
	    my $chan_long = $msg->param(0);
	    my ($chan_short, $network_name) = Multicast::detach($chan_long);
	    my $network = RunLoop->shared_loop->network($network_name);
	    unless (defined $network) {
		::debug_printmsg(
		    __PACKAGE__.': "'.$network_name.
			'" network is not found in tiarra.'
		       );
		last;
	    }
	    my $ch = $network->channel($chan_short);
	    last unless (defined $ch);
	    my $remark = $sender->remark('who-cache-used') || {};
	    if (!exists $remark->{$chan_long}) {
		# cache ������äƤ��뤫�狼��ʤ����ᡢ
		# �Ȥꤢ������äƤߤơ�­��ʤ��ä��餢�����롣
		my $message_tmpl = IRCMessage->new(
		    Prefix => RunLoop->shared_loop->sysmsg_prefix('system'),
		    Command => RPL_WHOREPLY,
		    Params => [
			RunLoop->shared_loop->current_nick,
			$chan_long,
		       ],
		   );
		my @messages;
		eval {
		    foreach (values %{$ch->names}) {
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
								   $network));
			$message->param(6,
					(length($p->away) ? 'G' : 'H') .
					    $p_ch->priv_symbol);
			$message->param(7,
					$network->remark('server-hops')
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
		    $remark->{$chan_long} = 1;
		    $sender->remark('who-cache-used', $remark);
		    return undef;
		} else {
		    if ($ch->remark("__PACKAGE__/fetching-who")) {
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
