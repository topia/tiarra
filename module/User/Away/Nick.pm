# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package User::Away::Nick;
use strict;
use warnings;
use base qw(Module);
use Mask;
use IRCMessage;
use Multicast;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # ���饤����Ȥ��������ä�NICK�ˤΤ�ȿ�����롣
    if ($sender->isa('IrcIO::Client') &&
	$msg->command eq 'NICK') {

	my $set_away;
	foreach ($this->config->away('all')) {
	    my ($mask,$away_str) = m/^(.+?)\s+(.+)$/;
	    if (Mask::match($mask,$msg->param(0))) {
		$this->set_away($msg,$away_str);
		$set_away = 1;
		last;
	    }
	}
	if (!$set_away) {
	    $this->unset_away($msg);
	}
    }
    $msg;
}

sub set_away {
    my ($this,$msg,$away_str) = @_;
    $this->away($msg,
		IRCMessage->new(
		    Command => 'AWAY',
		    Param => $away_str));
}

sub unset_away {
    my ($this,$msg) = @_;
    $this->away($msg,
		IRCMessage->new(
		    Command => 'AWAY'));
}

sub away {
    my ($this,$msg,$away_msg) = @_;
    # NICK hoge@ircnet�Τ褦�˥ͥåȥ��̾����������Ƥ������ϡ�
    # ���ƤΥ����С����Ф���AWAY��ȯ�Ԥ��롣
    # �����Ǥʤ�����������줿�ͥåȥ���ˤΤ�AWAY��ȯ�Ԥ��롣
    
    my (undef,$network_name,$specified) = Multicast::detach($msg->param(0));
    if ($specified) {
	# �������줿
	my $network = RunLoop->shared->network($network_name);
	if (defined $network) {
	    $network->send_message($away_msg);
	}
    }
    else {
	# ��������ʤ��ä�
	RunLoop->shared->broadcast_to_servers($away_msg);
    }
}

1;

=pod
info: �˥å��͡����ѹ��˱����� AWAY �����ꤷ�ޤ���
default: off

# �˥å��͡�����ѹ������Ȥ��ˡ����Υ˥å��͡�����б�����AWAY��
# ���ꤵ��Ƥ���С�����AWAY�����ꤷ�ޤ��������Ǥʤ����AWAY����ä��ޤ���

# ��: <nick�Υޥ���> <���ꤹ��AWAY��å�����>
#
# nick��hoge_zzz���ѹ�����ȡ��ֿ��Ƥ���פȤ���AWAY�����ꤹ�롣
# hoge_work�ޤ���hoge_zzz���ѹ��������ϡ��ֻŻ���פȤ���AWAY�����ꤹ�롣
# ����ʳ���nick���ѹ���������AWAY����ä���
# ��Ԥ�����ɽ�������Ѥ��ơ�away: re:hoge_(work|zzz) �Ż���פȤ��Ƥ��ɤ���
-away: hoge_zzz           ���Ƥ���
-away: hoge_work,hoge_zzz �Ż���
=cut
