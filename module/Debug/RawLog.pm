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

sub notification_of_message_io {
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
	    'CLIENT ';
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

    if ($this->config->get($conf_entry) != 0) {
	::printmsg($prefix . $message->serialize());
    }
}

1;
