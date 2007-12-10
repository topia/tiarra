# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package User::Vanish;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
our $DEBUG = 0;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    my $result = $msg;
    if ($sender->server_p) {
	my $method = 'cmd_'.$msg->command;
	if ($this->can($method)) {
	    if ($DEBUG) {
		my $original = $msg->serialize;
		$result = $this->$method($msg, $sender);
		my $filtered = (defined $result ? $result->serialize : '');
		if ($original ne $filtered) {
		    # ���Ƥ��񴹤ؤ�줿��
		    my $debug_msg = "'$original' -> '$filtered'";
		    eval {
			substr($debug_msg, 400) = '...';
		    };
		    RunLoop->shared->notify_msg($debug_msg);
		}
	    }
	    else {
		$result = $this->$method($msg, $sender);
	    }
	}
    }
    elsif ($sender->client_p) {
	if ($msg->command eq 'VANISHDEBUG') {
	    $DEBUG = $msg->param(0);
	    RunLoop->shared->notify_msg("User::Vanish - debug-mode ".($DEBUG?'enabled':'disabled'));
	    $result = undef;
	}
    }

    $result;
}

*cmd_NOTICE = \&cmd_PRIVMSG;
sub cmd_PRIVMSG {
    my ($this,$msg,$sender) = @_;

    # ȯ�Ը���Vanish�оݤ���
    my $ch_long = $msg->param(0);
    my $ch_short = Multicast::detach($ch_long);
    if (Multicast::nick_p($ch_short)) {
	$ch_long = '#___priv___@'.$sender->network_name;
    }

    if ($this->target_of_vanish_p($msg->prefix,$ch_long)) {
	undef;
    }
    else {
	$msg;
    }
}

sub cmd_JOIN {
    my ($this,$msg,$sender) = @_;
    my @channels; # �����ͥ�ꥹ�Ȥ�ƹ������롣
    foreach my $channel (split m/,/,$msg->param(0)) {
	my ($ch_full,$mode) = ($channel =~ m/^([^\x07]+)(?:\x07(.*))?/);
	if (!$this->target_of_vanish_p($msg->prefix,$ch_full)) {
	    push @channels,$channel;
	}
    }

    if (@channels > 0) {
	# �ƹ����η�̡������ͥ뤬�ޤ��ĤäƤ���
	$msg->param(0,join(',',@channels));
    }
    else {
	$msg = undef;
    }

    $msg;
}

sub cmd_NJOIN {
    my ($this,$msg,$sender) = @_;
    my $ch_long = $msg->param(0);
    my $ch_short = Multicast::detach($ch_long);
    my $ch = $sender->channel($ch_short);
    if (defined $ch) {
	my @nicks;
	foreach my $mode_and_nick (split m/,/,$msg->param(1)) {
	    my ($mode,$nick) = ($mode_and_nick =~ m/^([@+]*)(.+)$/);
	    my $person = $ch->names($nick);
	    if (!defined $person || !$this->target_of_vanish_p) {
		push @nicks,$mode_and_nick;
	    }
	}

	if (@nicks > 0) {
	    # �ƹ����η�̡�nick���ޤ��ĤäƤ���
	    $msg->param(1,join(',',@nicks));
	}
	else {
	    $msg = undef;
	}
    }

    $msg;
}

sub cmd_PART {
    my ($this,$msg,$sender) = @_;
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	undef;
    }
    else {
	$msg;
    }
}

sub cmd_INVITE {
    my ($this,$msg,$sender) = @_;
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(1))) {
	undef;
    }
    else {
	$msg;
    }
}

*cmd_QUIT = \&cmd_NICK;
sub cmd_NICK {
    my ($this,$msg,$sender) = @_;

    # �ƶ���ڤܤ����������ͥ�̾�Υꥹ�Ȥ����롣���Υꥹ�Ȥˤϥͥåȥ��̾���դ��Ƥ��ʤ���
    my $affected = $msg->remark('affected-channels');
    # ��ĤǤ�Vanish�оݤǤʤ������ͥ��nick���Ȥߤ�����С�����NICK���˴����ʤ���
    my $no_vanish;
    foreach (@$affected) {
	my $ch_long = Multicast::attach($_,$sender->network_name);
	if (!$this->target_of_vanish_p($msg->prefix,$ch_long)) {
	    $no_vanish = 1;
	    last;
	}
    }

    if ($no_vanish) {
	$msg;
    }
    else {
	undef;
    }
}

sub cmd_TOPIC {
    my ($this,$msg,$sender) = @_;
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	if ($this->config->drop_topic_by_target) {
	    $msg->prefix('HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH');
	}
    }
    $msg;
}

sub cmd_353 {
    # RPL_NAMREPLY
    my ($this,$msg,$sender) = @_;

    my $ch_long = $msg->param(2);
    my $ch_short = Multicast::detach($ch_long);
    my $ch = $sender->channel($ch_short);
    if (defined $ch) {
	my @nicks;
	foreach my $mode_and_nick (split / /,$msg->param(3)) {
	    my ($mode,$nick) = ($mode_and_nick =~ m/^([@\+]{0,2})(.+)$/);
	    my $person = $ch->names($nick);
	    if (!defined $person || !$this->target_of_vanish_p($person->info,$ch_long)) {
		push @nicks,$mode_and_nick;
	    }
	}
	$msg->param(3,join(' ',@nicks));
    }

    $msg;
}

sub cmd_MODE {
    my ($this,$msg,$sender) = @_;

    # ȯ�Ը���Vanish�оݤ���
    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	if ($this->config->drop_mode_by_target) {
	    # prefix����
	    $msg->prefix('HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH');
	}
    }

    # +o/-o/+v/-v���оݤ�Vanish���оݤ���
    my $ch_long = $msg->param(0);
    my $ch_short = Multicast::detach($ch_long);
    my $ch = $sender->channel($ch_short);
    if (defined $ch && (sub{defined$_[0]?$_[0]:1}->($this->config->drop_mode_switch_for_target))) {
	my $n_params = @{$msg->params};
	my $plus = 0; # ����ɾ����Υ⡼�ɤ�+�ʤΤ�-�ʤΤ���
	my $mode_char_pos = 1; # ����ɾ�����mode character�ΰ��֡�
	my $mode_param_offset = 0; # $mode_char_pos������Ĥ��ɲåѥ�᥿�򽦤ä�����

	my $fetch_param = sub {
	    $mode_param_offset++;
	    return $msg->param($mode_char_pos + $mode_param_offset);
	};

	my @params = ($ch_long); # �ѥ�᡼����ƹ��ۤ��롣
	my $add = sub {
	    my ($char,$option) = @_;
	    push @params,($plus ? '+' : '-').$char;
	    if (defined $option) {
		push @params,$option;
	    }
	};

	for (;$mode_char_pos < $n_params;$mode_char_pos += $mode_param_offset + 1) {
	    $mode_param_offset = 0; # ��������ꥻ�åȤ��롣
	    foreach my $c (split //,$msg->param($mode_char_pos)) {
		if ($c eq '+') {
		    $plus = 1;
		}
		elsif ($c eq '-') {
		    $plus = 0;
		}
		elsif (index('bIk',$c) != -1) {
		    $add->($c,$fetch_param->());
		}
		elsif (index('Oov',$c) != -1) {
		    my $target = $fetch_param->();
		    my $person = $ch->names($target);
		    if (!defined $person || !$this->target_of_vanish_p($person->info,$ch_long)) {
			$add->($c,$target);
		    }
		}
		elsif ($c eq 'l') {
		    if ($plus) {
			$add->($c,$fetch_param->()); # �ɲåѥ�᥿��ΤƤ�
		    }
		    else {
			$add->($c);
		    }
		}
		else {
		    $add->($c);
		}
	    }
	}

	# �ѥ�᥿�ƹ����η�̡���Ĥ�̵���ʤä��顢���Υ�å��������˴���
	if (@params > 1) {
	    $msg = $this->construct_irc_message(
		Prefix => $msg->prefix,
		Command => $msg->command,
		Params => \@params);
	}
	else {
	    $msg = undef;
	}
    }
    $msg;
}

sub cmd_KICK {
    my ($this,$msg,$sender) = @_;

    if ($this->target_of_vanish_p($msg->prefix,$msg->param(0))) {
	if ($this->config->drop_kick_by_target) {
	    $msg->prefix('HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH');
	}
    }

    my $kicked_nick = $msg->param(1);
    my $ch = $sender->channel(Multicast::detach($msg->param(0)));
    if (defined $ch) {
	if ($this->config->drop_kick_for_target) {
	    $msg = undef;
	}
    }

    $msg;
}

sub target_of_vanish_p {
    # $userinfo: nick!name@host�����Υ桼��������
    # $ch_long : �ͥåȥ��̾�դ��Υ����ͥ�̾
    # �����: ������
    my ($this,$userinfo,$ch_long) = @_;
    Mask::match_deep_chan([$this->config->mask('all')],$userinfo,$ch_long);
}

1;

=pod
info: ���ꤵ�줿��ʪ��¸�ߤ��͡��ʥ�å���������õ�롣
default: off

# �оݤȤʤä���ʪ��ȯ�Ԥ���JOIN��PART��INVITE��QUIT��NICK�Ͼõ�졢NAMES���֤��͡���ꥹ�Ȥ����ä��롣
# �ޤ����оݤȤʤä���ʪ��NJOIN��õ��롣

# Vanish�оݤ�ȯ�Ԥ���MODE��õ�뤫�ɤ������ǥե���Ȥ�0��
# �õ��Ȥϱ�����������MODE���Τ�Τ�ä��Ƥ��ޤ��ΤǤϤʤ���
# ���Υ桼�����������"HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH"��MODE��¹Ԥ������ˤ��롣
drop-mode-by-target: 1

# Vanish�оݤ��оݤȤ���MODE +o/-o/+v/-v��õ�뤫�ɤ������ǥե���Ȥ�1��
drop-mode-switch-for-target: 1

# Vanish�оݤ�ȯ�Ԥ���KICK��õ�뤫�ɤ������ǥե���Ȥ�0��
# �����˾ä��ΤǤϤʤ���"HIDDEN!HIDDEN@HIDDEN.BY.USER.VANISH"��KICK��¹Ԥ������ˤ��롣
drop-kick-by-target: 1

# Vanish�оݤ��оݤȤ���KICK��õ�뤫�ɤ������ǥե���Ȥ�0��
drop-kick-for-target: 0

# Vanish�оݤ�ȯ�Ԥ���TOPIC��õ�뤫�ɤ������ǥե���Ȥ�0��
# �����˾ä��ΤǤ�̵������¾�������Ʊ����
drop-topic-by-target: 1

# �����ͥ��Vanish�оݤ������
# ����Υ����ͥ�ǤΤ��оݤȤ��롢�Ȥ��ä�������ǽ��
# �ޤ���priv�ξ��ϡ�#___priv___@�ͥåȥ��̾�פȤ���ʸ���������ͥ�̾������Ȥ��ƥޥå��󥰤�Ԥʤ���
# ��: mask: <�����ͥ�Υޥ���> <�桼�����Υޥ���>
mask: #example@example  example!exapmle@example.com
=cut
