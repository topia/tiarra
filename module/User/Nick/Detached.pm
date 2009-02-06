# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# このモジュールはRunLoopのcurrent_nick、すなわちローカルnickを変更しない。
# -----------------------------------------------------------------------------
package User::Nick::Detached;
use strict;
use warnings;
use base qw(Module);
use RunLoop;
our $BB_KEY = __PACKAGE__.'/old-nick';

sub destruct {
    my $this = shift;
    # 掲示板から最終nickを消す
    BulletinBoard->shared->set($BB_KEY, undef);
}

sub config_reload {
    my ($this, $old_config) = @_;
    # リロードのときは掲示板を保持しておきたいので定義だけしておく。
}

sub client_attached {
    my ($this,$client) = @_;

    # 掲示板に古いnickが保存されていたら変更する。
    my $old_nick = BulletinBoard->shared->get($BB_KEY);
    if (defined $old_nick) {
	BulletinBoard->shared->set($BB_KEY, undef);
	RunLoop->shared->broadcast_to_servers(
	    $this->construct_irc_message(
		Command => 'NICK',
		Param => $old_nick));
    }
}

sub client_detached {
    my ($this,$client) = @_;
    # クライアントの数が1(このメソッドから戻った後に0になる)ならNICKを実行。
    if (@{RunLoop->shared->clients} == 1 &&
	defined $this->config->detached) {

	BulletinBoard->shared->set($BB_KEY, RunLoop->shared->current_nick);
	RunLoop->shared->broadcast_to_servers(
	    $this->construct_irc_message(
		Command => 'NICK',
		Param => $this->config->detached));
    }
}

sub connected_to_server {
    my ($this,$server,$new_connection) = @_;
    # クライアントの数が0ならNICKを実行。
    if (@{RunLoop->shared->clients} == 0 &&
	defined $this->config->detached) {

	if (!defined BulletinBoard->shared->get($BB_KEY)) {
	    # 定義されていない場合(起動直後など)は現在のnickを記録しておく
	    BulletinBoard->shared->set($BB_KEY, RunLoop->shared->current_nick);
	}

	$server->send_message(
	    $this->construct_irc_message(
		Command => 'NICK',
		Param => $this->config->detached));
    }
}

1;

=pod
info: クライアントが接続されていない時に、特定のnickに変更します。
default: off
section: important

# クライアントが接続されていない時のnick。
# このnickが既に使われていたら、適当に変更が加えられて使用されます。
# クライアントが再び接続されると、切断前のローカルnickに戻ります。
detached: PHO_d
=cut
