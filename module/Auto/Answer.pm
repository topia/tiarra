# -----------------------------------------------------------------------------
# $Id: Answer.pm,v 1.4 2004/02/23 02:46:19 topia Exp $
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

=pod
info: 特定の発言に反応して対応する発言をする。
default: off

# Auto::Aliasを有効にしていれば、エイリアス置換を行ないます。

# 反応する発言と、それに対する返事を定義します。
# エイリアス置換が有効です。#(nick.now)と$(channel)はそれぞれ
# 相手の現在のnickとチャンネル名に置換されます。
#
# 書式: <反応する発言のマスク> <それに対する返事>
# 例:
-reply: こんにちは* こんにちは、#(name|nick.now)さん。
# この例では誰かが「こんにちは」で始まる発言をすると、
# 発言した人のエイリアスを参照して「こんにちは、○○さん。」のように発言します。
=cut
