# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Channel::Mode::Oper::Grant;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use IRCMessage;
use Timer;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{queue} = {}; # network name => [[IrcIO::Server,channel(short),nick]]
    $this->{timer} = undef; # queue�����Ǥʤ�������ɬ�פˤʤ�Timer
    $this;
}

sub destruct {
    my ($this) = @_;
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
    }
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    # ��˿ʤि��ξ��:
    # 1. �����С�����Υ�å������Ǥ���
    # 2. ���ޥ�ɤ�JOIN�Ǥ���
    # 3. ��ʬ��JOIN�ǤϤʤ�
    # 4. @�դ���JOIN�ǤϤʤ�
    # 5. ���Υ����ͥ�Ǽ�ʬ��@����äƤ���
    # 6. ����mask�˰��פ���
    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'JOIN' &&
	defined $msg->nick &&
	$msg->nick ne RunLoop->shared->current_nick) {
	foreach (split /,/,$msg->param(0)) {
	    my ($ch_full,$mode) = (m/^(.+?)(?:\x07(.*))?$/);
	    my $ch_short = Multicast::detatch($ch_full);
	    my $ch = $sender->channel($ch_short);
	    my $myself = $ch->names($sender->current_nick);
	    if (defined $myself && $myself->has_o && (!defined $mode || $mode !~ /o/)) {
		if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix,$ch_full)) {
		    # wait�ǻ��ꤵ�줿�ÿ��ηв��ˡ����塼������롣
		    # Ʊ���˥��塼�ò������ޡ���������롣
		    $this->push_to_queue($sender,$ch_short,$msg->nick);
		}
	    }
	}
    }
    $msg;
}

sub push_to_queue {
    my ($this,$server,$ch_short,$nick) = @_;
    my $wait = $this->config->wait || 0;
    if ($wait =~ /^\s*(\d+)\s*-\s*(\d+)\s*$/) {
	$wait = int(rand($2 - $1 + 1)) + $1;
    }
    Timer->new(
	After => $wait,
	Code => sub {
	    # �оݤοͤ�����+o����Ƥ�������ߡ�
	    my $ch = $server->channel($ch_short);
	    return if !defined $ch;
	    my $target = $ch->names($nick);
	    return if !defined $target;
	    return if $target->has_o;

	    my $queue = $this->{queue}->{$server->network_name};
	    if (!defined $queue) {
		$queue = $this->{queue}->{$server->network_name} = [];
	    }
	    push @$queue,[$server,$ch_short,$nick];
	    $this->prepare_timer;
	})->install;
}

sub prepare_timer {
    my ($this) = @_;
    # ���塼�ò������ޡ���¸�ߤ��ʤ���к��
    if (!defined $this->{timer}) {
	$this->{timer} = Timer->new(
	    Interval => 0, # �������ǽ��trigger���ѹ����롣
	    Repeat => 1,
	    Code => sub {
		my ($timer) = @_;
		$timer->interval(1);

		# �����3�Ĥ��ľò����롣
		# �����ͥ���˺��磳�Ĥ���Ż��롣
		my $queue_has_elem;
		foreach my $queue (values %{$this->{queue}}) {
		    my $channels = {}; # ch_shortname => [nick,nick,...]
		    for (my $i = 0; $i < @$queue && $i < 3; $i++) {
			my $elem = $queue->[$i];
			my $nicks = $channels->{$elem->[1]};
			if (!defined $nicks) {
			    $nicks = $channels->{$elem->[1]} = [];
			}
			push @$nicks,$elem->[2];
		    }
		    while (my ($ch_short,$nicks) = each %$channels) {
			$queue->[0]->[0]->send_message(
			    IRCMessage->new(
				Command => 'MODE',
				Params => [$ch_short,
					   '+'.('o' x @$nicks),
					   @$nicks]));
		    }
		    splice @$queue,0,3;
		    # ���塼�����Ǥʤ����$queue_has_elem��1������롣
		    if (@$queue > 0) {
			$queue_has_elem = 1;
		    }
		}

		# ���ƤΥ��塼�����ˤʤä��齪λ��
		if (!$queue_has_elem) {
		    $timer->uninstall;
		    $this->{timer} = undef;
		}
	    })->install;
    }
}

1;

=pod
info: ����Υ����ͥ������οʹ֤�join�������ˡ���ʬ�������ͥ륪�ڥ졼�����¤���äƤ����+o���롣
default: off

# split����������ʤɤ�+o�оݤοͤ����٤����̤����ä���Ƥ�+o�Ͼ������ļ¹Ԥ��ޤ���
# Excess Flood�ˤϤʤ�ʤ�Ȧ�Ǥ������ܳ�Ū���ɱ�BOT�˻Ȥ�������ʪ�ǤϤ���ޤ���

# �оݤοʹ֤�join���Ƥ���ºݤ�+o����ޤǲ����ԤĤ���
# ��ά���줿���Ԥ��ޤ���
# 5-10 �Τ褦�˻��ꤵ���ȡ������ͤ���ǥ�������Ԥ��ޤ���
wait: 2-5

# �����ͥ�ȿʹ֤Υޥ����������Auto::Oper��Ʊ�͡�
-mask: * example!~example@*.example.ne.jp
=cut
