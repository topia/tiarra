# -----------------------------------------------------------------------------
# $Id: Raw.pm,v 1.3 2004/02/20 18:09:11 admin Exp $
# -----------------------------------------------------------------------------
package System::Raw;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Configuration;

sub message_arrived {
    my ($this, $msg, $sender) = @_;
    if ($sender->client_p and
	  $msg->command eq uc($this->config->command || 'raw')) {
	# 最低限パラメタは二つ必要。
	if ($msg->n_params < 2) {
	    $sender->send_message(
		IRCMessage->new(
		    do {
			if (Configuration->shared->general->omit_sysmsg_prefix_when_possible) {
			    ();
			}
			else {
			    (Prefix => Configuration->shared_conf->general->sysmsg_prefix);
			}
		    },
		    Prefix => Configuration->shared->general->sysmsg_prefix,
		    Command => 'NOTICE',
		    Params => [
			RunLoop->shared->current_nick,
			"*** command `".$msg->command."' requires 2 or more parameters",
		       ]));
	}
	else {
	    # 送り先の鯖を知る。これはマスク。
	    my $target = $msg->param(0);
	    
	    # メッセージ再構築
	    my $raw_msg = IRCMessage->new(
		Line => join(' ', @{$msg->params}[1 .. $msg->n_params]),
		Encoding => 'utf8',
	       );

	    # 送信先マスクにマッチするネットワーク全てにこれを送る。
	    my $sent;
	    foreach my $network (RunLoop->shared->networks_list) {
		if (Mask::match($target, $network->network_name)) {
		    $network->send_message($raw_msg);
		    $sent = 1;
		}
	    }
	    if (!$sent) {
		$sender->send_message(
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
			   "*** no networks matches to `$target'",
			  ]));
	    }
	}
	$msg = undef; # 破棄
    }
    $msg;
}

1;
=pod
info: マスクで指定したサーバーにIRCメッセージを加工せずに直接送る。
default: off

# 例えばQUITを送る事で一時的な切断が可能。

# この機能を利用するためのコマンド名。デフォルトは「raw」。
# 「/raw ircnet quit」のようにして使う。
# 一つ目のパラメータは送り先のネットワーク名。ワイルドカード使用可能。
# CHOCOA の場合、 raw がクライアントで使われてしまうので、
# コマンド名を変えるか、 /raw raw ircnet quit のようにする必要がある。
command: raw
=cut
