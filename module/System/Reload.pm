# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package System::Reload;
use strict;
use warnings;
use base qw(Module);
use ReloadTrigger;
use Timer;
use Configuration;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);

    if (!defined $this->config->conf_reloaded_notify ||
	    $this->config->conf_reloaded_notify) {
	$this->{conf_hook} = Configuration::Hook->new(
	    sub {
		my ($hook) = shift;
		RunLoop->shared_loop->notify_msg("Reloaded configuration file.");
	    })->install('reloaded');
    }
    return $this;
}

sub destruct {
    my $this = shift;

    $this->{conf_hook}->uninstall if defined $this->{conf_hook};
    $this->{conf_hook} = undef;
}

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

# conf�ե���������ɤ����Ȥ������Τ��ޤ���
# �⥸�塼������꤬�ѹ�����Ƥ������ϡ������Ǥ�����ˤ�����餺��
# �⥸�塼�뤴�Ȥ�ɽ������ޤ���1�ޤ��Ͼ�ά���줿�������Τ��ޤ���
conf-reloaded-notify: 1
=cut
