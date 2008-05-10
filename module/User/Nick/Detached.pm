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

sub client_attached {
    my ($this,$client) = @_;
    # クライアントが接続されたという事は、
    # 少なくとも一つ以上のクライアントが存在するに決まっている。
    RunLoop->shared->broadcast_to_servers(
	$this->construct_irc_message(
	    Command => 'NICK',
	    Param => RunLoop->shared->current_nick));
}

sub client_detached {
    my ($this,$client) = @_;
    # クライアントの数が1(このメソッドから戻った後に0になる)ならNICKを実行。
    if (@{RunLoop->shared->clients} == 1 &&
	defined $this->config->detached) {

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
