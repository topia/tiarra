# -----------------------------------------------------------------------------
# $Id: Version.pm,v 1.2 2003/03/23 07:00:19 topia Exp $
# -----------------------------------------------------------------------------
# CTCP flood�к��Τ��ᡢVERSION��USERINFO���ϰ���ȿ�������٤�
# IrcIO::Server�ˡ�last-ctcp-replied => ȿ������פȤ���remark���դ��롣
# �����ȿ�������������֤��вᤷ�Ƥ��ʤ���С�CTCP�˱������ʤ���
# -----------------------------------------------------------------------------
package CTCP::Version;
use strict;
use warnings;
use base qw(Module);
use CTCP;
use Multicast;
use Config;
use BulletinBoard;

# ctcp-clientinfo-version������
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
		# �����CTCPȿ�����������ְʾ�вᤷ�Ƥ��롣
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
