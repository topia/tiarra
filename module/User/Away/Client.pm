# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package User::Away::Client;
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
	    Command => 'AWAY'));
}

sub client_detached {
    my ($this,$client) = @_;
    # クライアントの数が1(このメソッドから戻った後に0になる)ならAWAYを実行。
    if (@{RunLoop->shared->clients} == 1 &&
	defined $this->config->away) {
	
	RunLoop->shared->broadcast_to_servers(
	    $this->construct_irc_message(
		Command => 'AWAY',
		Param => $this->config->away));
    }
}

sub connected_to_server {
    my ($this,$server,$new_connection) = @_;
    # クライアントの数が0ならAWAYを実行。
    if (@{RunLoop->shared->clients} == 0 &&
	defined $this->config->away) {
	
	$server->send_message(
	    $this->construct_irc_message(
		Command => 'AWAY',
		Param => $this->config->away));
    }
}

1;

=pod
info: クライアントが一つも接続されていない時にAWAYを設定します。
default: off
section: important

# どのようなAWAYメッセージを設定するか。省略された場合はAWAYを設定しません。
-away: 居ない。
=cut
