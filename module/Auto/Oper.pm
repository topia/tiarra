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
