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
info: $BI8=`=PNO$K%/%i%$%"%s%H$d%5!<%P$H$NDL?.$r%@%s%W$9$k!#(B
default: off

# 0 $B$^$?$O>JN,$GI=<($7$J$$!#(B 1 $B$GI=<($9$k!#(B

# $B%5!<%P$+$i$NF~NO(B
enable-server-in: 1

# $B%5!<%P$X$N=PNO(B
enable-server-out: 1

# $B%/%i%$%"%s%H$+$i$NF~NO(B
enable-client-in: 0

# $B%/%i%$%"%s%H$X$N=PNO(B
enable-client-out: 0

# PING/PONG $B$rL5;k$9$k(B
ignore-ping: 1

# NumericReply $B$NL>A0$r2r7h$7$FI=<($9$k(B($B$A$c$s$H$7$?(B dump $B$G$OL5$/$J$j$^$9(B)
resolve-numeric: 1
=cut
