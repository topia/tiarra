# -----------------------------------------------------------------------------
# $Id: Reload.pm,v 1.2 2003/07/26 14:00:37 admin Exp $
# -----------------------------------------------------------------------------
package System::Reload;
use strict;
use warnings;
use base qw(Module);
use ReloadTrigger;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    # クライアントの発言か？
    if ($sender->isa('IrcIO::Client')) {
	# コマンド名は一致してるか？
	if ($msg->command eq uc($this->config->command)) {
	    # 必要ならリロードを実行。
	    $this->_reload_if_needed;
	    return undef;
	}
    }
    return $msg;
}

sub _reload_if_needed {
    ReloadTrigger->reload_conf_if_updated;
    ReloadTrigger->reload_mods_if_updated;
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
