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

  # サーバーからのメッセージか？
  if ($sender->isa('IrcIO::Server')) {
    # PRIVMSGか？
    if ($msg->command eq 'PRIVMSG') {
      my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

      # replyに設定されたものの中から、一致しているものがあれば発言。
      # 一致にはMask::matchを用いる。
      foreach ($this->config->reply('all')) {
	my ($mask,$reply_msg) = m/^(.+?)\s+(.+)$/;
	if (Mask::match($mask,$msg->param(1))) {
	  # 一致していた。
	  $reply_anywhere->($reply_msg);
	}
      }
    }
  }

  return @result;
}

1;
