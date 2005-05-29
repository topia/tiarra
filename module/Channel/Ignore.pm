# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Channel::Ignore;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use NumericReply;

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Server')) {
	if ($type eq 'in') {
	    my $numeric = NumericReply::fetch_name($msg->command);
	    my $method = 'cmd_'.($numeric || $msg->command);
	    if ($this->can($method)) {
		return $this->$method($msg, $io);
	    }
	}
    }

    $msg;
}

*cmd_NOTICE = \&cmd_PRIVMSG;
*cmd_PART = \&cmd_PRIVMSG;
*cmd_INVITE = \&cmd_PRIVMSG;
*cmd_TOPIC = \&cmd_PRIVMSG;
*cmd_MODE = \&cmd_PRIVMSG;
*cmd_KICK = \&cmd_PRIVMSG;
sub cmd_PRIVMSG {
    my ($this,$msg,$io) = @_;

    my $ch_short = $msg->param(0);
    my $ch_long = Multicast::attach($ch_short, $io->network_name);
    if (!Multicast::channel_p($ch_short)) {
	$ch_long = 'priv@'.$io->network_name;
    }

    if ($this->ignore_channel_p($ch_long)) {
	undef;
    }
    else {
	$msg;
    }
}

sub cmd_JOIN {
    my ($this,$msg,$io) = @_;
    my @channels; # チャンネルリストを再構成する。
    foreach my $channel (split m/,/,$msg->param(0)) {
	my ($ch_short,$mode) = ($channel =~ m/^([^\x07]+)(?:\x07(.*))?/);
	my $ch_long = Multicast::attach($ch_short, $io->network_name);
	if (!$this->ignore_channel_p($ch_long)) {
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
    my ($this,$msg,$io) = @_;
    my $ch_short = $msg->param(0);
    my $ch_long = Multicast::attach($ch_short, $io->network_name);
    if ($this->ignore_channel_p($ch_long)) {
	$msg = undef;
    }

    $msg;
}

*cmd_QUIT = \&cmd_NICK;
sub cmd_NICK {
    my ($this,$msg,$io) = @_;

    # 影響を及ぼした全チャンネル名のリストを得る。このリストにはネットワーク名が付いていない。
    my $affected = $msg->remark('affected-channels');
    my $no_ignore;
    foreach (@$affected) {
	my $ch_long = Multicast::attach($_,$io->network_name);
	if (!$this->ignore_channel_p($ch_long)) {
	    $no_ignore = 1;
	    last;
	}
    }

    if ($no_ignore) {
	$msg;
    }
    else {
	undef;
    }
}

sub cmd_RPL_NAMREPLY {
    my ($this,$msg,$io) = @_;

    my $ch_short = $msg->param(2);
    my $ch_long = Multicast::attach($ch_short, $io->network_name);
    if ($this->ignore_channel_p($ch_long)) {
	$msg = undef;
    }

    $msg;
}

*cmd_RPL_CHANNELMODEIS = \&cmd_RPL_ENDOFNAMES;
*cmd_RPL_TOPIC_WHO_TIME = \&cmd_RPL_ENDOFNAMES;
*cmd_RPL_TOPIC = \&cmd_RPL_ENDOFNAMES;
sub cmd_RPL_ENDOFNAMES {
    my ($this,$msg,$io) = @_;

    my $ch_short = $msg->param(1);
    my $ch_long = Multicast::attach($ch_short, $io->network_name);
    if ($this->ignore_channel_p($ch_long)) {
	$msg = undef;
    }

    $msg;
}

sub ignore_channel_p {
    my ($this,$ch_long) = @_;
    Mask::match_deep([$this->config->mask('all')],$ch_long);
}

1;

=pod
info: 指定されたチャンネルの存在を、様々なメッセージから消去する。
default: off

# 対象となったチャンネルのJOIN、PART、INVITE、QUIT、NICK、NAMES、NJOINは消去される。


# チャンネルの定義。
# また、privの場合は「priv@ネットワーク名」という文字列をチャンネル名の代わりとしてマッチングを行なう。
# 書式: mask: <チャンネルのマスク>
mask: #example@example
=cut


1;
