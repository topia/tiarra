# -----------------------------------------------------------------------------
# $Id: Shutdown.pm,v 1.3 2003/01/24 16:07:15 admin Exp $
# -----------------------------------------------------------------------------
package System::Shutdown;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Client')) {
	# ���饤����Ȥ���Υ��ޥ��
	if ($msg->command eq uc($this->config->command)) {
	    # �ɤ������饤����Ȥؤ������ʤ�����å�����ɽ��
	    RunLoop->shared->notify_msg(
		"System::Shutdown received shutdown command from client.");
	    &::shutdown;
	}
    }
    elsif ($sender->isa('IrcIO::Server')) {
	# priv����
	if (defined $msg->nick &&
	    $msg->param(0) eq RunLoop->shared->current_nick &&
	    ($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE')) {
	    # ȯ�����Ƥ�message�˴������פ��Ƥ��뤫��
	    if (defined $this->config->message &&
		$msg->param(1) eq $this->config->message) {
		# ȯ���Ԥ�mask�˥ޥå����뤫��
		if (Mask::match(
			join(',',$this->config->mask('all')),
			$msg->prefix)) {
		    # �ɤ������饤����Ȥˤ������ʤ�����å�����ɽ��
		    RunLoop->shared->notify_msg(
			"System::Shutdown received shutdown command from ".$msg->prefix.".");
		    &::shutdown;
		}
	    }
	}
    }
    $msg;
}

1;

=pod
info: Tiarra��λ�����롣
default: off

# ���饤����Ȥ�������Υ��ޥ�ɤ��¹Ԥ��줿���䡢
# ï������Ŀ�Ū��(priv��)�����ȯ��������줿����
# Tiarra ��λ�����ޤ���

# �ɲä��륳�ޥ�ɡ���ά���줿���ϥ��ޥ�ɤǤΥ���åȥ������̵���ˤʤ�ޤ���
-command: shutdown

# Tiarra�򥷥�åȥ����󤵤���priv��ȯ����
# ��ά���줿����priv�ǤΥ���åȥ������̵���ˤʤ�ޤ���
-message: shutdown

# priv�ǤΥ���åȥ��������Ĥ���͡�
# ��ά���줿����priv�ǤΥ���åȥ������̵���ˤʤ�ޤ���
# ʣ���Υޥ�������ꤷ�����ϡ���ĤǤ�ޥå������Τ�����Х���åȥ����󤷤ޤ���
-mask: example!example@*.example.jp
=cut
