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
use Module::Use qw(Client::Guess);
use Client::Guess;

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client')) {
	if ($this->is_target('woolchat', $io)) {
	    if ($type eq 'out' &&
		    $msg->command eq 'NICK') {
		$msg->remark('always-use-colon-on-last-param', 1);
	    }
	}
    }
    return $msg;
}

sub is_target {
    my ($this, $target, $io) = @_;

    if ($this->config->get("enable-$target") &&
	    Client::Guess->shared->is_target($target, $io)) {
	return 1;
    }
    return 0;
}

1;
=pod
info: IRC ��å������ˤ���ä��ѹ���ä��ơ����饤����ȤΥХ�����������
default: off

# WoolChat:
#  �б����Ƥ����å�����:
#   NICK(�����ɬ��)
#  ����:
#   NICK ����³ľ��ˤ�ȯ�Ԥ���뤿�ᡢ Client::GetVersion �Ǥ�Ƚ�̤ޤ�
#   �ԤƤޤ��󡣳������饤����ȤΥ��ץ���� client-type �� woolchat ��
#   ���ꤷ�Ƥ�����������̾��� $client-type=woolchat$ �Ƚ񤱤� OK �Ǥ���
enable-woolchat: 1

=cut
