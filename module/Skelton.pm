# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# �⥸�塼��Υ�����ȥ�
# -----------------------------------------------------------------------------
package Skelton;
use strict;
use warnings;
use base qw(Module);

sub new {
    my $class = shift;
    # �⥸�塼�뤬ɬ�פˤʤä����˸ƤФ�롣
    # ����ϥ⥸�塼��Υ��󥹥ȥ饯���Ǥ��롣
    # ������̵����
    my $this = $class->SUPER::new(@_);

    return $this;
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
    # ����ͤ�IRCMessage�ޤ��Ϥ�������ޤ���undef��
    #
    # $message :
    #    ����: IRCMessage���֥�������
    #    �����С����顢�ޤ��ϥ��饤����Ȥ��������Ƥ�����å�������
    #    �⥸�塼��Ϥ��Υ��֥������Ȥ򤽤Τޤ��֤��Ƥ��ɤ�����
    #    ���Ѥ����֤��Ƥ��ɤ��������֤��ʤ��Ƥ��ɤ�����İʾ��֤��Ƥ��ɤ���
    # $sender :
    #    ����: IrcIO���֥�������
    #    ���Υ�å�������ȯ����IrcIO�������С��ޤ��ϥ��饤����ȤǤ��롣
    #    ��å������������С������褿�Τ����饤����Ȥ����褿�Τ���
    #    $sender->isa('IrcIO::Server')�ʤɤȤ����Ƚ�����롣
    #
    # �����С������饤����Ȥ�ή��Ǥ⡢Prefix������ʤ���å�������
    # ή���Ƥ⹽��ʤ����դ˸����С����Τ褦�ʥ�å���������Ƥ�
    # ���꤬������ʤ��褦�˥⥸�塼����߷פ��ʤ���Фʤ�ʤ���
    return $message;
}
## Auto::Utils::generate_reply_closures ��Ȥ���硣
# sub message_arrived {
#     my ($this,$message,$sender) = @_;
#     my @result = ($msg);
# 
#     if ($msg->command eq 'PRIVMSG') {
# 	my ($reply,$reply_as_priv,$get_raw_ch_name,$reply_anywhere,$get_full_ch_name)
# 	    = Auto::Utils::generate_reply_closures($msg,$sender,\@result);
# 
# 	$reply_anywhere->('Hello, #(name|default_name)',
# 			'default_name' => '(your name)');
# 	if ($get_raw_ch_name->() eq '#Tiarra_testing') {
# 	    # �ʤ�餫�ν���
# 	}
# 	if ($get_full_ch_name->() eq '#Tiarra_testing@LocalServer') {
# 	    # �ʤ�餫�ν���
# 	}
#     }
#     return @result;
# }
# 

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
    #    ����: IRCMessage���֥�������
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

1;
