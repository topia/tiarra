# -----------------------------------------------------------------------------
# $Id: Rejoin.pm,v 1.4 2004/02/23 02:46:19 topia Exp $
# -----------------------------------------------------------------------------
# ���Υ⥸�塼���ư����˷Ǽ��Ĥ�do-not-touch-mode-of-channels��Ȥ��ޤ���
# -----------------------------------------------------------------------------
package Channel::Rejoin;
use strict;
use warnings;
use base qw(Module);
use BulletinBoard;
use Multicast;
use RunLoop;
use NumericReply;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{sessions} = {}; # �����ͥ�ե�͡��� => ���å�������
    # ���å������� : HASH
    # ch_fullname => �����ͥ�ե�͡���
    # ch_shortname => �����ͥ륷�硼�ȥ͡���
    # ch => ChannelInfo
    # server => IrcIO::Server
    # got_mode => ����MODE��������Ƥ��뤫�ɤ�����
    # got_blist => ����+b�ꥹ�Ȥ�(ά
    # got_elist => +e(ά
    # got_Ilist => +I(ά
    # got_oper => ����PART->JOIN���Ƥ��뤫�ɤ�����
    # cmd_buf => ARRAY<IRCMessage>
    $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server')) {
	# PART,KICK,QUIT,KILL�������줾���ͤˤʤ��װ���
	my $cmd = $msg->command;
	if ($cmd eq 'PART') {
	    foreach my $ch_fullname (split /,/,$msg->param(0)) {
		$this->check_channel(
		    scalar Multicast::detatch($ch_fullname),
		    $sender);
	    }
	}
	elsif ($cmd eq 'KICK') {
	    # RFC2812�ˤ��ȡ�ʣ���Υ����ͥ�����KICK��å�������
	    # ���饤����Ȥ��Ϥ�����̵����
	    $this->check_channel(
		scalar Multicast::detatch($msg->param(0)),
		$sender);
	}
	elsif ($cmd eq 'QUIT' || $cmd eq 'KILL') {
	    # ���affected-channels�˱ƶ��Τ��ä������ͥ�Υꥹ�Ȥ����äƤ���Ϥ���
	    foreach (@{$msg->remark('affected-channels')}) {
		$this->check_channel($_,$sender);
	    }
	}

	$this->session_work($msg,$sender);
    }
    $msg;
}

sub check_channel {
    my ($this,$ch_name,$server) = @_;
    if ($ch_name =~ m/^\+/) {
	# +�����ͥ��@���դ��ʤ���
	return;
    }
    my $ch = $server->channel($ch_name);
    if (!defined $ch) {
	# ��ʬ�����äƤ��ʤ�
	return;
    }
    if ($ch->switches('a')) {
	# +a�����ͥ�Ǥϰ�ͤˤʤä����ɤ�����Ƚ�꤬���ݤǤ����ˡ�
	# @�����褵�����̣��̵��������褵���ʤ�����˾�ޤ�����
	return;
    }
    if ($ch->names(undef,undef,'size') > 1) {
	# ��Ͱʾ夤�롣
	return;
    }
    my $myself = $ch->names($server->current_nick);
    if (defined $myself && $myself->has_o) {
	# ��ʬ��@����äƤ��롣
	return;
    }
    $this->rejoin($ch_name,$server);
}

sub rejoin {
    my ($this,$ch_name,$server) = @_;
    my $ch_fullname = Multicast::attach($ch_name,$server->network_name);
    RunLoop->shared->notify_msg(
	"Channel::Rejoin is going to rejoin to ${ch_fullname}.");

    ###############
    #   ������ή��
    ### phase 1 ###
    # ���å���������
    # �Ǽ��Ĥˡ֤��Υ����ͥ�Υ⡼�ɤ��ѹ�����ʡפȽ񤭹��ࡣ
    # TOPIC��Ф��롣
    # ����switches-are-known�����ʤ�MODE #channel�¹ԡ�
    # ɬ�פʤ�MODE #channel +b,MODE #channel +e,MODE #channel +I��¹ԡ�
    ### phase 2 ###
    # 324(mode��ץ饤),368(+b�ꥹ�Ƚ����),
    # 349(+e�ꥹ�Ƚ����),347(+I�ꥹ�Ƚ����)�򤽤줾��ɬ�פʤ��Ԥġ�
    ### phase 3 ###
    # PART #channel�¹ԡ�
    # JOIN #channel�¹ԡ�
    # ��ʬ��JOIN���Ԥġ�
    # ��������̿��Хåե���ί�ޤä����ޥ�ɤ�¹Ԥ��Ƥ�����Timer���ѡ�
    #   ̿��Хåե��ˤ�MODE��TOPIC�����äƤ��롣
    # �Ǽ��Ĥ���ä���
    # ���å������˴���
    ###############

    # �����ͥ����
    my $ch = $server->channel($ch_name);

    # ���å������Ͽ
    my $session = $this->{sessions}->{$ch_fullname} = {
	ch_fullname => $ch_fullname,
	ch_shortname => $ch_name,
	ch => $ch,
	server => $server,
	cmd_buf => [],
    };
    
    # do-not-touch-mode-of-channels�����
    my $untouchables = BulletinBoard->shared->do_not_touch_mode_of_channels;
    if (!defined $untouchables) {
	$untouchables = {};
	BulletinBoard->shared->set('do-not-touch-mode-of-channels',$untouchables);
    }
    # ���Υ����ͥ��ե�͡������Ͽ
    $untouchables->{$ch_fullname} = 1;
    
    # TOPIC��Ф��롣
    if ($ch->topic ne '') {
	push @{$session->{cmd_buf}},IRCMessage->new(
	    Command => 'TOPIC',
	    Params => [$ch_name,$ch->topic]);
    }
    
    # ɬ�פʤ�MODE #channel�¹ԡ�
    #if ($ch->remarks('switches-are-known')) {
    #	$session->{got_mode} = 1;
    #	push @{$session->{cmd_buf}},IRCMessage->new(
    #	    Command => 'MODE',
    #}
    # ��äѤ��ᡣ���ݡ��ɱ�BOT�Ȥ��ƻȤ������ä��餳��ʥ⥸�塼��Ȥ�ʤ����ȡ�
    #else {
    	$server->send_message(
    	    IRCMessage->new(
		Command => 'MODE',
		Param => $ch_name));
    #}
    
    # ɬ�פʤ�+e,+b,+I�¹ԡ�
    if ($this->config->save_lists) {
	foreach (qw/+e +b +I/) {
	    $server->send_message(
		IRCMessage->new(
		    Command => 'MODE',
		    Params => [$ch_name,$_]));
	}
    }
    else {
	$session->{got_elist} =
	    $session->{got_blist} =
	    $session->{got_Ilist} = 1;
    }

    # �Ԥ��ʤ���Фʤ�ʤ���ΤϤ��뤫��
    if ($this->{got_mode} && $this->{got_elist} &&
	$this->{got_blist} && $this->{got_Ilist}) {
	# �⤦����̵����
	$this->part_and_join($session);
    }
}

sub part_and_join {
    my ($this,$session) = @_;
    $session->{got_oper} = 1;
    foreach (qw/PART JOIN/) {
	$session->{server}->send_message(
	    IRCMessage->new(
		Command => $_,
		Param => $session->{ch_shortname}));
    }
}

sub session_work {
    my ($this,$msg,$server) = @_;
    my $session;
    # �����å����оݤˤʤ�Τ�JOIN,324,368,349,347��

    my $got_reply = sub {
	my $type = shift;
	my ($flagname,$listname) = do {
	    if ($type eq 'b') {
		('got_blist','banlist');
	    }
	    elsif ($type eq 'e') {
		('got_elist','exceptionlist');
	    }
	    elsif ($type eq 'I') {
		('got_Ilist','invitelist');
	    }
	};
	
	$session = $this->{sessions}->{$msg->param(1)};
	if (defined $session) {
	    $session->{$flagname} = 1;
	    
	    my $list = $session->{ch}->$listname();
	    my $list_size = @$list;
	    # ���Ĥ��ĤޤȤ�롣
	    for (my $i = 0; $i < $list_size; $i+=3) {
		my @masks = ($list->[$i]);
		push @masks,$list->[$i+1] if $i+1 < $list_size;
		push @masks,$list->[$i+2] if $i+2 < $list_size;
		
		push @{$session->{cmd_buf}},IRCMessage->new(
		    Command => 'MODE',
		    Params => [$session->{ch_shortname},
			       '+'.($type x scalar(@masks)),
			       @masks]);
	    }
	}
    };
    
    if ($msg->command eq RPL_CHANNELMODEIS) {
	# MODE��ץ饤
	$session = $this->{sessions}->{$msg->param(1)};
	if (defined $session) {
	    $session->{got_mode} = 1;
	    my $ch = $session->{ch};
	    
	    my ($params, @params) = $ch->mode_string;
	    if (length($params) > 1) {
		# ���ꤹ�٤��⡼�ɤ����롣
		push @{$session->{cmd_buf}},IRCMessage->new(
		    Command => 'MODE',
		    Params => [$session->{ch_shortname},
			       $params,
			       @params]);
	    }
	}
    }
    elsif ($msg->command eq RPL_ENDOFBANLIST) {
	# +b�ꥹ�Ƚ����
	$got_reply->('b');
    }
    elsif ($msg->command eq RPL_ENDOFEXCEPTLIST) {
	# +e�ꥹ�Ƚ����
	$got_reply->('e');
    }
    elsif ($msg->command eq RPL_ENDOFINVITELIST) {
	# +I�ꥹ�Ƚ����
	$got_reply->('I');
    }
    elsif ($msg->command eq 'JOIN') {
	$session = $this->{sessions}->{$msg->param(0)};
	if (defined $session && defined $msg->nick &&
	    $msg->nick eq RunLoop->shared->current_nick) {
	    # ����ľ������
	    $session->{got_oper} = 1; # ���˥��åȤ���Ƥ���Ȧ����ǰ�Τ���
	    $this->revive($session);
	}
    }

    # $session�����Ǥʤ���С�ɬ�פʾ�������·�ä���ǽ�������롣
    if (defined $session && !$session->{got_oper} &&
	$session->{got_mode} && $session->{got_blist} &&
	$session->{got_elist} && $session->{got_Ilist}) {
	$this->part_and_join($session);
    }
}

sub revive {
    my ($this,$session) = @_;
    Timer->new(
	Interval => 1,
	Repeat => 1,
	Code => sub {
	    my $timer = shift;
	    my $cmd_buf = $session->{cmd_buf};
	    if (@$cmd_buf > 0) {
		# ���٤���Ĥ�������Ф���
		my $msg_per_trigger = 2;
		for (my $i = 0; $i < @$cmd_buf && $i < $msg_per_trigger; $i++) {
		    $session->{server}->send_message($cmd_buf->[$i]);
		}
		splice @$cmd_buf,0,$msg_per_trigger;
	    }
	    if (@$cmd_buf == 0) {
		# cmd_buf�������ä��齪λ��
		# untouchables����õ�
		my $untouchables = BulletinBoard->shared->do_not_touch_mode_of_channels;
		delete $untouchables->{$session->{ch_fullname}};
		# session�õ�
		delete $this->{sessions}->{$session->{ch_fullname}};
		# �����ޡ��򥢥󥤥󥹥ȡ���
		$timer->uninstall;
	    }
	})->install;
}

1;

=pod
info: �����ͥ륪�ڥ졼�����¤�̵�������Ȥ�����ͤʤ�join��ľ����
default: off

# +�����ͥ��+a����Ƥ�������ͥ�ʳ��ǥ����ͥ륪�ڥ졼�����¤��������
# ��ͤ���ˤʤä��������Υ����ͥ��@�����褵���뤿��˼�ưŪ��join��ľ���⥸�塼�롣
# �ȥԥå����⡼�ɡ�ban�ꥹ�����Τ���������ͥ�°�������¸���ޤ���

# +b,+I,+e�ꥹ�Ȥ������Ԥʤ����ɤ�����
# ���ޤ��Ĺ���ꥹ�Ȥ���������Max Send-Q Exceed����Ȥ���뤫���Τ�ޤ���
save-lists: 1
=cut
