# -----------------------------------------------------------------------------
# $Id: Client.pm,v 1.1 2003/01/27 05:04:01 admin Exp $
# -----------------------------------------------------------------------------
package User::Away::Client;
use strict;
use warnings;
use base qw(Module);
use RunLoop;
use IRCMessage;

sub client_attached {
    my ($this,$client) = @_;
    # クライアントが接続されたという事は、
    # 少なくとも一つ以上のクライアントが存在するに決まっている。
    RunLoop->shared->broadcast_to_servers(
	IRCMessage->new(
	    Command => 'AWAY'));
}

sub client_detached {
    my ($this,$client) = @_;
    # クライアントの数が1(このメソッドから戻った後に0になる)ならAWAYを実行。
    if (@{RunLoop->shared->clients} == 1 &&
	defined $this->config->away) {
	
	RunLoop->shared->broadcast_to_servers(
	    IRCMessage->new(
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
	    IRCMessage->new(
		Command => 'AWAY',
		Param => $this->config->away));
    }
}

1;
