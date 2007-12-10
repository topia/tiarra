# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Utils;
use strict;
use warnings;
use Module::Use qw(Auto::AliasDB);
use Auto::AliasDB;
use Multicast;
use RunLoop;
use base qw(Tiarra::IRC::NewMessageMixin);

# get_ch_name �� get_raw_ch_name �Υ����ꥢ��(���ߴ��Τ���)
*get_ch_name = \&get_raw_ch_name;
sub get_raw_ch_name {
    # �ͥåȥ��̾ȴ����������(�����ͥ�/nick)̾ or undef ������
    my ($msg, $ch_place) = @_;

    if (defined($msg->param($ch_place)) && $msg->param($ch_place) ne '') {
	return(scalar(Multicast::detach($msg->param($ch_place))));
    } else {
	return undef;
    }
}

sub get_full_ch_name {
    # �ͥåȥ��̾�դ���������(�����ͥ�/nick)̾ or undef ������
    my ($msg, $ch_place) = @_;

    if (defined($msg->param($ch_place)) && $msg->param($ch_place) ne '') {
	return($msg->param($ch_place));
    } else {
	return undef;
    }
}

sub sendto_channel_closure {
    # �����ͥ����� PRIVMSG / NOTICE �����륯��������֤��ޤ���

    # - ���� -
    # $sendto	: �����ͥ�̾ or �˥å����ͥåȥ��̾���դ��Ʋ�������
    # $command	: 'PRIVMSG' or 'NOTICE'������¾�Υ��ޥ�ɤ����¤Ϥ��ޤ��󤬰�̣��̵���Ǥ��礦��
    # $msg	: message_arrived���ϤäƤ���$msg�������ꥢ���ִ��˻��Ѥ���ޤ�����äơ�
    #               ��Ҥ��� $use_alias �� false �ʤ���ꤹ��ɬ�פϤ���ޤ���
    #               ���ξ��� undef �Ǥ��Ϥ��Ƥ����ޤ��礦��
    # $sender	: message_arrived���ϤäƤ���$sender�������˻Ȥ��ޤ����ʤ�����
    #               $result �ȤȤ�� undef ����ꤷ�Ƥ���������
    # $result	: message_arrived���֤��ͤˤ�������λ��ȡ��ܺ٤���򸫤ޤ��礦��
    # $use_alias	: �����ꥢ���֤�������Ԥ����ɤ�������ά�ĤǾ�ά��������
    #                       �Ԥ����� $msg, $sender �Τɤ��餫�� undef �ʤ饨���ꥢ��
    #                       �֤�������ƤӽФ��ʤ��ΤǹԤ�ʤ���
    # $extra_callbacks
    # 		: �ɲäΥ����ꥢ���ִ�������Хå�����ά�ġ�
    #
    # �����ꥢ���ִ���������Хå��˴ؤ��Ƥ� Auto::AliasDB �򻲾Ȥ��Ƥ���������
    #
    # - �֤��� -
    # 	$send_message
    # $send_message
    # 		: �������㡣�������˥�å���������������ʹߤ��ɲäΥ����ꥢ��(��ά��ǽ)����ꤷ�ƸƤӽФ���
    #               ��å������Ȥ���undef���Ϥ��줿���ϡ����⤻���˽�λ���롣
    #
    # - ������ -
    #       sub message_arrived {
    #           my ($this,$msg,$sender) = @_;
    #           my @result = ($msg);
    #           my $send_message = 
    #               sendto_channel_closure('#test@ircnet', 'NOTICE', $msg, $sender, \@result);
    #           $send_message->('message', 'hoge' => 'moge');
    #           return @result;
    #       }
    #

    my ($sendto, $command, $msg, $sender, $result, $use_alias, $extra_callbacks) = @_;

    $use_alias = 1 if (!defined $use_alias && defined $msg && defined $sender);
    $extra_callbacks = [] unless defined $extra_callbacks;

    return sub {
	my ($line,%extra_replaces) = @_;
	return if !defined $line;
	foreach my $str ((ref($line) eq 'ARRAY') ? @$line : $line) {
	    my $msg_to_send = __PACKAGE__->construct_irc_message(
		Command => $command,
		Params => ['',	# �������
			   ($use_alias ? Auto::AliasDB->shared->stdreplace_add(
			       $msg->prefix || $sender->fullname,
			       $str,
			       $extra_callbacks,
			       $msg,
			       $sender,
			       %extra_replaces)
				: $str)]);
	    my ($rawname, $network_name, $specified_network) =
		Multicast::detach($sendto);
	    my $get_network_name = sub {
		$specified_network ? $network_name :
		    Configuration->shared_conf->networks->default;
	    };
	    my $sendto_client = Multicast::attach_for_client($rawname, $network_name);
	    if (!defined $sender) {
		# ���ˤϥ����ͥ�̾�˥ͥåȥ��̾���դ��ʤ���
		my $for_server = $msg_to_send->clone;
		$sender = RunLoop->shared_loop->network($get_network_name->());
		if (defined $sender) {
		    $for_server->param(0, $rawname);
		    $sender->send_message($for_server);
		}

		# ���饤����Ȥˤϥ����ͥ�̾�˥ͥåȥ��̾���դ��롣
	    # �ޤ������饤����Ȥ���������ˤ�Prefix�����Υ桼���������ꤵ���褦�����դ��롣
		my $for_client = $msg_to_send->clone;
		$for_client->param(0, $sendto_client);
		$for_client->remark('fill-prefix-when-sending-to-client',1);
		RunLoop->shared_loop->broadcast_to_clients($for_client);
	    } elsif ($sender->isa('IrcIO::Server')) {
		# ���ˤϥ����ͥ�̾�˥ͥåȥ��̾���դ��ʤ���
		my $for_server = $msg_to_send->clone;
		$for_server->param(0, $rawname);
		$sender->send_message($for_server);

		# ���饤����Ȥˤϥ����ͥ�̾�˥ͥåȥ��̾���դ��롣
		# �ޤ������饤����Ȥ���������ˤ�Prefix�����Υ桼���������ꤵ���褦�����դ��롣
		my $for_client = $msg_to_send->clone;
		$for_client->param(0, $sendto_client);
		$for_client->remark('fill-prefix-when-sending-to-client',1);
		push @$result,$for_client;
	    } elsif ($sender->isa('IrcIO::Client')) {
		# �����ͥ�̾�˥ͥåȥ��̾���դ��롣
		my $for_server = $msg_to_send->clone;
		$for_server->param(0, $sendto);
		push @$result,$for_server;

		my $for_client = $msg_to_send->clone;
		$for_client->prefix($sender->fullname);
		$for_client->param(0, $sendto_client);
		$sender->send_message($for_client);
	    }
	}
    };
}

sub generate_reply_closures {
    # �����Ԥ� NOTICE ���������륯��������֤��ޤ���

    # - ���� -
    # $msg	: message_arrived���ϤäƤ���$msg��
    # $sender	: message_arrived���ϤäƤ���$sender��
    # $result	: message_arrived���֤��ͤˤ�������λ��ȡ��ܺ٤���򸫤ޤ��礦��
    # $use_alias	: �����ꥢ���֤�������Ԥ����ɤ�������ά�ġ���ά�������ϹԤ���
    # $extra_callbacks
    #		: �ɲäΥ����ꥢ���ִ�������Хå�����ά�ġ�
    # $ch_place	: �����ͥ�̾��¸�ߤ��� $msg->param �����ΰ��֤���ꤷ�ޤ�����ά����0(��Ƭ)�Ǥ���
    #
    # �����ꥢ���ִ���������Хå��˴ؤ��Ƥ� Auto::AliasDB �򻲾Ȥ��Ƥ���������
    #
    # - �֤��� -
    # 	($get_raw_ch_name, $reply, $reply_as_priv, $reply_anywhere, $get_full_ch_name)
    # $get_raw_ch_name	: �������㡣�ͥåȥ��̵̾���Υ����ͥ�̾ or undef ���֤��ޤ���
    # $reply		: �������㡣�����ͥ���������ޤ���
    # $reply_as_priv	: �������㡣�����Ԥ�ľ�� priv ���������ޤ���
    # $reply_anywhere	: �������㡣�����ͥ뤬ͭ���Ǥ���� $reply ���������Ǥʤ���� $reply_as_priv �Ǥ���
    # $get_full_ch_name	: �������㡣�ͥåȥ��̾�դ��Υ����ͥ�̾ or undef ���֤��ޤ���
    #
    # $reply* ���������˥�å���������������ʹߤ��ɲäΥ����ꥢ��(��ά��ǽ)����ꤷ�ƸƤӽФ��ޤ���
    # ��������undef���Ϥ��줿���ϡ����⤻���˽�λ���ޤ���
    #
    # - ������ -
    #       sub message_arrived {
    #           my ($this,$msg,$sender) = @_;
    #           my @result = ($msg);
    #           my ($get_ch_name, $reply, $reply_as_priv, $reply_anywhere) = 
    #               generate_reply_closures($msg, $sender, \@result);
    #           $reply_anywhere->('message', 'hoge' => 'moge');
    #           return @result;
    #       }
    #
    # - ���� -
    # $get_raw_ch_name ����������ʤΤϲ��Ȥθߴ����Τ��ᡢ
    # $get_full_ch_name ���������㡼�ʤΤ϶������Τ���Ǥ���

    my ($msg, $sender, $result, $use_alias, $extra_callbacks, $ch_place) = @_;
    $use_alias = 1 unless defined $use_alias;
    $extra_callbacks = [] unless defined $extra_callbacks;
    $ch_place = 0 unless defined $ch_place;

    my $raw_ch_name = get_raw_ch_name($msg, $ch_place);
    my $get_raw_ch_name = sub () {
	$raw_ch_name;
    };
    my $full_ch_name = get_full_ch_name($msg, $ch_place);
    my $get_full_ch_name = sub () {
	$full_ch_name;
    };
    my $reply = sub {
	sendto_channel_closure($msg->param($ch_place), 'NOTICE', $msg, $sender, $result,
			       $use_alias, $extra_callbacks)->(@_, 'channel' => $raw_ch_name);
    };
    my $reply_as_priv = sub {
	my ($line,%extra_replaces) = @_;
	return if !defined $line;
	foreach my $str ((ref($line) eq 'ARRAY') ? @$line : $line) {
	    $sender->send_message(__PACKAGE__->construct_irc_message(
		Command => 'NOTICE',
		Params => [$msg->nick,
			   ($use_alias ? Auto::AliasDB->shared->stdreplace_add(
			       $msg->prefix,
			       $str,
			       $extra_callbacks,
			       $msg,
			       $sender,
			       %extra_replaces)
				: $str)]));
	}
    };
    my $reply_anywhere = sub {
	if (defined($raw_ch_name) && Multicast::nick_p($raw_ch_name)) {
	    return $reply_as_priv;
	} else {
	    return $reply;
	}
    };
    return ($get_raw_ch_name,$reply,$reply_as_priv,$reply_anywhere->(),$get_full_ch_name);
}

1;
