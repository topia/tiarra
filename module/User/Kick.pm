# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package User::Kick;
use strict;
use warnings;
use base qw/Module/;
use Mask;
use Multicast;
use IRCMessage;
use Timer;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{queue} = {}; # network name => [IRCmessage,...]
    $this->{timer} = undef; # queue�����Ǥʤ�������ɬ�פˤʤ�Timer
    $this;
}

sub destruct {
    my ($this) = @_;
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }
}

sub message_arrived {
    my ($this, $msg, $sender) = @_;
    
    if ($sender->server_p && $msg->command eq 'JOIN' && defined $msg->nick) {
	foreach (split m/,/,$msg->param(0)) {
	    my ($ch_full,$mode) = (m/^(.+?)(?:\x07(.*))?$/);
	    my $ch_short = Multicast::detatch($ch_full);
	    my $ch = $sender->channel($ch_short);
	    my $myself = $ch->names($sender->current_nick);
	    if ($myself->has_o &&
		Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix,$ch_full)) {
		# kick���塼������롣
		$this->enqueue(
		    $sender->network_name, IRCMessage->new(
			Command => 'KICK',
			Params => [$ch_short,
				   $msg->nick,
				   $this->config->message || 'User::Kick']));
	    }
	}
    }

    $msg;
}

sub enqueue {
    my ($this, $network_name, $command) = @_;
    
    my $queue = $this->{queue}->{$network_name};
    if (!defined $queue) {
	$queue = $this->{queue}->{$network_name} = [];
    }
    push @$queue, $command;
    $this->prepare_timer;
}

sub prepare_timer {
    my $this = shift;
    # ���塼�ò������ޡ���¸�ߤ��ʤ���к�롣
    if (!defined $this->{timer}) {
	$this->{timer} = Timer->new(
	    Interval => 0, # ����Τؤ�
	    Repeat => 1,
	    Code => sub {
		my $timer = shift;
		$timer->interval(1);

		# �����1�ĤŤľò����롣
		my $queue_has_elem;
		while (my ($network_name, $queue) = each %{$this->{queue}}) {
		    my $server = RunLoop->shared->network($network_name);
		    my $msg = shift @$queue;
		    $server->send_message($msg) if defined $server;

		    if (@$queue > 0) {
			$queue_has_elem = 1;
		    }
		}

		# ���ƤΥ��塼�����ˤʤĤ��齪λ��
		if (!$queue_has_elem) {
		    $timer->uninstall;
		    $this->{timer} = undef;
		}
	    })->install;
    }
}

1;
