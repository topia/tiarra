# -----------------------------------------------------------------------------
# $Id: Raw.pm,v 1.1 2003/10/15 16:23:42 admin Exp $
# -----------------------------------------------------------------------------
package System::Raw;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this, $msg, $sender) = @_;
    if ($sender->client_p and
	  $msg->command eq uc($this->config->command || 'raw')) {
	# ����¥ѥ�᥿�����ɬ�ס�
	if ($msg->n_params < 2) {
	    $sender->send_message(
		IRCMessage->new(
		    Command => 'NOTICE',
		    Params => [
			RunLoop->shared->current_nick,
			"*** command `".$msg->command."' requires 2 or more parameters",
		       ]));
	}
	else {
	    # ������λ����Τ롣����ϥޥ�����
	    my $target = $msg->param(0);
	    
	    # ��å������ƹ���
	    my $raw_msg = IRCMessage->new(
		Line => join(' ', @{$msg->params}[1 .. $msg->n_params]),
		Encoding => 'utf8',
	       );

	    # ������ޥ����˥ޥå�����ͥåȥ�����Ƥˤ�������롣
	    my $sent;
	    foreach my $network (RunLoop->shared->networks_list) {
		if (Mask::match($target, $network->network_name)) {
		    $network->send_message($raw_msg);
		    $sent = 1;
		}
	    }
	    if (!$sent) {
		$sender->send_message(
		    IRCMessage->new(
			Command => 'NOTICE',
			Params => [
			   RunLoop->shared->current_nick, 
			   "*** no networks matches to `$target'",
			  ]));
	    }
	}
	$msg = undef; # �˴�
    }
    $msg;
}

1;