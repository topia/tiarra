# -----------------------------------------------------------------------------
# $Id: Eval.pm,v 1.4 2004/06/04 12:57:30 topia Exp $
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
	    # ��å������ƹ���
	    my ($method) = join(' ', @{$msg->params}[0 .. ($msg->n_params - 1)]);
	    my ($ret, $err);
	    do {
		# disable warning
		local $SIG{__WARN__} = sub { };
		# die handler
		local $SIG{__DIE__} = sub { $err = $_[0]; };
		no strict;
		# untaint
		$method =~ /\A(.*)\z/s;
		$err = '';
		$ret = eval($1);
	    };

	    my $message = IRCMessage->new(
		Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [RunLoop->shared_loop->current_nick,
			   ''],
	       );
	    do {
		local($Data::Dumper::Terse) = 1;
		map {
		    my $new = $message->clone;
		    $new->param(1, $_);
		    $sender->send_message($new);
		} (
		    (split /\n/, 'method: '.Dumper($method)),
		    (split /\n/, 'result: '.Dumper($ret)),
		    (split /\n/, 'error: '.$err),
		   );
		return undef;
	    };
	}
    }

    return $msg;
}

# useful functions to call from eval
sub network {
    return runloop()->network(shift);
}

sub runloop {
    return RunLoop->shared_loop;
}
1;
=pod
info: ���饤����Ȥ��� Perl ����¹ԤǤ���褦�ˤ��롣
default: off

# eval ��¹Ԥ��륳�ޥ��̾����ά�����ȥ��ޥ�ɤ��ɲä��ޤ���
# ���λ����ޥ�ɤ�Tiarra�������٤��Τǡ�IRC�ץ�ȥ�����������줿
# ���ޥ��̾�����ꤹ�٤��ǤϤ���ޤ���
command: eval
=cut
