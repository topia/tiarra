# -----------------------------------------------------------------------------
# $Id: ClientInfo.pm,v 1.2 2003/03/23 07:00:19 topia Exp $
# -----------------------------------------------------------------------------
# BulletinBoard��ctcp-clientinfo-�ǻϤޤ��ͤ�õ���������CLIENTINFO�Ȥ��Ʊ������롣
# -----------------------------------------------------------------------------
package CTCP::ClientInfo;
use strict;
use warnings;
use base qw(Module);
use CTCP;
use Multicast;
use BulletinBoard;

# CLIENTINFO����
BulletinBoard->shared->ctcp_clientinfo_clientinfo('CLIENTINFO');

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	defined $msg->nick) {

	my $ctcp = CTCP::extract($msg);
	if (defined $ctcp && $ctcp eq 'CLIENTINFO') {

	    my $last = $sender->remark('last-ctcp-replied');
	    if (!defined $last || time - $last > ($this->config->interval || 3)) {
		# �����CTCPȿ�����������ְʾ�вᤷ�Ƥ��롣

		my $clientinfo = join(
		    ' ',
		    map {
			BulletinBoard->shared->get($_);
		    } grep {
			m/^ctcp-clientinfo-/;
		    } BulletinBoard->shared->keys);

		my $reply = CTCP::make(
		    "CLIENTINFO $clientinfo",
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
info: CTCP CLIENTINFO�˱������롣
default: off

# CTCP::Version��interval��Ʊ����
interval: 3
=cut
