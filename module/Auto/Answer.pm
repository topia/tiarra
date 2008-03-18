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

  # PRIVMSG �ʳ���̵��.
  if( $msg->command ne 'PRIVMSG' )
  {
    return @result;
  }

  # �����С�����ʳ�(��ʬ��ȯ��)��,
  # ���꤬�ʤ����̵��.
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

      # reply�����ꤵ�줿��Τ��椫�顢���פ��Ƥ����Τ������ȯ����
      # ���פˤ�Mask::match���Ѥ��롣
      foreach ($this->config->reply('all')) {
	my ($mask,$reply_msg) = m/^(.+?)\s+(.+)$/;
	if (Mask::match($mask,$msgval)) {
	  # ���פ��Ƥ�����
	  $reply_anywhere->($reply_msg);
	}
      }

      # channel-reply �Υ����å���
      foreach ($this->config->channel_reply('all')) {
	my ($chan_mask, $msg_mask, $reply_msg) = split(' ', $_, 3);
	$chan_mask =~ s/\[(.*)\]$//;
	my @opts = split(/,/,$1||'');

	defined($reply_msg) or next;
	if( !Mask::match($msg_mask,$msgval) )
	{
	  # ��å��������ޥå����ʤ�.
	  next;
	}
	if( !Mask::match($chan_mask,$msg_ch_full)) {
	  # �����ͥ뤬�ޥå����ʤ�.
	  next;
	}
	# �ޥå������ΤǤ��ֻ�.
	$reply_anywhere->($reply_msg);

	# [last] ���꤬����Ф����Ǥ����ޤ�.
	if( grep{$_ eq 'last'} @opts )
	{
	  last;
	}
      }

  return @result;
}

1;

=pod
info: �����ȯ����ȿ�������б�����ȯ���򤹤롣
default: off

# Auto::Alias��ͭ���ˤ��Ƥ���С������ꥢ���ִ���Ԥʤ��ޤ���

# ȿ������ȯ���ȡ�������Ф����ֻ���������ޤ���
# �����ꥢ���ִ���ͭ���Ǥ���#(nick.now)��$(channel)�Ϥ��줾��
# ���θ��ߤ�nick�ȥ����ͥ�̾���ִ�����ޤ���
#
# ���ޥ��: reply
# ��: <ȿ������ȯ���Υޥ���> <������Ф����ֻ�>
# ��:
-reply: ����ˤ���* ����ˤ��ϡ�#(name|nick.now)����
# ������Ǥ�ï�����֤���ˤ��ϡפǻϤޤ�ȯ���򤹤�ȡ�
# ȯ�������ͤΥ����ꥢ���򻲾Ȥ��ơ֤���ˤ��ϡ��������󡣡פΤ褦��ȯ�����ޤ���
#
# ���ޥ��: channel-reply
# ��: <ȿ����������ͥ�Υޥ���> <ȿ������ȯ���Υޥ���> <������Ф����ֻ�>
# ��:
-channel-reply: #��������@ircnet ����ˤ���* ����ˤ��ϡ�#(name|nick.now)����
# ������Ǥ�#��������@ircnet��ï�����֤���ˤ��ϡפǻϤޤ�ȯ���򤹤�ȡ�
# ȯ�������ͤΥ����ꥢ���򻲾Ȥ��ơ֤���ˤ��ϡ��������󡣡פΤ褦��ȯ�����ޤ���
#
# ���ޥ��: answer-to-myself
# ��: <������>
# ��:
-answer-to-myself: on
# ��ʬ��ȯ���ˤ�ȿ������褦�ˤʤ�ޤ���
# �ǥե���Ȥ� off �Ǥ���

=cut
