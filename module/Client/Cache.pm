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

sub MODE_CACHE_FORCE_SENDED (){0;}
sub MODE_CACHE_SENDED (){1;}

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{hook} = IrcIO::Client::Hook->new(
	sub {
	    my ($hook, $client, $ch_name, $network, $ch) = @_;
	    if ($ch->remark('switches-are-known')) {
		# 送信できる場合は強制的に送信してみる
		my $remark = $client->remark('mode-cache-state') || {};
		_send_mode_cache($client,$ch_name,$ch);
		$remark->{$ch_name}->[MODE_CACHE_FORCE_SENDED] = 1;
		$client->remark('mode-cache-state', $remark);
	    }
	})->install('channel-info');
    $this;
}

sub destruct {
    my ($this) = shift;

    # hook を解除
    $this->{hook} and $this->{hook}->uninstall;

    # チャンネルについている remark を削除。
    foreach my $network (RunLoop->shared_loop->networks_list) {
	foreach my $ch ($network->channels_list) {
	    $ch->remark("__PACKAGE__/fetching-switches", undef, 'delete');
	    $ch->remark("__PACKAGE__/fetching-who", undef, 'delete');
	}
    }

    # クライアントについてるのは削除しない。
}

sub _yesno {
    my ($this, $value, $default) = @_;

    return $default || 0 if (!defined $value);
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # 数値判定
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
	    # 処理の都合上、一つでも帰ってきた時点で取り消し。
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

    # 条件をはずれていたら last で抜ける
    while (1) {
	# クライアントからのメッセージか？
	last unless ($sender->isa('IrcIO::Client'));
	# 動作は許可されているか?
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
		my $remark = $sender->remark('mode-cache-state') || {};
		if (!$remark->{$chan_long}->[MODE_CACHE_SENDED]) {
		    _send_mode_cache($sender,$chan_long,$ch)
			if (!$remark->{$chan_long}
				->[MODE_CACHE_FORCE_SENDED]);
		    $remark->{$chan_long}->[MODE_CACHE_SENDED] = 1;
		    $sender->remark('mode-cache-state', $remark);
		    return undef;
		}
	    } else {
		if ($ch->remark("__PACKAGE__/fetching-switches")) {
		    # 取得しているクライアントがいるなら、今回は消す。
		    return undef;
		}
		# 取得しにいってもらう。
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
		# cache がそろっているかわからないため、
		# とりあえず作ってみて、足りなかったらあきらめる。
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

			# たいして重要でない上、
			# 捏造が簡単なデータは捏造します。
			# 注意してください。
			if (!$p->username || !$p->userhost ||
				!$p->realname || !$p->server) {
			    # データ不足。あきらめる。
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
			# 取得しているクライアントがいるなら、今回は消して便乗。
			return undef;
		    }
		    # 取得しにいってもらう。
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
}

1;
=pod
info: データをキャッシュしてサーバに問い合わせないようにする
default: off

# キャッシュを使用しても、使われるのは接続後最初の一度だけです。
# 二度目からは通常通りにサーバに問い合わせます。
# また、クライアントオプションの no-cache を指定すれば動きません。

# mode キャッシュを使用するか
use-mode-cache: 1

# who キャッシュを使用するか
use-who-cache: 1
=cut
