# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::PatchworkMessage;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use NumericReply;
use Module::Use qw(Client::Guess);
use Client::Guess;
use Tiarra::Utils;

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    my $mark_as_need_colon = sub {
	$msg->remark('always-use-colon-on-last-param', 1);
    };

    if ($io->isa('IrcIO::Client')) {
	if ($this->is_target('woolchat', $io)) {
	    if ($type eq 'out' &&
		    $msg->command eq 'NICK') {
		$mark_as_need_colon->();
	    }
	} elsif ($this->is_target('xchat', $io)) {
	    if ($type eq 'out' &&
		    $msg->command eq RPL_WHOISUSER) {
		$mark_as_need_colon->();
	    }
	}
    }
    return $msg;
}

sub is_target {
    my ($this, $target, $io, $default_disable) = @_;

    if (Client::Guess->shared->is_target($target, $io) &&
	    utils->cond_yesno($this->config->get("enable-$target"),
			      !$default_disable)) {
	return 1;
    }
    return 0;
}

1;
=pod
info: IRC ��å������ˤ���ä��ѹ���ä��ơ����饤����ȤΥХ�����������
default: on

# �ä���ս񤭤��ʤ����ϥǥե���Ȥ�ͭ���Ǥ���
# �ޤ��� Client::GetVersion ��Ʊ��������Ƥ����������Ǥ���

# WoolChat:
#  �б����Ƥ����å�����:
#   NICK(�����ɬ��)
#  ����:
#   NICK ����³ľ��ˤ�ȯ�Ԥ���뤿�ᡢ Client::GetVersion �Ǥ�Ƚ�̤ޤ�
#   �ԤƤޤ��󡣳������饤����ȤΥ��ץ���� client-type �� woolchat ��
#   ���ꤷ�Ƥ�����������̾��� $client-type=woolchat$ �Ƚ񤱤� OK �Ǥ���
enable-woolchat: 1

# X-Chat:
#  �б����Ƥ����å�����:
#   RPL_WHOISUSER(�����ɬ��)
#  ����:
#   WHOIS �� realname �˥��ڡ��������äƤ��ʤ��Ⱥǽ�ΰ�ʸ��������ޤ���
enable-xchat: 1

=cut
