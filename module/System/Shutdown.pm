# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package System::Shutdown;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Client')) {
	# クライアントからのコマンド
	if ($msg->command eq uc($this->config->command)) {
	    # どうせクライアントへは送られないがメッセージ表示
	    RunLoop->shared->notify_msg(
		"System::Shutdown received shutdown command from client.");
	    ::shutdown(join(' ', @{$msg->params}));;
	}
    }
    elsif ($sender->isa('IrcIO::Server')) {
	# privか？
	if (defined $msg->nick &&
	    $msg->param(0) eq RunLoop->shared->current_nick &&
	    ($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE')) {
	    my ($command, $message) = split(/\s+/, $msg->param(1));
	    # 発言内容はmessageに完全一致しているか？
	    if (Mask::match_deep([$this->config->message('all')],
				 $command)) {
		# 発言者はmaskにマッチするか？
		if (Mask::match_deep([$this->config->mask('all')],
				     $msg->prefix)) {
		    # どうせクライアントには送られないがメッセージ表示
		    RunLoop->shared->notify_msg(
			"System::Shutdown received shutdown command from ".$msg->prefix.".");
		    ::shutdown($message);
		}
	    }
	}
    }
    $msg;
}

1;

=pod
info: Tiarraを終了させる。
default: off

# クライアントから特定のコマンドが実行された時や、
# 誰かから個人的に(privで)特定の発言が送られた時に
# Tiarra を終了させます。

# 追加するコマンド。省略された場合はコマンドでのシャットダウンは無効になります。
-command: shutdown

# Tiarraをシャットダウンさせるprivの発言。
# 省略された場合はprivでのシャットダウンは無効になります。
# パラメータとして shutdown メッセージを指定できます。
-message: shutdown

# privでのシャットダウンを許可する人。
# 省略された場合はprivでのシャットダウンは無効になります。
# 複数のマスクを指定した場合は、一つでもマッチするものがあればシャットダウンします。
-mask: example!example@*.example.jp
=cut
