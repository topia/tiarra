# -----------------------------------------------------------------------------
# $Id: Detached.pm,v 1.2 2003/01/27 11:04:06 admin Exp $
# -----------------------------------------------------------------------------
# このモジュールはRunLoopのcurrent_nick、すなわちローカルnickを変更しない。
# -----------------------------------------------------------------------------
package User::Nick::Detached;
use strict;
use warnings;
use base qw(Module);
use IRCMessage;
use RunLoop;

sub client_attached {
    my ($this,$client) = @_;
    # クライアントが接続されたという事は、
    # 少なくとも一つ以上のクライアントが存在するに決まっている。
    RunLoop->shared->broadcast_to_servers(
	IRCMessage->new(
	    Command => 'NICK',
	    Param => RunLoop->shared->current_nick));
}

sub client_detached {
    my ($this,$client) = @_;
    # クライアントの数が1(このメソッドから戻った後に0になる)ならNICKを実行。
    if (@{RunLoop->shared->clients} == 1 &&
	defined $this->config->detached) {

	RunLoop->shared->broadcast_to_servers(
	    IRCMessage->new(
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
	    IRCMessage->new(
		Command => 'NICK',
		Param => $this->config->detached));
    }
}

1;
