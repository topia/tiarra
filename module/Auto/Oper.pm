# -----------------------------------------------------------------------------
# $Id: Oper.pm,v 1.10 2003/07/31 07:34:13 topia Exp $
# -----------------------------------------------------------------------------
package Auto::Oper;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;
use Multicast;

sub new {
  my $class = shift;
  my $this = $class->SUPER::new;
  $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);
    
    my ($get_raw_ch_name,$reply,$reply_as_priv,$reply_anywhere,$get_full_ch_name)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);
    
    my $op = sub {
	$sender->send_message(IRCMessage->new(
				  Command => 'MODE',
				  Params => [$get_raw_ch_name->(),'+o',$msg->nick]));
    };
    
    # �����饯�饤����Ȥؤ�PRIVMSG�ǡ�����request�˥ޥå����Ƥ��뤫��
    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	Mask::match_array([$this->config->request('all')],$msg->param(1), 1)) {
	# ���ꤵ�줿�����ͥ�ϴ��Τ�������������С�priv�ǤϤʤ�����
	my $ch_name = $msg->param(0);
	my ($ch_name_plain) = Multicast::detatch($ch_name);
	my $ch = $sender->channel($ch_name_plain);
	if (defined $ch) {
	    # ���ꤵ�줿�����ͥ�ˡ��׵�Ԥ����äƤ��뤫��
	    if (defined $ch->names($msg->nick)) {
		# �ʤ�Ȥ��Ϥ��Ƥ��ɤ��Τʤ��Ϥ���
		if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix,$get_full_ch_name->())) {
		    # ��ʬ�Ϥʤ�Ȥ���äƤ뤫��
		    my $myself = $ch->names($sender->current_nick);
		    if ($myself->has_o) {
			# ���Ϥʤ�Ȥ���äƤ��뤫��
			my $target = $ch->names($msg->nick);
			if ($target->has_o) {
			    $reply->($this->config->oper('random'));
			} else {
			    $reply->($this->config->message('random'));
			    $op->();
			}
		    } else {
			$reply->($this->config->not_oper('random'));
		    }
		} else {
		    $reply->($this->config->deny('random'));
		}
	    } else {
		$reply_as_priv->($this->config->out('random'));
	    }
	} else {
	    $reply_as_priv->($this->config->private('random'));
	}
    }
    return @result;
}

1;

=pod
info: �����ʸ�����ȯ�������ͤ�+o���롣
default: off

# Auto::Alias��ͭ���ˤ��Ƥ���С������ꥢ���ִ���Ԥʤ��ޤ���

# +o���׵᤹��ʸ����(�ޥ���)����ꤷ�ޤ���
request: �ʤ�ȴ�ۤ�

# �����ͥ륪�ڥ졼�����¤��׵ᤷ���ͤ��׵ᤵ�줿�����ͥ뤬
# �����ǻ��ꤷ���ޥ����˰��פ��ʤ��ä�����
# deny�ǻ��ꤷ��ʸ�����ȯ������+o����ޤ���
# ��ά���줿����ï�ˤ�+o���ޤ���
# �񼰤ϡ֥����ͥ� ȯ���ԡפǤ���
# �ޥå��󥰤Υ��르�ꥺ��ϼ����̤�Ǥ���
# 1. �����ͥ�̾�˥ޥå�����mask��������ƽ����
# 2. ���ޤä������ȯ���ԥޥ�����������줿��˥���ޤǷ�礹��
# 3. ���Τ褦�ˤ����������줿�ޥ�����ȯ���ԤΥޥå��󥰤�Ԥʤ�����̤�+o��ǽ���Ȥ��롣
# ��1:
# mask: *@2ch* *!*@*
# mask: #*@ircnet* *!*@*.hoge.jp
# ������Ǥϥͥåȥ�� 2ch �����ƤΥ����ͥ��ï�ˤǤ� +o ����
# �ͥåȥ�� ircnet �� # �ǻϤޤ����ƤΥ����ͥ�ǥۥ���̾ *.hoge.jp �οͤ�+o���ޤ���
# #*@ircnet���ȡ�#hoge@ircnet:*.jp�פʤɤ˥ޥå����ʤ��ʤ�ޤ���
# ��2:
# mask: #hoge@ircnet -*!*@*,+*!*@*.hoge.jp
# mask: *            +*!*@*
# ����Ū�����ƤΥ����ͥ��ï�ˤǤ� +o ���뤬���㳰Ū��#hoge@ircnet�Ǥ�
# �ۥ���̾ *.hoge.jp �οͤˤ��� +o ���ʤ���
# ���ν����岼�դˤ���ȡ����ƤΥ����ͥ�����Ƥοͤ� +o ������ˤʤ�ޤ���
# ���Τʤ�ǽ��* +*!*@*�����Ƥοͤ˥ޥå����뤫��Ǥ���
mask: * *!*@*

# +o���׵ᤷ���ͤ�ºݤ�+o������������ǻ��ꤷ��ȯ���򤷤Ƥ���+o���ޤ���
# #(name|nick)�Τ褦�ʥ����ꥢ���ִ���Ԥ��ޤ���
# �����ꥢ���ʳ��Ǥ⡢#(nick.now)������nick�ˡ�#(channel)��
# ���Υ����ͥ�̾�ˤ��줾���ִ����ޤ���
message: λ��

# +o���׵ᤵ�줿��+o���٤����ǤϤʤ��ä�����ȯ����
# ��ά���줿�鲿������ޤ���
deny: �Ǥ��

# +o���׵ᤵ�줿�����ϴ��˥����ͥ륪�ڥ졼�����¤���äƤ�������ȯ����
# ��ά���줿��deny�����ꤵ�줿��Τ�Ȥ��ޤ���
oper: ����@����äƤ���

# +o���׵ᤵ�줿����ʬ�ϥ����ͥ륪�ڥ졼�����¤���äƤ��ʤ��ä�����ȯ����
# ��ά���줿��deny�����ꤵ�줿��Τ�Ȥ��ޤ���
not-oper: @��̵��

# �����ͥ���Ф��ƤǤʤ���ʬ���Ф���+o���׵��Ԥʤä�����ȯ����
# ��ά���줿��deny�����ꤵ�줿��Τ�Ȥ��ޤ���
private: �����ͥ���׵᤻��

# �����ͥ�γ�����+o���׵ᤵ�줿����ȯ����+n�����ͥ�Ǥϵ�����ޤ���
# ��ά���줿��deny�����ꤵ�줿��Τ�Ȥ��ޤ���
out: �����ͥ�����äƤ��ʤ�
=cut
