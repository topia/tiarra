# -----------------------------------------------------------------------------
# $Id: Detached.pm,v 1.2 2003/01/27 11:04:06 admin Exp $
# -----------------------------------------------------------------------------
# ���Υ⥸�塼���RunLoop��current_nick�����ʤ��������nick���ѹ����ʤ���
# -----------------------------------------------------------------------------
package User::Nick::Detached;
use strict;
use warnings;
use base qw(Module);
use IRCMessage;
use RunLoop;

sub client_attached {
    my ($this,$client) = @_;
    # ���饤����Ȥ���³���줿�Ȥ������ϡ�
    # ���ʤ��Ȥ��İʾ�Υ��饤����Ȥ�¸�ߤ���˷�ޤäƤ��롣
    RunLoop->shared->broadcast_to_servers(
	IRCMessage->new(
	    Command => 'NICK',
	    Param => RunLoop->shared->current_nick));
}

sub client_detached {
    my ($this,$client) = @_;
    # ���饤����Ȥο���1(���Υ᥽�åɤ�����ä����0�ˤʤ�)�ʤ�NICK��¹ԡ�
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
    # ���饤����Ȥο���0�ʤ�NICK��¹ԡ�
    if (@{RunLoop->shared->clients} == 0 &&
	defined $this->config->detached) {
	
	$server->send_message(
	    IRCMessage->new(
		Command => 'NICK',
		Param => $this->config->detached));
    }
}

1;
