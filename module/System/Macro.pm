# -----------------------------------------------------------------------------
# $Id: Macro.pm,v 1.3 2004/02/23 02:46:20 topia Exp $
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

=pod
info: 新規にコマンドを追加し、そのコマンドが使われた時に特定の動作をまとめて実行します。
default: off

# 書式: <コマンド> <動作>
# コマンド"switch"を追加して、それが使われると
# #a@ircnet,#b@ircnet,#c@ircnetにjoinして、
# #d@ircnet,#e@ircnet,#f@ircnetからpartする例。
-macro: switch join #a@ircnet,#b@ircnet,#c@ircnet
-macro: switch part #d@ircnet,#e@ircnet,#f@ircnet
=cut
