# -*- cperl -*-
# $Clovery: tiarra/module/Debug/RawLog.pm,v 1.2 2003/05/30 11:09:24 topia Exp $
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
	::printmsg($prefix . $message->serialize());
	last;
    }

    return $message;
}

1;

=pod
info: 標準出力にクライアントやサーバとの通信をダンプする。
default: off

# 0 または省略で表示しない。 1 で表示する。

# サーバからの入力
enable-server-in: 1

# サーバへの出力
enable-server-out: 1

# クライアントからの入力
enable-client-in: 0

# クライアントへの出力
enable-client-out: 0

# PING/PONG を無視する
ignore-ping: 1
=cut
