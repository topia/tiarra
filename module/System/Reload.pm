# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package System::Reload;
use strict;
use warnings;
use base qw(Module);
use ReloadTrigger;
use Timer;
use Configuration;
use Mask;
use RunLoop;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);

    if (!defined $this->config->conf_reloaded_notify ||
	    $this->config->conf_reloaded_notify) {
	$this->{conf_hook} = Configuration::Hook->new(
	    sub {
		my ($hook) = shift;
		RunLoop->shared_loop->notify_msg("Reloaded configuration file.");
	    })->install('reloaded');
    }
    return $this;
}

sub destruct {
    my $this = shift;

    $this->{conf_hook}->uninstall if defined $this->{conf_hook};
    $this->{conf_hook} = undef;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my $do_reload = 0;

    # クライアントの発言か？
    if ($sender->isa('IrcIO::Client')) {
	# コマンド名は一致してるか？
	if (Mask::match_deep([$this->config->broadcast_command('all')],
			     $msg->command)) {
	    RunLoop->shared_loop->broadcast_to_servers($msg->clone);
	    $do_reload = 1;
	} elsif (Mask::match_deep([$this->config->command('all')],
				  $msg->command)) {
	    $do_reload = 1;
	}
    }
    if ($do_reload) {
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

# command と同じですが、サーバにもブロードキャストします。
-broadcast-command: load-all

# confファイルをリロードしたときに通知します。
# モジュールの設定が変更されていた場合は、ここでの設定にかかわらず、
# モジュールごとに表示されます。1または省略された場合は通知します。
conf-reloaded-notify: 1
=cut
