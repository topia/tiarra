# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Client::Eval;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Timer;
use Data::Dumper;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # ���饤����Ȥ���Υ�å���������
    if ($sender->isa('IrcIO::Client')) {
	# ���ꤵ�줿���ޥ�ɤ�?
	if (Mask::match_deep([$this->config->command('all')], $msg->command)) {
	    # ��å������ƹ���
	    my ($method) = join(' ', @{$msg->params});
	    my ($ret, $err);
	    do {
		# disable warning
		local $SIG{__WARN__} = sub { };
		# die handler
		#local $SIG{__DIE__} = sub { $err = $_[0]; };
		no strict;
		# untaint
		$method =~ /\A(.*)\z/s;
		$err = '';
		$ret = eval($1);
	    };
	    $err = $@;

	    my $message = IRCMessage->new(
		Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [RunLoop->shared_loop->current_nick,
			   ''],
	       );
	    do {
		local($Data::Dumper::Terse) = 1;
		local($Data::Dumper::Purity) = 1;
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
sub runloop { return RunLoop->shared; }
sub network { return runloop->network(shift); }
sub conf { return Configuration->shared; }
sub module_manager { return ModuleManager->shared_manager; }
sub module { return module_manager->get(shift); }
sub shutdown { return ::shutdown; }
sub reload {
    ReloadTrigger->_install_reload_timer;
    return undef;
}
sub reload_mod {
    my $name = shift;
    delete $INC{$name};
    require $name;
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
