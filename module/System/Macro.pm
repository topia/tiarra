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
    $this->{macros} = $this->hash; # ���ޥ�� => ARRAY<ư��(IRCMessage)>
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
	    # ���Υ�å������ϻ�������ʤ���
	    $msg->remark('do-not-send-to-servers',1);
	}
    }
    
    $msg;
}

1;

=pod
info: �����˥��ޥ�ɤ��ɲä������Υ��ޥ�ɤ��Ȥ�줿���������ư���ޤȤ�Ƽ¹Ԥ��ޤ���
default: off

# ��: <���ޥ��> <ư��>
# ���ޥ��"switch"���ɲä��ơ����줬�Ȥ����
# #a@ircnet,#b@ircnet,#c@ircnet��join���ơ�
# #d@ircnet,#e@ircnet,#f@ircnet����part�����㡣
-macro: switch join #a@ircnet,#b@ircnet,#c@ircnet
-macro: switch part #d@ircnet,#e@ircnet,#f@ircnet
=cut
