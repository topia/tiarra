# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package System::Error;
use strict;
use warnings;
use base qw(Module);

sub message_io_hook {
    my ($this,$message,$io,$type) = @_;

    if ($io->isa('IrcIO::Client') &&
	    $type eq 'out' &&
		$message->command eq 'ERROR' &&
		    !$message->remark('send-error-as-is-to-client')) {
	$message->param(1, $message->serialize);
	$message->param(0, RunLoop->shared_loop->current_nick);
	$message->command('NOTICE');
    }

    return $message;
}

1;

=pod
info: �����С������ERROR��å�������NOTICE��������
default: on

# �����off�ˤ���ȥ��饤����Ȥ�ERROR��å����������Τޤ������ޤ���
# ���饤����ȤȤδ֤Ǥ�ERROR��å������ϼ�����Ƿٹ�˻Ȥ��Ƥ��ꡢ
# ���Τޤ�ή���Ƥ��ޤ��ȥ��饤����Ȥ����𤹤��ǽ��������ޤ���
#   ������ܤϤ���ޤ���

# ���Υ⥸�塼�����򤷤�ERROR��å������򥯥饤����Ȥ����ꤿ�����ϡ�
# remark��send-error-as-is-to-client����ꤷ�Ƥ���������
=cut
