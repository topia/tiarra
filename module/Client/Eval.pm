# -----------------------------------------------------------------------------
# $Id: Reload.pm,v 1.3 2003/11/09 09:04:18 topia Exp $
# -----------------------------------------------------------------------------
package Client::Eval;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Data::Dumper;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # ���饤����Ȥ���Υ�å���������
    if ($sender->isa('IrcIO::Client')) {
	# ���ꤵ�줿���ޥ�ɤ�?
	if (Mask::match_deep([$this->config->command('all')], $msg->command)) {
	    my ($method) = $msg->param(0);
	    my ($ret, $err);
	    do {
		# disable warning
		local $SIG{__WARN__} = sub { };
		# die handler
		local $SIG{__DIE__} = sub { $err = $_[0]; };
		no strict;
		$ret = eval($method);
	    };

	    my $message = IRCMessage->new(
		Command => 'NOTICE',
		Params => [RunLoop->shared_loop->current_nick,
			   ''],
		Remarks => {
		    'fill-prefix-when-sending-to-client' => 1,
		},
	       );
	    do {
		local($Data::Dumper::Terse) = 1;
		map {
		    my $new = $message->clone;
		    $new->param(1, $_);
		    $sender->send_message($new);
		} (
		    'method: '.Dumper($method),
		    'result: '.Dumper($ret),
		    'error: '.$err,
		   );
		return undef;
	    };
	}
    }

    return $msg;
}

1;
=pod
info: ���饤����Ȥ��� Perl ����¹ԤǤ���褦�ˤ��롣
default: off

# eval ��¹Ԥ��륳�ޥ��̾����ά�����ȥ��ޥ�ɤ��ɲä��ޤ���
# ���λ����ޥ�ɤ�Tiarra�������٤��Τǡ�IRC�ץ��ȥ�����������줿
# ���ޥ��̾�����ꤹ�٤��ǤϤ���ޤ���
command: eval
=cut