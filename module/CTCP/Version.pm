# -----------------------------------------------------------------------------
# $Id$
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

=pod
info: CTCP VERSION�˱������롣
default: on

# Ϣ³����CTCP�ꥯ�����Ȥ��Ф�������δֳ֡�ñ�̤��á�
# �㤨��3�ä����ꤷ����硢���ٱ������Ƥ���3�ô֤�
# CTCP�˰��ڱ������ʤ��ʤ롣�ǥե���Ȥ�3��
#
# �ʤ���CTCP��������ε�Ͽ�ϡ����Ƥ�CTCP�⥸�塼��Ƕ�ͭ����롣
# �㤨��CTCP VERSION�����ä�ľ���CTCP CLIENTINFO�����ä��Ȥ��Ƥ⡢
# CTCP::ClientInfo��interval�����ꤵ�줿���֤�᤮�Ƥ��ʤ����
# ��Ԥϱ������ʤ���
interval: 3
=cut
