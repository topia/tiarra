# -----------------------------------------------------------------------------
# $Id: Cache.pm,v 1.1 2004/02/14 11:48:20 topia Exp $
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
    return 1 if ($value); # 数値判定
    return 0;
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
		RunLoop->shared_loop->notify_warn(
		    __PACKAGE__.': "'.$network_name.
			'" network is not found in tiarra.'
		       ) if ::debug_mode;
		last;
	    }
	    my $ch = $network->channel($chan_short);
	    last unless (defined $ch && $ch->remark('switches-are-known'));
	    my $remark = $sender->remark('mode-cache-used') || {};
	    if (!exists $remark->{$chan_long}) {
		$sender->send_message(
		    IRCMessage->new(
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
	} elsif ($msg->command eq 'WHO' &&
		     $this->_yesno($this->config->use_who_cache) &&
			 Multicast::channel_p($msg->param(0))) {
	    my $chan_long = $msg->param(0);
	    my ($chan_short, $network_name) = Multicast::detach($chan_long);
	    my $network = RunLoop->shared_loop->network($network_name);
	    unless (defined $network) {
		RunLoop->shared_loop->notify_warn(
		    __PACKAGE__.': "'.$network_name.
			'" network is not found in tiarra.'
		       ) if ::debug_mode;
		last;
	    }
	    my $ch = $network->channel($chan_short);
	    last unless (defined $ch);
	    my $remark = $sender->remark('who-cache-used') || {};
	    if (!exists $remark->{$chan_long}) {
		# cache がそろっているかわからないため、
		# とりあえず作ってみて、足りなかったらあきらめる。
		my $message_tmpl = IRCMessage->new(
		    Command => RPL_WHOREPLY,
		    Params => [
			RunLoop->shared_loop->current_nick,
			$chan_long,
		       ],
		    Remarks => {
			'fill-prefix-when-sending-to-client' => 1,
		    },
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
			    RunLoop->shared_loop->notify_warn(
				__PACKAGE__.': cache data not enough: '.$p->info.
				    ' on '.$p->server) if ::debug_mode;
			    die 'cache data not enough';
			}

			my $message = $message_tmpl->clone(deep => 1);
			$message->param(2, $p->username);
			$message->param(3, $p->userhost);
			$message->param(4, $p->server);
			$message->param(5, $p->nick);
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
		}
	    }
	}
	last;
    }

    return $msg;
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
