# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::GetVersion;
use strict;
use warnings;
use base qw(Module);
use CTCP;

use constant ({
    EXPIRE_TIME => 5 * 60,
    FETCH_EXPIRE_KEY => __PACKAGE__->attach_package('fetching-version-expire'),
});

sub client_attached {
    my ($this,$client) = @_;

    $client->send_message(
	$this->construct_irc_message(
	    Prefix => $this->_runloop->sysmsg_prefix(qw(system)),
	    Command => 'PRIVMSG',
	    Params => [
		$this->_runloop->current_nick,
		CTCP->make_text('VERSION'),
	       ],
	   ));
    $client->remark(FETCH_EXPIRE_KEY, time() + EXPIRE_TIME);
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client')) {
	if ($type eq 'in' && $msg->command eq 'NOTICE' &&
		!Multicast::channel_p($msg->param(0)) &&
		    defined $msg->param(1) &&
			defined $io->remark(FETCH_EXPIRE_KEY)) {
	    if ($io->remark(FETCH_EXPIRE_KEY)
		    >= time()) {
		my $ctcp = CTCP->extract_from_text($msg->param(1));
		if (defined $ctcp) {
		    my ($command, $text) = split(/ /, $ctcp, 2);
		    if ($command eq 'VERSION') {
			$io->remark('client-version', $text);
			$io->remark(FETCH_EXPIRE_KEY, undef, 'delete');
			return undef;
		    }
		}
	    } else {
		$io->remark(FETCH_EXPIRE_KEY, undef, 'delete');
	    }
	}
    }

    return $msg;
}

1;
=pod
info: クライアントに CTCP Version を発行してバージョン情報を得る
default: on

# オプションはいまのところありません。
# (開発者向け情報: 取得した情報は remark の client-version に設定され、
#                  Client::Guess から使用されます。)

=cut
