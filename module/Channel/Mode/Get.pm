# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Channel::Mode::Get;
use strict;
use warnings;
use base qw(Module);
use Multicast;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{buffer} = []; # [IrcIO::Server,IRCMessage]
    $this->{timer} = undef; # Timer��ɬ�פʻ������Ȥ��롣
    $this;
}

sub destruct {
    my $this = shift;
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
    }
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    
    if ($sender->isa('IrcIO::Server') &&
	    $msg->command eq 'JOIN' &&
	    defined $msg->nick &&
	    $msg->nick eq RunLoop->shared->current_nick) {
	# ��ʬ��JOIN�ʤΤǡ�MODE #channel��ȯ��
	foreach (split /,/,$msg->param(0)) {
	    my $ch_shortname = Multicast::detatch($_);
	    my $entry = [$sender,
			 IRCMessage->new(
			     Command => 'MODE',
			     Param => $ch_shortname)];
	    push @{$this->{buffer}},$entry;
	    $this->setup_timer;
	}
    }
    
    $msg;
}

sub setup_timer {
    my ($this) = @_;
    # ���˥����ޡ�������Ƥ����鲿�⤻������롣
    if (!defined $this->{timer}) {
	$this->{timer} = Timer->new(
	    Interval => 1,
	    Repeat => 1,
	    Code => sub {
		my $timer = shift;
		# ���٤���Ĥ�������Ф���
		my $msg_per_once = 2;
		my $buffer = $this->{buffer};
		for (my $i = 0;
		     $i < @$buffer && $i < $msg_per_once;
		     $i++) {
		    my $entry = $buffer->[$i];
		    $entry->[0]->send_message($entry->[1]);
		}
		splice @$buffer,0,2;
		# �Хåե������ˤʤä��齪λ��
		if (@$buffer == 0) {
		    $timer->uninstall;
		    $this->{timer} = undef;
		}
	    })->install;
    }
}

1;

=pod
info: �����ͥ��JOIN�����������Υ����ͥ�Υ⡼�ɤ�������ޤ���
default: off

# Channel::Mode::Set����������ư������ˤ�
# �����ͥ�Υ⡼�ɤ�Tiarra���İ����Ƥ���ɬ�פ�����ޤ���
# ��ưŪ�˥⡼�ɤ�������륯�饤����ȤǤ����ɬ�פ���ޤ��󤬡�
# �����Ǥʤ���Ф��Υ⥸�塼���Ȥ��٤��Ǥ���

# ������ܤ�̵����
=cut
