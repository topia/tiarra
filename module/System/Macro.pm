# -----------------------------------------------------------------------------
# $Id: Macro.pm,v 1.2 2003/07/19 05:15:56 admin Exp $
# -----------------------------------------------------------------------------
package System::Macro;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use IRCMessage;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{macros} = $this->hash; # コマンド => ARRAY<動作(IRCMessage)>
    $this;
}

sub hash {
    my $this = shift;
    my $macros = {};
    foreach ($this->config->macro('all')) {
	my ($command,$action) = (m/^(.+?)\s+(.+)$/);
	$command = uc($command);
	
	my $action_msg = IRCMessage->new(
	    Line => $action,
	    Encoding => 'utf8');
	my $array = $macros->{$command};
	if (defined $array) {
	    push @$array,$action_msg;
	}
	else {
	    $macros->{$command} = [$action_msg];
	}
    }
    $macros;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    
    if ($sender->isa('IrcIO::Client')) {
	my $actions = $this->{macros}->{$msg->command};
	if (defined $actions) {
	    foreach (@$actions) {
		Multicast::from_client_to_server($_, $sender);
	    }
	    # このメッセージは鯖に送らない。
	    $msg->remark('do-not-send-to-servers',1);
	}
    }
    
    $msg;
}

1;
