# -----------------------------------------------------------------------------
# $Id: Ignore.pm,v 1.3 2003/08/04 09:29:20 admin Exp $
# -----------------------------------------------------------------------------
package User::Ignore;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    
    # �����饯�饤����Ȥظ�������å���������
    if ($sender->isa('IrcIO::Server')) {
	# �оݤȤʤ륳�ޥ�ɤ���
	if (Mask::match(
		$this->config->command,
		$msg->command)) {
	    # ���Ƥ�mask�򥫥�ޤǷҤ��ƥޥå��󥰤�Ԥʤ���
	    if (Mask::match(
		    join(',',$this->config->mask('all')),
		    $msg->prefix || '')) {
		# �ǽ�Ū�˥ޥå������Τǡ����Υ�å������ϼΤƤ롣
		return undef;
	    }
	}
    }
    return $msg;
}

1;
=pod
info: ���ꤵ�줿�ʹ֤����PRIVMSG��NOTICE���˴����ƥ��饤����Ȥ�����ʤ��褦�ˤ���⥸�塼�롣
default: off

# �оݤȤʤ륳�ޥ�ɤΥޥ�������ά���ˤ�"privmsg,notice"�����ꤵ��Ƥ��롣
# ������privmsg��notice�ʳ����˴����Ƥ��ޤ��ȡ�(Tiarra��ʿ���Ǥ�)���饤����Ȥ����𤹤롣
command: privmsg,notice

# mask��ʣ�������ǽ��������줿���֤ǥޥå��󥰤��Ԥʤ��ޤ���
mask: example!*@*.example.net
=cut
