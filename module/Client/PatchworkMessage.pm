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
use NumericReply;
use Module::Use qw(Client::Guess);
use Client::Guess;
use Tiarra::Utils;

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    my $mark_as_need_colon = sub {
	$msg->remark('always-use-colon-on-last-param', 1);
    };

    if ($io->isa('IrcIO::Client')) {
	if ($this->is_target('woolchat', $io)) {
	    if ($type eq 'out' &&
		    $msg->command eq 'NICK') {
		$mark_as_need_colon->();
	    }
	} elsif ($this->is_target('xchat', $io)) {
	    if ($type eq 'out' &&
		    $msg->command eq RPL_WHOISUSER) {
		$mark_as_need_colon->();
	    }
	}
    }
    return $msg;
}

sub is_target {
    my ($this, $target, $io, $default_disable) = @_;

    if (Client::Guess->shared->is_target($target, $io) &&
	    utils->cond_yesno($this->config->get("enable-$target"),
			      !$default_disable)) {
	return 1;
    }
    return 0;
}

1;
=pod
info: IRC メッセージにちょっと変更を加えて、クライアントのバグを抑制する
default: off

# 特に注意書きがない場合はデフォルトで有効です。
# また、 Client::GetVersion も同時に入れておくと便利です。
# とりあえず obsolete です。このモジュールで実装されていた機能は
# Client::Conservative によって実現できます。
# Client::Conservative で実装してはいけないようなものがあった場合のみ
# このモジュールで対処します。

# WoolChat:
#  対応しているメッセージ:
#   NICK(コロンが必須)
#  説明:
#   NICK は接続直後にも発行されるため、 Client::GetVersion での判別まで
#   待てません。該当クライアントのオプション client-type に woolchat と
#   指定してください。実名欄に $client-type=woolchat$ と書けば OK です。
enable-woolchat: 1

# X-Chat:
#  対応しているメッセージ:
#   RPL_WHOISUSER(コロンが必須)
#  説明:
#   WHOIS の realname にスペースが入っていないと最初の一文字が削られます。
enable-xchat: 1

=cut
