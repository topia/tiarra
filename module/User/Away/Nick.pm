# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package User::Away::Nick;
use strict;
use warnings;
use base qw(Module);
use Mask;
use IRCMessage;
use Multicast;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # クライアントから受け取ったNICKにのみ反応する。
    if ($sender->isa('IrcIO::Client') &&
	$msg->command eq 'NICK') {

	my $set_away;
	foreach ($this->config->away('all')) {
	    my ($mask,$away_str) = m/^(.+?)\s+(.+)$/;
	    if (Mask::match($mask,$msg->param(0))) {
		$this->set_away($msg,$away_str);
		$set_away = 1;
		last;
	    }
	}
	if (!$set_away) {
	    $this->unset_away($msg);
	}
    }
    $msg;
}

sub set_away {
    my ($this,$msg,$away_str) = @_;
    $this->away($msg,
		IRCMessage->new(
		    Command => 'AWAY',
		    Param => $away_str));
}

sub unset_away {
    my ($this,$msg) = @_;
    $this->away($msg,
		IRCMessage->new(
		    Command => 'AWAY'));
}

sub away {
    my ($this,$msg,$away_msg) = @_;
    # NICK hoge@ircnetのようにネットワーク名が明示されていた場合は、
    # 全てのサーバーに対してAWAYを発行する。
    # そうでなければ明示されたネットワークにのみAWAYを発行する。
    
    my (undef,$network_name,$specified) = Multicast::detach($msg->param(0));
    if ($specified) {
	# 明示された
	my $network = RunLoop->shared->network($network_name);
	if (defined $network) {
	    $network->send_message($away_msg);
	}
    }
    else {
	# 明示されなかった
	RunLoop->shared->broadcast_to_servers($away_msg);
    }
}

1;

=pod
info: ニックネーム変更に応じて AWAY を設定します。
default: off

# ニックネームを変更したときに、そのニックネームに対応するAWAYが
# 設定されていれば、そのAWAYを設定します。そうでなければAWAYを取り消します。

# 書式: <nickのマスク> <設定するAWAYメッセージ>
#
# nickをhoge_zzzに変更すると、「寝ている」というAWAYを設定する。
# hoge_workまたはhoge_zzzに変更した場合は、「仕事中」というAWAYを設定する。
# それ以外のnickに変更した場合はAWAYを取り消す。
# 後者は正規表現を利用して「away: re:hoge_(work|zzz) 仕事中」としても良い。
-away: hoge_zzz           寝ている
-away: hoge_work,hoge_zzz 仕事中
=cut
