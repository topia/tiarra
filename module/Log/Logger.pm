# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Log::Logger;
use strict;
use warnings;
use Multicast;

sub new {
    my ($class,$enstringed_callback,$exception_object,@exceptions) = @_;
    # enstringed_callback:
    #   ��å��������ʸ���󲽤������˸ƤФ��ؿ���CODE����
    #   ��������ļ�ꡢ����ܤϥ����ͥ�̾������ܤϥ�ʸ����
    # exception_object:
    #   exceptions�ǻ��ꤵ�줿�᥽�åɤ�Ƥ֤Ȥ����ɤΥ��֥������ȤǸƤ֤���
    # exceptions:
    #   ����Υ�å������Υ�ʸ���󲽤򥪡��С��饤�ɤ���
    #   'S_PRIVMSG'����
    #   ������(Tiarra::IRC::Message,IrcIO)������ͤ�[�����ͥ�̾,��ʸ����]������
    my $this = {
	enstringed => $enstringed_callback,
	exception_object => $exception_object,
	exceptions => do {
	    my %hash = map { $_ => 1 } @exceptions;
	    \%hash;
	},
    };
    bless $this,$class;
}

sub log {
    my ($this,$msg,$sender) = @_;
    my $prefix = do {
	if ($sender->isa('IrcIO::Server')) {
	    'S';
	}
	elsif ($sender->isa('IrcIO::Client')) {
	    'C';
	}
    };
    my $method_name = "${prefix}_".$msg->command;
    my @results;
    # ���Υ᥽�åɤ�exceptions���������Ƥ��뤫��
    if (defined $this->{exceptions}->{$method_name}) {
	eval {
	    @results = $this->{exception_object}->$method_name($msg,$sender);
	}; if ($@) {
	    RunLoop->shared->notify_error($@);
	}
    }
    else {
	# ���Υ��饹�˥᥽�åɤϤ��뤫��
	if ($this->can($method_name)) {
	    eval {
		@results = $this->$method_name($msg,$sender);
	    }; if ($@) {
		RunLoop->shared->notify_error($@);
	    }
	}
    }
    
    foreach (@results) {
	$this->{enstringed}->($_->[0],$_->[1]);
    }
}

sub S_JOIN {
    my ($this,$msg,$sender) = @_;
    
    $msg->param(0) =~ m/^([^\x07]+)(?:\x07(.*))?/;
    my ($ch_name,$mode) = ($1,(defined $2 ? $2 : ''));
    $mode =~ tr/ov/@+/;

    [$msg->param(0),
     sprintf('+ %s%s (%s) to %s',
	     $mode,$msg->nick,$msg->prefix,$msg->param(0))];
}

sub S_PART {
    my ($this,$msg,$sender) = @_;
    if (defined $msg->param(1)) {
	[$msg->param(0),
	 sprintf('- %s from %s (%s)',
		 $msg->nick,$msg->param(0),$msg->param(1))];
    } else {
	[$msg->param(0),
	 sprintf('- %s from %s',
		 $msg->nick,$msg->param(0))];
    }
}

sub S_KICK {
    my ($this,$msg,$sender) = @_;
    # RFC2812�ˤϡ��֥����Фϥ��饤����Ȥ�ʣ���Υ����ͥ��桼����KICK��å�������
    # ���äƤϡ֤����ޤ���ס�����ϡ��Ť����饤����ȥ��եȥ������Ȥβ��̸ߴ��Τ���Ǥ����פȤ��롣
    [$msg->param(0),
     sprintf('- %s by %s from %s (%s)',
	     $msg->param(1),$msg->nick,$msg->param(0),$msg->param(2))];
}

sub S_INVITE {
    my ($this,$msg,$sender) = @_;
    [$msg->param(1),
	sprintf 'Invited by %s: %s',$msg->nick,$msg->param(1)];
}

sub S_MODE {
    my ($this,$msg,$sender) = @_;
    [$msg->param(0),
     sprintf('Mode by %s: %s %s',
	     $msg->nick,
	     $msg->param(0),
	     join(' ',@{$msg->params}[1 .. ($msg->n_params - 1)]))];
}

sub S_NICK {
    my ($this,$msg,$sender) = @_;
    my $network_name = $sender->network_name;
    my $line = do {
	sprintf(
	    do {
		if ($msg->param(0) eq $sender->current_nick) {
		    'My nick is changed (%s -> %s)';
		}
		else {
		    '%s -> %s';
		}
	    },
	    $msg->nick,
	    $msg->param(0));
    };
    my @result;
    foreach my $ch_name (@{$msg->remark('affected-channels')}) {
	push @result,[Multicast::attach($ch_name,$network_name),
		      $line];
    }
    @result;
}

*S_KILL = \&S_QUIT;
sub S_QUIT {
    my ($this,$msg,$sender) = @_;
    my $network_name = $sender->network_name;
    my @result;
    foreach my $ch_name (@{$msg->remark('affected-channels')}) {
	push @result,[Multicast::attach($ch_name,$network_name),
		      sprintf '! %s (%s)',$msg->nick,$msg->param(0)];
    }
    @result;
}

sub S_TOPIC {
    my ($this,$msg,$sender) = @_;
    [$msg->param(0),
     sprintf('Topic of channel %s by %s: %s',
	     $msg->param(0),
	     $msg->nick,
	     $msg->param(1))];
}

1;
