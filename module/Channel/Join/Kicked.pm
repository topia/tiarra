# -----------------------------------------------------------------------------
# $Id: Kicked.pm,v 1.1 2003/04/29 08:32:48 admin Exp $
# -----------------------------------------------------------------------------
package Channel::Join::Kicked;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->server_p && $msg->command eq 'KICK' &&
        $msg->param(1) eq $sender->current_nick &&
	Mask::match_deep([$this->config->channel('all')],$msg->param(0))) {
	# 自分が蹴られた。
	# +kされているチャンネルならキーワードを付ける。
	my $ch = RunLoop->shared->channel($msg->param(0));
	if (defined $ch) {
	    my @params = ($ch->name);
	    if ($ch->parameters('k')) {
		push @params,$ch->parameters('k');
	    }

	    $sender->send_message(
		IRCMessage->new(
		    Command => 'JOIN',
		    Params => \@params));
	}
    }

    $msg;
}

1;
