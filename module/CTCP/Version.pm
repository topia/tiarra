# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# CTCP flood対策のため、VERSION、USERINFO等は一度反応する度に
# IrcIO::Serverに「last-ctcp-replied => 反応時刻」というremarkを付ける。
# 前回の反応時から一定時間が経過していなければ、CTCPに応答しない。
# -----------------------------------------------------------------------------
package CTCP::Version;
use strict;
use warnings;
use base qw(Module);
use CTCP;
use Multicast;
use Config;
use BulletinBoard;

# ctcp-clientinfo-versionを設定
BulletinBoard->shared->ctcp_clientinfo_version('VERSION');

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	defined $msg->nick) {

	my $ctcp = CTCP::extract($msg);
	if (defined $ctcp && $ctcp eq 'VERSION') {

	    my $last = $sender->remark('last-ctcp-replied');
	    if (!defined $last || time - $last > ($this->config->interval || 3)) {
		# 前回のCTCP反応から一定時間以上経過している。
		my $reply = CTCP::make(
		    'VERSION Tiarra:'.::version.':perl '.$Config{version}.' on '.$Config{archname},
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
info: CTCP VERSIONに応答する。
default: on

# 連続したCTCPリクエストに対する応答の間隔。単位は秒。
# 例えば3秒に設定した場合、一度応答してから3秒間は
# CTCPに一切応答しなくなる。デフォルトは3。
#
# なお、CTCP受信時刻の記録は、全てのCTCPモジュールで共有される。
# 例えばCTCP VERSIONを送った直後にCTCP CLIENTINFOを送ったとしても、
# CTCP::ClientInfoのintervalで設定された時間を過ぎていなければ
# 後者は応答しない。
interval: 3
=cut
