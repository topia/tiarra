# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::Rehash;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use NumericReply;
use Timer;

my $timer_name = __PACKAGE__.'/timer';

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
}

sub destruct {
    my ($this) = shift;

    # timer ������в��
    foreach my $client (RunLoop->shared_loop->clients_list) {
	my $timer = $client->remark($timer_name);
	if (defined $timer) {
	    $client->remark($timer_name, undef, 'delete');
	    $timer->uninstall;
	}
    }
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # ���饤����Ȥ���Υ�å���������
    if ($sender->isa('IrcIO::Client')) {
	my $runloop = RunLoop->shared_loop;
	# ���ꤵ�줿���ޥ�ɤ�?
	if (Mask::match_deep([$this->config->command_nick('all')], $msg->command)) {
	    if (!defined $msg->param(0)) {
	    } elsif ($msg->param(0) eq $runloop->current_nick) {
	    } else {
		$sender->send_message(
		    IRCMessage->new(
			Prefix => $msg->param(0).'!'.$sender->username.'@'.
			    $sender->client_host,
			Command => 'NICK',
			Param => $runloop->current_nick,
		       ));

	    }
	    # �����Ǿä���
	    return undef;
	} elsif (Mask::match_deep([$this->config->command_names('all')], $msg->command)) {
	    my @channels = map {
		my $network_name = $_->network_name;
		map {
		    [$network_name, $_->name];
		} $_->channels_list;
	    } $runloop->networks_list;
	    $sender->remark($timer_name, Timer->new(
	       Interval => (defined $this->config->interval ?
				$this->config->interval : 2),
	       Repeat => 1,
	       Code => sub {
		   my $timer = shift;
		   my $runloop = RunLoop->shared_loop;
		   while (1) {
		       my $entry = shift(@channels);
		       if (defined $entry && $sender->connected) {
			   my ($network_name, $ch_name) = @$entry;
			   my $network = $runloop->network($network_name);
			   my $flush_namreply = sub {
			       my $msg = shift;
			       $msg->param(0, $runloop->current_nick);
			       $sender->send_message($msg);
			   };
			   if (!defined $network) {
			       # network disconnected. ignore
			       next;
			   }
			   my $ch = $network->channel($ch_name);
			   if (!defined $ch) {
			       # parted channel; ignore
			       next;
			   }
			   $sender->do_namreply($ch, $network,
						undef, $flush_namreply);
		       } else {
			   $sender->remark($timer_name, undef, 'delete');
			   $timer->uninstall;
		       }
		       last;
		   }
	       },
	      )->install);

	    # �����Ǿä���
	    return undef;
	}
    }

    return $msg;
}

1;
=pod
info: �������ͥ�ʬ�� names ����������å���򥯥饤����Ȥ��������롣
default: off

# ��Ȥ�Ȥϥ��饤����Ȥκƽ������Ū�˺�ä��ΤǤ����� names ���������Ƥ�
# ��������ʤ����饤����Ȥ�¿���Τǡ���� multi-server-mode �� Tiarra ��
# ���ˤ���� Tiarra ��Ĥʤ��Ǥ���͸����ˤ��ޤ���

# names �ǥ˥å��ꥹ�Ȥ򹹿����Ƥ���륯�饤�����:
#   Tiarra
# ���Ƥ���ʤ����饤�����: (�����ϳ�ǧ�����С������ޤ������)
#   LimeChat(1.18)

# nick rehash �˻Ȥ����ޥ�ɤ���ꤷ�ޤ���
# ����ѥ�᡼���Ȥ��Ƹ��ߥ��饤����Ȥ�ǧ�����Ƥ��� nick ����ꤷ�Ƥ���������
command-nick: rehash-nick

# names rehash �˻Ȥ����ޥ�ɤ���ꤷ�ޤ���
command-names: rehash-names

# �����ͥ�ȥ����ͥ�δ֤Υ������Ȥ���ꤷ�ޤ���
interval: 2
=cut
