# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package System::PrivTranslator;
use strict;
use warnings;
use base qw(Module);
use Multicast;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server') &&
	defined $msg->nick) {

	my $cmd = $msg->command;
	if (($cmd eq 'PRIVMSG' || $cmd eq 'NOTICE') &&
	    Multicast::nick_p($msg->param(0))) {
	    
	    $msg->nick(
		Multicast::attach($msg->nick,$sender->network_name));
	}
    }
    $msg;
}

1;
=pod
info: ���饤����Ȥ���θĿ�Ū��priv�������Ϥ��ʤ��ʤ븽�ݤ���򤹤롣
default: off

# ���Υ⥸�塼��ϸĿͰ��Ƥ�privmsg�������Ԥ�nick�˥ͥåȥ��̾���ղä��ޤ���
# ������ܤϤ���ޤ���
=cut
