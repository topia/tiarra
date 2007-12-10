# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

package Debug::RawLog;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Tools::DateConvert);
use Tools::DateConvert;
use Mask;
use Multicast;

sub message_io_hook {
    my ($this,$message,$io,$type) = @_;

    my $prefix = 'RAWLOG: ';
    my $conf_entry = 'enable-';

    $prefix .= do {
	if ($type eq 'in') {
	    '<<';
	} elsif ($type eq 'out') {
	    '>>';
	} else {
	    '--';
	}
    };

    $prefix .= do {
	if ($io->server_p()) {
	    'SERVER(' . $io->network_name() . ') ';
	} elsif ($io->client_p()) {
	    'CLIENT(' . ($io->option('logname') || $io->fullname()) . ') ';
	} else {
	    '------ ';
	}
    };

    $conf_entry .= do {
	if ($io->server_p()) {
	    'server'
	} elsif ($io->client_p()) {
	    'client';
	}
    };

    $conf_entry .= '-' . $type;

    # break with last
    while (1) {
	last if (($message->command =~ /^P[IO]NG$/) &&
		     $this->config->ignore_ping);
	last unless ($this->config->get($conf_entry));
	my $msg = $message->clone;
	if ($this->config->resolve_numeric && $message->command =~ /^\d{3}$/) {
	    $msg->command(
		(NumericReply::fetch_name($message->command)||'undef').
		    '('.$message->command.')');
	}
	::printmsg($prefix . $msg->serialize());
	last;
    }

    return $message;
}

1;

=pod
info: ɸ����Ϥ˥��饤����Ȥ䥵���ФȤ��̿������פ��롣
default: off

# 0 �ޤ��Ͼ�ά��ɽ�����ʤ��� 1 ��ɽ�����롣
# ���饤����ȥ��ץ����� logname �ˤ�äơ�����פ˻Ȥ�̾�������Ǥ��ޤ���

# �����Ф��������
enable-server-in: 1

# �����Фؤν���
enable-server-out: 1

# ���饤����Ȥ��������
enable-client-in: 0

# ���饤����Ȥؤν���
enable-client-out: 0

# PING/PONG ��̵�뤹��
ignore-ping: 1

# NumericReply ��̾�����褷��ɽ������(�����Ȥ��� dump �Ǥ�̵���ʤ�ޤ�)
resolve-numeric: 1
=cut
