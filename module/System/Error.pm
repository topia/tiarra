# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package System::Error;
use strict;
use warnings;
use base qw(Module);

sub message_io_hook {
    my ($this,$message,$io,$type) = @_;

    if ($io->isa('IrcIO::Client') &&
	    $type eq 'out' &&
		$message->command eq 'ERROR' &&
		    !$message->remark('send-error-as-is-to-client')) {
	$message->param(1, $message->serialize);
	$message->param(0, RunLoop->shared_loop->current_nick);
	$message->command('NOTICE');
    }

    return $message;
}

1;

=pod
info: サーバーからのERRORメッセージをNOTICEに埋め込む
default: on

# これをoffにするとクライアントにERRORメッセージがそのまま送られます。
# クライアントとの間ではERRORメッセージは主に切断警告に使われており、
# そのまま流してしまうとクライアントが混乱する可能性があります。
#   設定項目はありません。

# このモジュールを回避してERRORメッセージをクライアントに送りたい場合は、
# remarkのsend-error-as-is-to-clientを指定してください。
=cut
