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
		Configuration->shared->general->sysmsg_prefix;
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
		    (defined $prefix ? (Prefix => $prefix) : ()),
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
		$target = Configuration->shared->general->sysmsg_prefix;
	    }
	    # ���������Ĥ��Ƥ��������С�/���饤����Ȥ�PONG�������֤���
	    $sender->send_message(
		new IRCMessage(
		    ((defined $prefix) ? (Prefix => $prefix) : ()),
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
