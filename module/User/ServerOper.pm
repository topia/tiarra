# -----------------------------------------------------------------------------
# $Id: ServerOper.pm,v 1.1 2003/01/27 11:04:06 admin Exp $
# -----------------------------------------------------------------------------
package User::ServerOper;
use strict;
use warnings;
use base qw(Module);
use IRCMessage;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{table} = do {
	# �ͥåȥ��̾ => [���ڥ졼��̾,���ڥ졼���ѥ����]
	my %hash = map {
	    my ($network,$id,$pass) = m/^(.+?)\s+(.+?)\s+(.+)$/;
	    $network => [$id,$pass];
	} $this->config->oper('all');
	\%hash;
    };
    $this;
}

sub connected_to_server {
    my ($this,$server,$new_connection) = @_;
    my $oper = $this->{table}->{$server->network_name};
    if (defined $oper) {
	$server->send_message(
	    IRCMessage->new(
		Command => 'OPER',
		Params => [$oper->[0],$oper->[1]]));
    }
}

1;

=pod
info: ����Υͥåȥ������³��������OPER���ޥ�ɤ�ȯ�Ԥ��Ƥ��ޤ���
default: off

# ��: <�ͥåȥ��̾> <���ڥ졼��̾> <���ڥ졼���ѥ����>
#
# �ͥåȥ��"local"����³�����������ڥ졼��̾oper��
# ���ڥ졼���ѥ����oper-pass��OPER���ޥ�ɤ�ȯ�Ԥ����㡣
-oper: local oper oper-pass
=cut
