# -----------------------------------------------------------------------------
# $Id: Answer.pm,v 1.3 2003/02/13 05:26:02 topia Exp $
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/Auto/Answer.pm,v 1.3 2003/02/13 04:38:56 topia Exp $
package Auto::Answer;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;
use Multicast;

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # �����С�����Υ�å���������
  if ($sender->isa('IrcIO::Server')) {
    # PRIVMSG����
    if ($msg->command eq 'PRIVMSG') {
      my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

      # reply�����ꤵ�줿��Τ��椫�顢���פ��Ƥ����Τ������ȯ����
      # ���פˤ�Mask::match���Ѥ��롣
      foreach ($this->config->reply('all')) {
	my ($mask,$reply_msg) = m/^(.+?)\s+(.+)$/;
	if (Mask::match($mask,$msg->param(1))) {
	  # ���פ��Ƥ�����
	  $reply_anywhere->($reply_msg);
	}
      }
    }
  }

  return @result;
}

1;
