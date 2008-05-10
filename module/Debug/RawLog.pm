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
info: 標準出力にクライアントやサーバとの通信をダンプする。
default: off

# 0 または省略で表示しない。 1 で表示する。
# クライアントオプションの logname によって、ダンプに使う名前を指定できます。

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

# NumericReply の名前を解決して表示する(ちゃんとした dump では無くなります)
resolve-numeric: 1
=cut
