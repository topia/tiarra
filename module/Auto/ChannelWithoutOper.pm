# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::ChannelWithoutOper;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use IRCMessage;

sub new {
    my ($class) = @_;
    my $this = $class->SUPER::new;
    $this->{last_message_time} = 0; # �Ǹ�ˤ��Υ⥸�塼�뤬ȯ���������
    $this->{table} = do {
	my %hash = map {
	    my ($ch_long,$msg) = m/^(.+?)\s+(.+)$/;
	    $ch_long => $msg;
	} $this->config->channel('all');
	\%hash;
    };
    $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my $notify = sub {
	my ($ch_long,$ch_short,$str) = @_;
	my $msg_to_send = IRCMessage->new(
	    Command => 'NOTICE',
	    Params => ['',$str]); # �����ͥ�̾�ϸ������
	# ���ˤϥͥåȥ��̾���դ��ʤ���
	my $for_server = $msg_to_send->clone;
	$for_server->param(0,$ch_short);
	$sender->send_message($for_server);

	# ���饤����Ȥˤ��դ��롣Prefix�⼫ư���ꤹ�롣
	my $for_client = $msg_to_send->clone;
	$for_client->param(0,$ch_long);
	$for_client->remark('fill-prefix-when-sending-to-client',1);
	push @result,$for_client;
    };
    
    if ($sender->isa('IrcIO::Server') &&
	defined $msg->nick &&
	$msg->nick ne RunLoop->shared->current_nick &&
	$msg->command eq 'JOIN') {

	foreach (split /,/,$msg->param(0)) {
	    my ($ch_long) = m/^([^\x07]+)/;
	    # ���Υ����ͥ�˳�����Ƥ�줿��å������Ϥ��뤫��
	    my $msg_for_ch = $this->{table}->{$ch_long};
	    if (defined $msg_for_ch) {
		my $ch_short = Multicast::detach($ch_long);
		my $ch = $sender->channel($ch_short);
		# ���Υ����ͥ��+�����ͥ�Ǥ�ʤ���+a��+r�����ꤵ��Ƥ��ʤ�����
		if (defined $ch &&
		    $ch->name !~ m/^\+/ &&
		    !$ch->switches('a') &&
		    !$ch->switches('r')) {
		    
		    # �ʤ�Ȥ�ï�����äƤ��뤫��
		    my $oper_exists;
		    foreach my $person (values %{$ch->names}) {
			if ($person->has_o) {
			    $oper_exists = 1;
			}
		    }
		    if (!$oper_exists) {
			# ȯ�����Ƥ���1�ðʾ�ФäƤ���С�ȯ����
			if (time > $this->{last_message_time} + 1) {
			    $notify->($ch_long,$ch_short,$msg_for_ch);
			    $this->{last_message_time} = time;
			}
		    }
		}
	    }
	}
    }
    @result;
}

1;

=pod
info: �����ͥ륪�ڥ졼�����¤��ʤ��ʤäƤ��ޤä��Ȥ���ȯ�����롣
default: off

# +�ǻϤޤ�ʤ�����Υ����ͥ�ǡ�+a�⡼�ɤǤ�+r�⡼�ɤǤ�ʤ��Τ�
# ï������ͥ륪�ڥ졼�����¤���äƤ��ʤ����֤ˤʤäƤ������
# ������ï����JOIN�����٤�����Υ�å�������ȯ������⥸�塼��Ǥ���

# ��: <�����ͥ�̾> <��å�����>
-channel: #IRC���ü�@ircnet �ʤ�Ⱦü����ޤ�����
=cut
