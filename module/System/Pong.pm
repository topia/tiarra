# -----------------------------------------------------------------------------
# $Id: Pong.pm,v 1.6 2004/02/14 11:48:20 topia Exp $
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/System/Pong.pm,v 1.2 2003/02/09 02:23:58 topia Exp $
package System::Pong;
use strict;
use warnings;
use Configuration;
use NumericReply;
use base qw(Module);

sub message_arrived {
    my ($this,$message,$sender) = @_;
    
    if ($message->command eq 'PING') {
	my ($prefix) = do {
	    if ($sender->isa('IrcIO::Server')) {
		undef;
	    } else {
		RunLoop->shared_loop->sysmsg_prefix(qw(system));
	    }
	};
	my ($nick) = do {
	    if ($sender->isa('IrcIO::Server')) {
		$sender->current_nick;
	    } else {
		RunLoop->shared_loop->current_nick;
	    }
	};
	if ($message->n_params < 1) {
	    # ���������Ĥ��Ƥ��������С�/���饤����Ȥ˥��顼���֤���
	    $sender->send_message(
		new IRCMessage(
		    Prefix => $prefix,
		    Command => ERR_NOORIGIN,
		    Params => [
			$nick,
			'No origin specified',
		       ]));
	} else {
	    my ($target);
	    if ($sender->isa('IrcIO::Server')) {
		$nick = undef;
		$target = $sender->server_hostname;
	    } else {
		$target = RunLoop->shared_loop->sysmsg_prefix(qw(system));
	    }
	    # ���������Ĥ��Ƥ��������С�/���饤����Ȥ�PONG�������֤���
	    $sender->send_message(
		new IRCMessage(
		    Prefix => $prefix,
		    Command => 'PONG',
		    Params => [
			$target,
			(defined $nick ? $nick : ()),
		       ]));
	}
	# print "System::Pong ponged to ".$message->params->[0].".\n";
	
	# PING��å������Ϥ���ʾ���ã�������������Ǿä��Ƥ��ޤ���
	return undef;
    }
    elsif ($message->command eq 'PONG') {
	# PONG��å������Ϥ���ʾ���ã�������������Ǿä��Ƥ��ޤ���
	return undef;
    }
    else {
	return $message;
    }
}

1;

=pod
info: �����С������PING��å��������Ф�����ưŪ��PONG���֤���
default: on

# �����off�ˤ���ȥ��饤����Ȥ�����PING�˱�������������ʤ��ʤ�ޤ�����
# ���饤����Ȥ����PONG��å������ϥǥե���ȤΥ����С���������Τ�
# �ǥե���Ȱʳ��Υ����С������Ping Timeout����Ȥ����ʤ�
# �����ɤ���������ޤ���
#   ������ܤϤ���ޤ���
=cut
