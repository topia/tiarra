# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package User::Vanish;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
our $DEBUG = 0;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    my $result = $msg;
    if ($sender->server_p) {
	my $method = 'cmd_'.$msg->command;
	if ($this->can($method)) {
	    if ($DEBUG) {
		my $original = $msg->serialize;
		$result = $this->$method($msg, $sender);
		my $filtered = (defined $result ? $result->serialize : '');
		if ($original ne $filtered) {
		    # 内容が書換へられた。
		    my $debug_msg = "'$original' -> '$filtered'";
		    eval {
			substr($debug_msg, 400) = '...';
		    };
		    RunLoop->shared->notify_msg($debug_msg);
		}
	    }
	    else {
		$result = $this->$method($msg, $sender);
	    }
	}
    }
    elsif ($sender->client_p) {
	if ($msg->command eq 'VANISHDEBUG') {
	    $DEBUG = $msg->param(0);
	    RunLoop->shared->notify_msg("User::Vanish - debug-mode ".($DEBUG?'enabled':'disabled'));
	    $result = undef;
	}
    }

    $result;
}

*cmd_NOTICE = \&cmd_PRIVMSG;
sub cmd_PRIVMSG {
    my ($this,$msg,$sender) = @_;

    # 発行元がVanish対象か？
    my $ch_long = $msg->param(0);
    my $ch_short = Multicast::detach($ch_long);
    if (Multicast::nick_p($ch_short)) {
	$ch_long = '#___priv___@'.$sender->network_name;
    }

    if ($this->target_of_vanish_p($msg->prefix,$ch_long)) {
	undef;
    }
    else {
	$msg;
    }
}

sub cmd_JOIN {
    my ($this,$msg,$sender) = @_;
    my @channels; # チャンネルリストを再構成する。
    foreach my $channel (split m/,/,$msg->param(0)) {
	my ($ch_full,$mode) = ($channel =~ m/^([^\x07]+)(?:\x07(.*))?/);
	if (!$this->target_of_vanish_p($msg->prefix,$ch_full)) {
	    push @channels,$channel;
	}
    }

    if (@channels > 0) {
	# 再構成の結果、チャンネルがまだ残ってた。
	$msg->param(0,join(',',@channels));
    }
    else {
	$msg = undef;
    }

    $msg;
}

sub cmd_NJOIN {
    my ($this,$msg,$sender) = @_;
    my $ch_long = $msg->param(0);
    my $ch_short = Multicast::detach($ch_long);
    my $ch = $sender->channel($ch_short);
    if (defined $ch) {
	my @nicks;
	foreach my $mode_and_nick (split m/,/,$msg->param(1)) {
	    my ($mode,$nick) = ($mode_and_nick =~ m/^([@+]*)(.+)$/);
	    my $person = $ch->names($nick);
	    if (!defined $person || !$this->target_of_vanish_p) {
		push @nicks,$mode_and_nick;
	    }
	}

	if (@nicks > 0) {
	    # 再構成の結果、nickがまだ残ってた。
	    $msg->param(1,join(',',@nicks));
	}
	else {
	    $msg = undef;
	}
    }

    $msg;
}

sub cmd_PART {
    my ($this,$msg,$sender) = @_;
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	undef;
    }
    else {
	$msg;
    }
}

sub cmd_INVITE {
    my ($this,$msg,$sender) = @_;
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(1))) {
	undef;
    }
    else {
	$msg;
    }
}

*cmd_QUIT = \&cmd_NICK;
sub cmd_NICK {
    my ($this,$msg,$sender) = @_;

    # 影響を及ぼした全チャンネル名のリストを得る。このリストにはネットワーク名が付いていない。
    my $affected = $msg->remark('affected-channels');
    # 一つでもVanish対象でないチャンネルとnickの組みがあれば、このNICKは破棄しない。
    my $no_vanish;
    foreach (@$affected) {
	my $ch_long = Multicast::attach($_,$sender->network_name);
	if (!$this->target_of_vanish_p($msg->prefix,$ch_long)) {
	    $no_vanish = 1;
	    last;
	}
    }

    if ($no_vanish) {
	$msg;
    }
    else {
	undef;
    }
}

sub cmd_TOPIC {
    my ($this,$msg,$sender) = @_;
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	if ($this->config->drop_topic_by_target) {
	    $msg->prefix('HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH');
	}
    }
    $msg;
}

sub cmd_353 {
    # RPL_NAMREPLY
    my ($this,$msg,$sender) = @_;

    my $ch_long = $msg->param(2);
    my $ch_short = Multicast::detach($ch_long);
    my $ch = $sender->channel($ch_short);
    if (defined $ch) {
	my @nicks;
	foreach my $mode_and_nick (split / /,$msg->param(3)) {
	    my ($mode,$nick) = ($mode_and_nick =~ m/^([@\+]{0,2})(.+)$/);
	    my $person = $ch->names($nick);
	    if (!defined $person || !$this->target_of_vanish_p($person->info,$ch_long)) {
		push @nicks,$mode_and_nick;
	    }
	}
	$msg->param(3,join(' ',@nicks));
    }

    $msg;
}

sub cmd_MODE {
    my ($this,$msg,$sender) = @_;

    # 発行元がVanish対象か？
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	if ($this->config->drop_mode_by_target) {
	    # prefix改竄
	    $msg->prefix('HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH');
	}
    }

    # +o/-o/+v/-vの対象がVanishの対象か？
    my $ch_long = $msg->param(0);
    my $ch_short = Multicast::detach($ch_long);
    my $ch = $sender->channel($ch_short);
    if (defined $ch && (sub{defined$_[0]?$_[0]:1}->($this->config->drop_mode_switch_for_target))) {
	my $n_params = @{$msg->params};
	my $plus = 0; # 現在評価中のモードが+なのか-なのか。
	my $mode_char_pos = 1; # 現在評価中のmode characterの位置。
	my $mode_param_offset = 0; # $mode_char_posから幾つの追加パラメタを拾ったか。

	my $fetch_param = sub {
	    $mode_param_offset++;
	    return $msg->param($mode_char_pos + $mode_param_offset);
	};

	my @params = ($ch_long); # パラメータを再構築する。
	my $add = sub {
	    my ($char,$option) = @_;
	    push @params,($plus ? '+' : '-').$char;
	    if (defined $option) {
		push @params,$option;
	    }
	};

	for (;$mode_char_pos < $n_params;$mode_char_pos += $mode_param_offset + 1) {
	    $mode_param_offset = 0; # これは毎回リセットする。
	    foreach my $c (split //,$msg->param($mode_char_pos)) {
		if ($c eq '+') {
		    $plus = 1;
		}
		elsif ($c eq '-') {
		    $plus = 0;
		}
		elsif (index('bIk',$c) != -1) {
		    $add->($c,$fetch_param->());
		}
		elsif (index('Oov',$c) != -1) {
		    my $target = $fetch_param->();
		    my $person = $ch->names($target);
		    if (!defined $person || !$this->target_of_vanish_p($person->info,$ch_long)) {
			$add->($c,$target);
		    }
		}
		elsif ($c eq 'l') {
		    if ($plus) {
			$add->($c,$fetch_param->()); # 追加パラメタを捨てる
		    }
		    else {
			$add->($c);
		    }
		}
		else {
		    $add->($c);
		}
	    }
	}

	# パラメタ再構成の結果、一つも無くなったら、このメッセージは破棄。
	if (@params > 1) {
	    $msg = $this->construct_irc_message(
		Prefix => $msg->prefix,
		Command => $msg->command,
		Params => \@params);
	}
	else {
	    $msg = undef;
	}
    }
    $msg;
}

sub cmd_KICK {
    my ($this,$msg,$sender) = @_;

    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	if ($this->config->drop_kick_by_target) {
	    $msg->prefix('HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH');
	}
    }

    my $kicked_nick = $msg->param(1);
    my $ch = $sender->channel(Multicast::detach($msg->param(0)));
    if (defined $ch) {
	if ($this->config->drop_kick_for_target) {
	    $msg = undef;
	}
    }

    $msg;
}

sub target_of_vanish_p {
    # $userinfo: nick!name@host形式のユーザー情報
    # $ch_long : ネットワーク名付きのチャンネル名
    # 戻り値: 真偽値
    my ($this,$userinfo,$ch_long) = @_;
    Mask::match_deep_chan([$this->config->mask('all')],$userinfo,$ch_long);
}

1;

=pod
info: 指定された人物の存在を、様々なメッセージから消去する。
default: off

# 対象となった人物の発行したJOIN、PART、INVITE、QUIT、NICKは消去され、NAMESの返すネームリストからも消える。
# また、対象となった人物のNJOINも消去される。

# Vanish対象が発行したMODEを消去するかどうか。デフォルトで0。
# 消去するとは云え、本当にMODEそのものを消してしまうのではなく、
# そのユーザーの代わりに"HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH"がMODEを実行した事にする。
drop-mode-by-target: 1

# Vanish対象を対象とするMODE +o/-o/+v/-vを消去するかどうか。デフォルトで1。
drop-mode-switch-for-target: 1

# Vanish対象が発行したKICKを消去するかどうか。デフォルトで0。
# 本当に消すのではなく、"HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH"がKICKを実行した事にする。
drop-kick-by-target: 1

# Vanish対象を対象とするKICKを消去するかどうか。デフォルトで0。
drop-kick-for-target: 0

# Vanish対象が発行したTOPICを消去するかどうか。デフォルトで0。
# 本当に消すのでは無いが、他の設定と同じ。
drop-topic-by-target: 1

# チャンネルとVanish対象の定義。
# 特定のチャンネルでのみ対象とする、といった事が可能。
# また、privの場合は「#___priv___@ネットワーク名」という文字列をチャンネル名の代わりとしてマッチングを行なう。
# 書式: mask: <チャンネルのマスク> <ユーザーのマスク>
mask: #example@example  example!exapmle@example.com
=cut
