# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package CTCP::Ping;
use strict;
use warnings;
use base qw(Module);
use CTCP;
use Multicast;
use Config;
use BulletinBoard;

# ctcp-clientinfo-pingを設定
BulletinBoard->shared->ctcp_clientinfo_ping('PING');

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	defined $msg->nick) {

	my $ctcp = CTCP::extract($msg);
	if (defined $ctcp && $ctcp =~ m/^PING/) {

	    my $last = $sender->remark('last-ctcp-replied');
	    if (!defined $last || time - $last > ($this->config->interval || 3)) {
		# 前回のCTCP反応から一定時間以上経過している。
		my $reply = CTCP::make(
		    $ctcp,
		    scalar Multicast::detach($msg->nick)
		);
		$sender->send_message($reply);
		$sender->remark('last-ctcp-replied',time);
	    }
	}
    }

    $msg;
}

1;

=pod
info: CTCP PINGに応答する。
default: off

# CTCP::Versionのintervalと同じ。
interval: 3
=cut
