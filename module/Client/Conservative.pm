# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::Conservative;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use NumericReply;
use Tiarra::Utils;

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client') &&
	    $type eq 'out') {
	my $mark_as_need_colon = sub {
	    $msg->remark('always-use-colon-on-last-param', 1);
	    $msg;
	};
	my $command = $msg->command;

	foreach (qw(PRIVMSG NOTICE NICK WALLOPS PART NJOIN KICK TOPIC INVITE
		    PING QUIT),
		 (map { NumericReply::fetch_number("RPL_$_") }
		      (qw(MAP MAPSTART HELLO SERVLIST AWAY USERHOST ISON),
		       qw(WHOISUSER WHOISSERVER WHOWASUSER WHOISCHANNELS),
		       qw(LIST TOPIC VERSION INFO YOUREOPER TIME))),
		) {
	    if ($command eq $_) {
		return $mark_as_need_colon->();
	    }
	}
    }
    return $msg;
}

1;
=pod
info: �����Ф���������褦�� IRC ��å��������������褦�ˤ���
default: on

# �����Ф��ºݤ��������Ƥ���褦�ʥ�å������ˤ��碌��褦�ˤ��ޤ���
# ¿���Υ��饤����Ȥ��߷ץߥ������Ǥ�(��Ȼפ��)�ޤ���

=cut
