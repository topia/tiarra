# -----------------------------------------------------------------------------
# $Id: Rejoin.pm,v 1.4 2004/02/23 02:46:19 topia Exp $
# -----------------------------------------------------------------------------
# このモジュールは動作時に掲示板のdo-not-touch-mode-of-channelsを使います。
# -----------------------------------------------------------------------------
package Channel::Rejoin;
use strict;
use warnings;
use base qw(Module);
use BulletinBoard;
use Multicast;
use RunLoop;
use NumericReply;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{sessions} = {}; # チャンネルフルネーム => セッション情報
    # セッション情報 : HASH
    # ch_fullname => チャンネルフルネーム
    # ch_shortname => チャンネルショートネーム
    # ch => ChannelInfo
    # server => IrcIO::Server
    # got_mode => 既にMODEを取得しているかどうか。
    # got_blist => 既に+bリストを(略
    # got_elist => +e(略
    # got_Ilist => +I(略
    # got_oper => 既にPART->JOINしているかどうか。
    # cmd_buf => ARRAY<IRCMessage>
    $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server')) {
	# PART,KICK,QUIT,KILLが、それぞれ一人になる要因。
	my $cmd = $msg->command;
	if ($cmd eq 'PART') {
	    foreach my $ch_fullname (split /,/,$msg->param(0)) {
		$this->check_channel(
		    scalar Multicast::detatch($ch_fullname),
		    $sender);
	    }
	}
	elsif ($cmd eq 'KICK') {
	    # RFC2812によると、複数のチャンネルを持つKICKメッセージが
	    # クライアントに届く事は無い。
	    $this->check_channel(
		scalar Multicast::detatch($msg->param(0)),
		$sender);
	}
	elsif ($cmd eq 'QUIT' || $cmd eq 'KILL') {
	    # 註釈affected-channelsに影響のあったチャンネルのリストが入っているはず。
	    foreach (@{$msg->remark('affected-channels')}) {
		$this->check_channel($_,$sender);
	    }
	}

	$this->session_work($msg,$sender);
    }
    $msg;
}

sub check_channel {
    my ($this,$ch_name,$server) = @_;
    if ($ch_name =~ m/^\+/) {
	# +チャンネルに@は付かない。
	return;
    }
    my $ch = $server->channel($ch_name);
    if (!defined $ch) {
	# 自分が入っていない
	return;
    }
    if ($ch->switches('a')) {
	# +aチャンネルでは一人になったかどうかの判定が面倒である上に、
	# @を復活させる意味も無ければ復活させない方が望ましい。
	return;
    }
    if ($ch->names(undef,undef,'size') > 1) {
	# 二人以上いる。
	return;
    }
    my $myself = $ch->names($server->current_nick);
    if (defined $myself && $myself->has_o) {
	# 自分が@を持っている。
	return;
    }
    $this->rejoin($ch_name,$server);
}

sub rejoin {
    my ($this,$ch_name,$server) = @_;
    my $ch_fullname = Multicast::attach($ch_name,$server->network_name);
    RunLoop->shared->notify_msg(
	"Channel::Rejoin is going to rejoin to ${ch_fullname}.");

    ###############
    #   処理の流れ
    ### phase 1 ###
    # セッション作成。
    # 掲示板に「このチャンネルのモードを変更するな」と書き込む。
    # TOPICを覚える。
    # 備考switches-are-knownが偽ならMODE #channel実行。
    # 必要ならMODE #channel +b,MODE #channel +e,MODE #channel +Iを実行。
    ### phase 2 ###
    # 324(modeリプライ),368(+bリスト終わり),
    # 349(+eリスト終わり),347(+Iリスト終わり)をそれぞれ必要なら待つ。
    ### phase 3 ###
    # PART #channel実行。
    # JOIN #channel実行。
    # 自分のJOINを待つ。
    # 少しずつ命令バッファに溜まったコマンドを実行していく。Timer使用。
    #   命令バッファにはMODEやTOPICが入っている。
    # 掲示板から消す。
    # セッションを破棄。
    ###############

    # チャンネル取得
    my $ch = $server->channel($ch_name);

    # セッション登録
    my $session = $this->{sessions}->{$ch_fullname} = {
	ch_fullname => $ch_fullname,
	ch_shortname => $ch_name,
	ch => $ch,
	server => $server,
	cmd_buf => [],
    };
    
    # do-not-touch-mode-of-channelsを取得
    my $untouchables = BulletinBoard->shared->do_not_touch_mode_of_channels;
    if (!defined $untouchables) {
	$untouchables = {};
	BulletinBoard->shared->set('do-not-touch-mode-of-channels',$untouchables);
    }
    # このチャンネルをフルネームで登録
    $untouchables->{$ch_fullname} = 1;
    
    # TOPICを覚える。
    if ($ch->topic ne '') {
	push @{$session->{cmd_buf}},IRCMessage->new(
	    Command => 'TOPIC',
	    Params => [$ch_name,$ch->topic]);
    }
    
    # 必要ならMODE #channel実行。
    #if ($ch->remarks('switches-are-known')) {
    #	$session->{got_mode} = 1;
    #	push @{$session->{cmd_buf}},IRCMessage->new(
    #	    Command => 'MODE',
    #}
    # やっぱりやめ。面倒。防衛BOTとして使いたかったらこんなモジュール使わないこと。
    #else {
    	$server->send_message(
    	    IRCMessage->new(
		Command => 'MODE',
		Param => $ch_name));
    #}
    
    # 必要なら+e,+b,+I実行。
    if ($this->config->save_lists) {
	foreach (qw/+e +b +I/) {
	    $server->send_message(
		IRCMessage->new(
		    Command => 'MODE',
		    Params => [$ch_name,$_]));
	}
    }
    else {
	$session->{got_elist} =
	    $session->{got_blist} =
	    $session->{got_Ilist} = 1;
    }

    # 待たなければならないものはあるか？
    if ($this->{got_mode} && $this->{got_elist} &&
	$this->{got_blist} && $this->{got_Ilist}) {
	# もう何も無い。
	$this->part_and_join($session);
    }
}

sub part_and_join {
    my ($this,$session) = @_;
    $session->{got_oper} = 1;
    foreach (qw/PART JOIN/) {
	$session->{server}->send_message(
	    IRCMessage->new(
		Command => $_,
		Param => $session->{ch_shortname}));
    }
}

sub session_work {
    my ($this,$msg,$server) = @_;
    my $session;
    # ウォッチの対象になるのはJOIN,324,368,349,347。

    my $got_reply = sub {
	my $type = shift;
	my ($flagname,$listname) = do {
	    if ($type eq 'b') {
		('got_blist','banlist');
	    }
	    elsif ($type eq 'e') {
		('got_elist','exceptionlist');
	    }
	    elsif ($type eq 'I') {
		('got_Ilist','invitelist');
	    }
	};
	
	$session = $this->{sessions}->{$msg->param(1)};
	if (defined $session) {
	    $session->{$flagname} = 1;
	    
	    my $list = $session->{ch}->$listname();
	    my $list_size = @$list;
	    # ３つずつまとめる。
	    for (my $i = 0; $i < $list_size; $i+=3) {
		my @masks = ($list->[$i]);
		push @masks,$list->[$i+1] if $i+1 < $list_size;
		push @masks,$list->[$i+2] if $i+2 < $list_size;
		
		push @{$session->{cmd_buf}},IRCMessage->new(
		    Command => 'MODE',
		    Params => [$session->{ch_shortname},
			       '+'.($type x scalar(@masks)),
			       @masks]);
	    }
	}
    };
    
    if ($msg->command eq RPL_CHANNELMODEIS) {
	# MODEリプライ
	$session = $this->{sessions}->{$msg->param(1)};
	if (defined $session) {
	    $session->{got_mode} = 1;
	    my $ch = $session->{ch};
	    
	    my ($params, @params) = $ch->mode_string;
	    if (length($params) > 1) {
		# 設定すべきモードがある。
		push @{$session->{cmd_buf}},IRCMessage->new(
		    Command => 'MODE',
		    Params => [$session->{ch_shortname},
			       $params,
			       @params]);
	    }
	}
    }
    elsif ($msg->command eq RPL_ENDOFBANLIST) {
	# +bリスト終わり
	$got_reply->('b');
    }
    elsif ($msg->command eq RPL_ENDOFEXCEPTLIST) {
	# +eリスト終わり
	$got_reply->('e');
    }
    elsif ($msg->command eq RPL_ENDOFINVITELIST) {
	# +Iリスト終わり
	$got_reply->('I');
    }
    elsif ($msg->command eq 'JOIN') {
	$session = $this->{sessions}->{$msg->param(0)};
	if (defined $session && defined $msg->nick &&
	    $msg->nick eq RunLoop->shared->current_nick) {
	    # 入り直した。
	    $session->{got_oper} = 1; # 既にセットされている筈だが念のため
	    $this->revive($session);
	}
    }

    # $sessionが空でなければ、必要な情報が全て揃った可能性がある。
    if (defined $session && !$session->{got_oper} &&
	$session->{got_mode} && $session->{got_blist} &&
	$session->{got_elist} && $session->{got_Ilist}) {
	$this->part_and_join($session);
    }
}

sub revive {
    my ($this,$session) = @_;
    Timer->new(
	Interval => 1,
	Repeat => 1,
	Code => sub {
	    my $timer = shift;
	    my $cmd_buf = $session->{cmd_buf};
	    if (@$cmd_buf > 0) {
		# 一度に二つずつ送り出す。
		my $msg_per_trigger = 2;
		for (my $i = 0; $i < @$cmd_buf && $i < $msg_per_trigger; $i++) {
		    $session->{server}->send_message($cmd_buf->[$i]);
		}
		splice @$cmd_buf,0,$msg_per_trigger;
	    }
	    if (@$cmd_buf == 0) {
		# cmd_bufが空だったら終了。
		# untouchablesから消去
		my $untouchables = BulletinBoard->shared->do_not_touch_mode_of_channels;
		delete $untouchables->{$session->{ch_fullname}};
		# session消去
		delete $this->{sessions}->{$session->{ch_fullname}};
		# タイマーをアンインストール
		$timer->uninstall;
	    }
	})->install;
}

1;

=pod
info: チャンネルオペレータ権限を無くしたとき、一人ならjoinし直す。
default: off

# +チャンネルや+aされているチャンネル以外でチャンネルオペレータ権限を持たずに
# 一人きりになった時、そのチャンネルの@を復活させるために自動的にjoinし直すモジュール。
# トピック、モード、banリスト等のあらゆるチャンネル属性をも保存します。

# +b,+I,+eリストの復旧を行なうかどうか。
# あまりに長いリストを取得するとMax Send-Q Exceedで落とされるかも知れません。
save-lists: 1
=cut
