# -----------------------------------------------------------------------------
# $Id: Reload.pm,v 1.3 2003/11/09 09:04:18 topia Exp $
# -----------------------------------------------------------------------------
package System::Reload;
use strict;
use warnings;
use base qw(Module);
use ReloadTrigger;
use Timer;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    # ���饤����Ȥ�ȯ������
    if ($sender->isa('IrcIO::Client')) {
	# ���ޥ��̾�ϰ��פ��Ƥ뤫��
	if ($msg->command eq uc($this->config->command)) {
	    # ɬ�פʤ����ɤ�¹ԡ�
	    Timer->new(
		After => 0,
		Code => sub {
		    ReloadTrigger->reload_conf_if_updated;
		    ReloadTrigger->reload_mods_if_updated;
		}
	       )->install;
	    return undef;
	}
    }
    return $msg;
}

1;
=pod
info: conf�ե������⥸�塼��ι��������ɤ��륳�ޥ�ɤ��ɲä��롣
default: on

# ����ɤ�¹Ԥ��륳�ޥ��̾����ά�����ȥ��ޥ�ɤ��ɲä��ޤ���
# �㤨��"load"�����ꤹ��ȡ�"/load"��ȯ�����褦�Ȥ������˥���ɤ�¹Ԥ��ޤ���
# ���λ����ޥ�ɤ�Tiarra�������٤��Τǡ�IRC�ץ�ȥ�����������줿
# ���ޥ��̾�����ꤹ�٤��ǤϤ���ޤ���
command: load
=cut
