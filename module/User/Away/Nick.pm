# -----------------------------------------------------------------------------
# $Id: Nick.pm,v 1.1 2003/01/27 11:04:06 admin Exp $
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
