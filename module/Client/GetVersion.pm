# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::GetVersion;
use strict;
use warnings;
use base qw(Module);
use CTCP;

sub CTCP_VERSION_EXPIRE_TIME (){5 * 60;}

sub client_attached {
    my ($this,$client) = @_;

    my $msg = CTCP::make('VERSION', RunLoop->shared_loop->current_nick, 'PRIVMSG');
    $msg->prefix(RunLoop->shared_loop->sysmsg_prefix(qw(system)));

    $client->send_message($msg);
    $client->remark(__PACKAGE__.'/fetching-version-expire',
		    time() + CTCP_VERSION_EXPIRE_TIME);
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client')) {
	if ($type eq 'in' && $msg->command eq 'NOTICE' &&
		!Multicast::channel_p($msg->param(0)) &&
		    defined $msg->param(1) &&
			defined $io->remark(__PACKAGE__.'/fetching-version-expire')) {
	    if ($io->remark(__PACKAGE__.'/fetching-version-expire')
		    >= time()) {
		my $ctcp = CTCP::extract($msg);
		if (defined $ctcp) {
		    my ($command, $text) = split(/ /, $ctcp, 2);
		    if ($command eq 'VERSION') {
			$io->remark('client-version', $text);
			return undef;
		    }
		}
	    } else {
		$io->remark(__PACKAGE__.'/fetching-version-expire', undef, 'delete');
	    }
	}
    }

    return $msg;
}

1;
=pod
info: クライアントに CTCP Version を発行してバージョン情報を得る
default: off

# オプションはいまのところありません。
# (開発者向け情報: 取得した情報は remark の client-version に設定され、
#                  Client::Guess から使用されます。)

=cut
