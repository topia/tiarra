# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Channel::Join::Kicked;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->server_p && $msg->command eq 'KICK' &&
        $msg->param(1) eq $sender->current_nick &&
	Mask::match_deep([$this->config->channel('all')],$msg->param(0))) {
	# ��ʬ������줿��
	# +k����Ƥ�������ͥ�ʤ饭����ɤ��դ��롣
	my $ch = RunLoop->shared->channel($msg->param(0));
	if (defined $ch) {
	    my @params = ($ch->name);
	    if ($ch->parameters('k')) {
		push @params,$ch->parameters('k');
	    }

	    $sender->send_message(
		$this->construct_irc_message(
		    Command => 'JOIN',
		    Params => \@params));
	}
    }

    $msg;
}

1;

=pod
info: ����Υ����ͥ뤫��kick���줿���ˡ���ư������ʤ�����
default: off
section: important

# �оݤȤʤ�����ͥ�̾�Υޥ���
channel: *
=cut
