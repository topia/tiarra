# -----------------------------------------------------------------------------
# $Id: Reload.pm,v 1.3 2003/11/09 09:04:18 topia Exp $
# -----------------------------------------------------------------------------
package System::Reload;
use strict;
use warnings;
use base qw(Module);
use ReloadTrigger;
use Timer;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    # クライアントの発言か？
    if ($sender->isa('IrcIO::Client')) {
	# コマンド名は一致してるか？
	if ($msg->command eq uc($this->config->command)) {
	    # 必要ならリロードを実行。
	    Timer->new(
		After => 0,
		Code => sub {
		    ReloadTrigger->reload_conf_if_updated;
		    ReloadTrigger->reload_mods_if_updated;
		}
	       )->install;
	    return undef;
	}
    }
    return $msg;
}

1;
=pod
info: confファイルやモジュールの更新をリロードするコマンドを追加する。
default: on

# リロードを実行するコマンド名。省略されるとコマンドを追加しません。
# 例えば"load"を設定すると、"/load"と発言しようとした時にリロードを実行します。
# この時コマンドはTiarraが握り潰すので、IRCプロトコル上で定義された
# コマンド名を設定すべきではありません。
command: load
=cut
