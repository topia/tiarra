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
info: IRC メッセージにちょっと変更を加えて、クライアントのバグを抑制する
default: off

# WoolChat:
#  対応しているメッセージ:
#   NICK(コロンが必須)
#  説明:
#   NICK は接続直後にも発行されるため、 Client::GetVersion での判別まで
#   待てません。該当クライアントのオプション client-type に woolchat と
#   指定してください。実名欄に $client-type=woolchat$ と書けば OK です。
enable-woolchat: 1

=cut
