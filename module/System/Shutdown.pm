# -----------------------------------------------------------------------------
# $Id: Shutdown.pm,v 1.3 2003/01/24 16:07:15 admin Exp $
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
	    &::shutdown;
	}
    }
    elsif ($sender->isa('IrcIO::Server')) {
	# privか？
	if (defined $msg->nick &&
	    $msg->param(0) eq RunLoop->shared->current_nick &&
	    ($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE')) {
	    # 発言内容はmessageに完全一致しているか？
	    if (defined $this->config->message &&
		$msg->param(1) eq $this->config->message) {
		# 発言者はmaskにマッチするか？
		if (Mask::match(
			join(',',$this->config->mask('all')),
			$msg->prefix)) {
		    # どうせクライアントには送られないがメッセージ表示
		    RunLoop->shared->notify_msg(
			"System::Shutdown received shutdown command from ".$msg->prefix.".");
		    &::shutdown;
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
-message: shutdown

# privでのシャットダウンを許可する人。
# 省略された場合はprivでのシャットダウンは無効になります。
# 複数のマスクを指定した場合は、一つでもマッチするものがあればシャットダウンします。
-mask: example!example@*.example.jp
=cut
