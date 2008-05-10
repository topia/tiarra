# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Answer;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;
use Multicast;

sub as_boolean
{
  my $val = shift;
  if( $val && $val =~ /^(off|no|false)/i )
  {
    $val = 0;
  }
  $val;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # PRIVMSG 以外は無視.
  if( $msg->command ne 'PRIVMSG' )
  {
    return @result;
  }

  # サーバーから以外(自分の発言)は,
  # 設定がなければ無視.
  if( !$sender->isa('IrcIO::Server') )
  {
    if( !as_boolean( $this->config->answer_to_myself() ) )
    {
      return @result;
    }
  }

      my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);
      my $msgval = $msg->param(1);
      my $msg_ch_full = Auto::Utils::get_full_ch_name($msg, 0);

      # replyに設定されたものの中から、一致しているものがあれば発言。
      # 一致にはMask::matchを用いる。
      foreach ($this->config->reply('all')) {
	my ($mask,$reply_msg) = m/^(.+?)\s+(.+)$/;
	if (Mask::match($mask,$msgval)) {
	  # 一致していた。
	  $reply_anywhere->($reply_msg);
	}
      }

      # channel-reply のチェック。
      foreach ($this->config->channel_reply('all')) {
	my ($chan_mask, $msg_mask, $reply_msg) = split(' ', $_, 3);
	$chan_mask =~ s/\[(.*)\]$//;
	my @opts = split(/,/,$1||'');

	defined($reply_msg) or next;
	if( !Mask::match($msg_mask,$msgval) )
	{
	  # メッセージがマッチしない.
	  next;
	}
	if( !Mask::match($chan_mask,$msg_ch_full)) {
	  # チャンネルがマッチしない.
	  next;
	}
	# マッチしたのでお返事.
	$reply_anywhere->($reply_msg);

	# [last] 指定があればここでおしまい.
	if( grep{$_ eq 'last'} @opts )
	{
	  last;
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
# コマンド: reply
# 書式: <反応する発言のマスク> <それに対する返事>
# 例:
-reply: こんにちは* こんにちは、#(name|nick.now)さん。
# この例では誰かが「こんにちは」で始まる発言をすると、
# 発言した人のエイリアスを参照して「こんにちは、○○さん。」のように発言します。
#
# コマンド: channel-reply
# 書式: <反応するチャンネルのマスク> <反応する発言のマスク> <それに対する返事>
# 例:
-channel-reply: #あいさつ@ircnet こんにちは* こんにちは、#(name|nick.now)さん。
# この例では#あいさつ@ircnetで誰かが「こんにちは」で始まる発言をすると、
# 発言した人のエイリアスを参照して「こんにちは、○○さん。」のように発言します。
#
# コマンド: answer-to-myself
# 書式: <真偽値>
# 例:
-answer-to-myself: on
# 自分の発言にも反応するようになります。
# デフォルトは off です。

=cut
