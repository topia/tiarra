# -----------------------------------------------------------------------------
# $Id: Pong.pm,v 1.5 2003/02/13 04:21:44 topia Exp $
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/System/Pong.pm,v 1.2 2003/02/09 02:23:58 topia Exp $
package System::Pong;
use strict;
use warnings;
use base qw(Module);

sub message_arrived {
    my ($this,$message,$sender) = @_;
    
    if ($message->command eq 'PING') {
	my ($prefix);
	if ($sender->isa('IrcIO::Server')) {
	    $prefix = undef;
	} else {
	    $prefix = $message->param(0);
	}
	# これを送りつけてきたサーバー/クライアントにPONGを送り返す。
	$sender->send_message(
	    new IRCMessage(
		Command => 'PONG',
		Params => $message->params));
	
	# print "System::Pong ponged to ".$message->params->[0].".\n";
	
	return $message;
    }
    elsif ($message->command eq 'PONG') {
	# PONGメッセージはこれ以上伝達させず、ここで消してしまう。
	return undef;
    }
    else {
	return $message;
    }
}

1;
