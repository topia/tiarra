# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Tiarra�⥸�塼��(�ץ饰����)��ɽ�魯��ݥ��饹�Ǥ���
# ���Ƥ�Tiarra�⥸�塼��Ϥ��Υ��饹��Ѿ�����
# ɬ�פʥ᥽�åɤ򥪡��С��饤�ɤ��ʤ���Фʤ�ޤ���
# -----------------------------------------------------------------------------
package Module;
use strict;
use warnings;
use Carp;
use Tiarra::ShorthandConfMixin;
use Tiarra::Utils;
use base qw(Tiarra::IRC::NewMessageMixin);
# our @USES = ();
Tiarra::Utils->define_attr_getter(0, [qw(_runloop runloop)]);

sub new {
    my ($class, $runloop) = @_;
    if (!defined $runloop) {
	carp 'please update module constructor; see Skelton.pm';
	$runloop = RunLoop->shared;
    }
    # �⥸�塼�뤬ɬ�פˤʤä����˸ƤФ�롣
    # ����ϥ⥸�塼��Υ��󥹥ȥ饯���Ǥ��롣
    # ������̵����
    bless {
	runloop => $runloop,
    },$class;
}

sub destruct {
    my $this = shift;
    # �⥸�塼�뤬���פˤʤä����˸ƤФ�롣
    # ����ϥ⥸�塼��Υǥ��ȥ饯���Ǥ��롣���Υ᥽�åɤ��ƤФ줿���DESTROY�������
    # �����ʤ�᥽�åɤ�ƤФ�����̵���������ޡ�����Ͽ�������ϡ����Υ᥽�åɤ�
    # ��Ǥ����äƤ���������ʤ���Фʤ�ʤ���
    # ������̵����
}

sub message_arrived {
    my ($this,$message,$sender) = @_;
    # �����С��ޤ��ϥ��饤����Ȥ����å��������褿���˸ƤФ�롣
    # ����ͤ�Tiarra::IRC::Message�ޤ��Ϥ�������ޤ���undef��
    #
    # $message :
    #    ����: Tiarra::IRC::Message���֥�������
    #    �����С����顢�ޤ��ϥ��饤����Ȥ��������Ƥ�����å�������
    #    �⥸�塼��Ϥ��Υ��֥������Ȥ򤽤Τޤ��֤��Ƥ��ɤ�����
    #    ���Ѥ����֤��Ƥ��ɤ��������֤��ʤ��Ƥ��ɤ�����İʾ��֤��Ƥ��ɤ���
    # $sender :
    #    ����: IrcIO���֥�������
    #    ���Υ�å�������ȯ����IrcIO�������С��ޤ��ϥ��饤����ȤǤ��롣
    #    ��å������������С������褿�Τ����饤����Ȥ����褿�Τ���
    #    $sender->isa('IrcIO::Server')�ʤɤȤ����Ƚ�����롣
    #    ���ΰ����ϸ��߽������Ƥ����å��������κ��򥵡��Фǡ��ºݤ�
    #    #message ������������󥹥��󥹤� $message->generator ������
    #    (�⥸�塼�뤬����������������äƤʤ����⤢�뤷���ޤ�
    #     Multicast ����å�������ʬ�������Ǥ� generator ���Ѳ����ʤ���)
    #
    # �����С������饤����Ȥ�ή��Ǥ⡢Prefix������ʤ���å�������
    # ή���Ƥ⹽��ʤ����դ˸����С����Τ褦�ʥ�å���������Ƥ�
    # ���꤬������ʤ��褦�˥⥸�塼����߷פ��ʤ���Фʤ�ʤ���
    return $message;
}

sub client_attached {
    my ($this,$client) = @_;
    # ���饤����Ȥ���������³�������˸ƤФ�롣
    # ����ͤ�̵����
    #
    # $client :
    #    ����: IrcIO::Client���֥�������
    #    ��³���줿���饤����ȡ�
}

sub client_detached {
    my ($this,$client) = @_;
    # ���饤����Ȥ����Ǥ������˸ƤФ�롣
    # ����ͤ�̵����
    #
    # $client :
    #    ����: IrcIO::Client���֥�������
    #    ���Ǥ������饤����ȡ�
}

sub connected_to_server {
    my ($this,$server,$new_connection) = @_;
    # �����С�����³�������˸ƤФ�롣
    # ����ͤ�̵����
    #
    # $server :
    #    ����: IrcIO::Server���֥�������
    #         ��³���������С���
    # $new_connection :
    #    ����: ������
    #         ��������³�ʤ�1�����Ǹ�μ�ư��³�Ǥ�undef��
}

sub disconnected_from_server {
    my ($this,$server) = @_;
    # �����С��������Ǥ���(�����Ϥ��줿)���˸ƤФ�롣
    # ����ͤ�̵����
    #
    # $server :
    #    ����: IrcIO::Server���֥�������
    #         ���Ǥ��������С���
}

sub message_io_hook {
    my ($this,$message,$io,$type) = @_;
    # �����С����������ä���å������������С������ä���å�������
    # ���饤����Ȥ��������ä���å����������饤����Ȥ����ä���å�������
    # ���Υ᥽�åɤǳƥ⥸�塼������Τ���롣��å��������ѹ����ǽ�ǡ�
    # ����ͤΥ롼���message_arrived��Ʊ����
    #
    # �̾�Υ⥸�塼��Ϥ��Υ᥽�åɤ��������ɬ�פ�̵����
    #
    # $message :
    #    ����: Tiarra::IRC::Message���֥�������
    #         ���������줿��å�����
    # $io :
    #    ����: IrcIO::Server����IrcIO::Client���֥�������
    #         ���������Ԥʤ�줿IrcIO
    # $type :
    #    ����: ʸ����
    #         'in'�ʤ������'out'�ʤ�����
    return $message;
}

sub control_requested {
    my ($this,$request) = @_;
    # ��������ȥ���ץ���फ��Υ�å��������褿��
    # ����ͤ�ControlPort::Reply��
    #
    # $request:
    #    ���� : ControlPort::Request
    #          ����줿�ꥯ������
    die "This module doesn't support controlling.\n";
}

sub config {
    my $this = shift;
    # ���Υ⥸�塼��������������롣
    # �����С��饤�ɤ���ɬ�פ�̵����
    # ����ͤ�Configuration::Block��
    $this->_conf->find_module_conf(ref($this),'block');
}

1;
