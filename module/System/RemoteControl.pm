# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package System::RemoteControl;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	Mask::match_deep([defined($this->config->mask) ? $this->config->mask('all') : '*!*@*'],
			 $msg->prefix)) {

	my ($nick,$cmd) = $msg->param(1) =~ m/^\+\s+(.+?)\s+(.+)$/;
	# ���ꤵ�줿nick�˼�ʬ�ϥޥå����뤫��
	if (Mask::match($nick,$sender->current_nick) &&
	    defined $cmd) {
	    # �¹ԡ�
	    $sender->send_message(
		$this->construct_irc_message(
		    Line => $cmd,
		    Encoding => 'utf8'));
	}
    }
    $msg;
}

1;

=pod
info: �����ȯ���������Ƥ����Ȥ��������ȿ������IRC���ޥ�ɤ�¹Ԥ��ޤ���
default: off

# �¹Ԥ���Ĥ���ʹ֤�ɽ���ޥ�����
-mask: *!*example@example.net

# ��ʸ: + <nick> <IRC Message>
# <nick>��ȿ������bot��nick��ɽ���ޥ�����
# <Tiarra::IRC::Message>�ϥ����С��˸�����ȯ�Ԥ���IRC��å�������
#
# ��:
# + hoge NICK [hoge]
# hoge�Ȥ���BOT��[hoge]��nick���ѹ����롣
=cut
