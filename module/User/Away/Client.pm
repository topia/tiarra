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
    # ���饤����Ȥ���³���줿�Ȥ������ϡ�
    # ���ʤ��Ȥ��İʾ�Υ��饤����Ȥ�¸�ߤ���˷�ޤäƤ��롣
    RunLoop->shared->broadcast_to_servers(
	IRCMessage->new(
	    Command => 'AWAY'));
}

sub client_detached {
    my ($this,$client) = @_;
    # ���饤����Ȥο���1(���Υ᥽�åɤ�����ä����0�ˤʤ�)�ʤ�AWAY��¹ԡ�
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
    # ���饤����Ȥο���0�ʤ�AWAY��¹ԡ�
    if (@{RunLoop->shared->clients} == 0 &&
	defined $this->config->away) {
	
	$server->send_message(
	    IRCMessage->new(
		Command => 'AWAY',
		Param => $this->config->away));
    }
}

1;
