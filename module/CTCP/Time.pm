# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package CTCP::Time;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Tools::DateConvert);
use Tools::DateConvert;
use CTCP;
use Multicast;
use Config;
use BulletinBoard;

# ctcp-clientinfo-timeを設定
BulletinBoard->shared->ctcp_clientinfo_time('TIME');

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	defined $msg->nick) {

	my $ctcp = CTCP::extract($msg);
	if (defined $ctcp && $ctcp eq 'TIME') {

	    my $last = $sender->remark('last-ctcp-replied');
	    if (!defined $last || time - $last > ($this->config->interval || 3)) {
		# 前回のCTCP反応から一定時間以上経過している。
		my $reply = CTCP::make(
		    'TIME :'.Tools::DateConvert::replace('%a, %Y/%m/%d %H:%M:%S %z'),
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
info: CTCP TIMEに応答する。
default: off
section: important

# CTCP::Versionのintervalと同じ。
interval: 3
=cut
