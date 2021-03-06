# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package CTCP::UserInfo;
use strict;
use warnings;
use base qw(Module);
use CTCP;
use Multicast;
use Config;
use BulletinBoard;

# ctcp-clientinfo-userinfoを設定
BulletinBoard->shared->ctcp_clientinfo_version('USERINFO');

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	defined $msg->nick) {

	my $ctcp = CTCP::extract($msg);
	if (defined $ctcp && $ctcp eq 'USERINFO') {

	    my $last = $sender->remark('last-ctcp-replied');
	    if (!defined $last || time - $last > ($this->config->interval || 3)) {
		# 前回のCTCP反応から一定時間以上経過している。
		my $reply = CTCP::make(
		    'USERINFO :'.($this->config->message || ''),
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
info: CTCP USERINFOに応答する。
default: off
section: important

# CTCP::Versionのintervalと同じ。
interval: 3

# USERINFOとして返すメッセージ。
message: テスト
=cut
