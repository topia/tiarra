# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IRCMessage��IRC�Υ�å�������ɽ�魯���饹�Ǥ����ºݤΥ�å�������UTF-8���ݻ����ޤ���
# ���Υ�å������Υѡ��������ꥢ�饤���������ƥ�å������������򥵥ݡ��Ȥ��ޤ���
# �ѡ����ȥ��ꥢ�饤���ˤ�ʸ�������ɤ���ꤷ�Ʋ������������ɤ��Ѵ����ޤ���
# Line��Encoding�ʳ��μ��ʤǥ��󥹥��󥹤���������ݤϡ�
# �ѥ�᡼���Ȥ���UTF-8���ͤ��Ϥ��Ʋ�������
# ���󥿡��ե�������Ʊ��Ǥ���
# -----------------------------------------------------------------------------
# ������ˡ����
#
# $msg = new IRCMessage(Line => ':foo!~foo@hogehoge.net PRIVMSG #hoge :hoge',
#                       Encoding => 'jis');
# print $msg->command; # 'PRIVMSG'��ɽ��
#
# $msg = new IRCMessage(Server => 'irc.hogehoge.net', # Server��Prefix�Ǥ��ɤ���
#                       Command => '366',
#                       Params => ['hoge','#hoge','End of /NAMES list.']);
# print $msg->serialize('jis'); # ":irc.hogehoge.net 366 hoge #hoge :End of /NAMES list."��ɽ��
#
# $msg = new IRCMessage(Nick => 'foo',
#                       User => '~bar',
#                       Host => 'hogehoge.net', # �ʾ壳�ĤΥѥ�᡼���������Prefix => 'foo!~bar@hogehoge.net'�Ǥ��ɤ���
#                       Command => 'NICK',
#                       Params => 'huga', # Params�����Ǥ���Ĥ����ʤ饹���顼�ͤǤ��ɤ���(���λ���Params�Ǥʤ�Param�Ǥ��ɤ���)
#                       Remarks => {'saitama' => 'SAITAMA'}, # �����󡣥��ꥢ�饤���ˤϱƶ����ʤ���
# print $msg->serialize('jis'); # ":foo!~bar@hogehoge.net NICK :huga"��ɽ��
#
# $msg = new IRCMessage(Command => 'NOTICE',
#                       Params => ['foo','hugahuga']);
# print $msg->serialize('jis'); # "NOTICE foo :hugahuga"��ɽ��
#
package IRCMessage;
use base qw(Tiarra::IRC::Message);

1;
