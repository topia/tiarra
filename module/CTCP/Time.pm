# -----------------------------------------------------------------------------
# $Id: Time.pm,v 1.3 2004/02/23 02:46:19 topia Exp $
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

# ctcp-clientinfo-time������
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
		# �����CTCPȿ�����������ְʾ�вᤷ�Ƥ��롣
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
info: CTCP TIME�˱������롣
default: off

# CTCP::Version��interval��Ʊ����
interval: 3
=cut
