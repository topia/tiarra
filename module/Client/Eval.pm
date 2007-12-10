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
	my $cmd = Mask::match_deep([$this->config->command('all')], $msg->command);
	my $hexcmd = Mask::match_deep([$this->config->hex_command('all')], $msg->command);
	if ($cmd || $hexcmd) {
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

	    my $message = $this->construct_irc_message(
		Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [RunLoop->shared_loop->current_nick,
			   ''],
	       );
	    my $process = sub {
		if (defined $this->config->max_line &&
			@_ > $this->config->max_line) {
		    splice @_, $this->config->max_line;
		}
		map {
		    if ($hexcmd) {
			s/([^\s,'[:print:]])/'\x'.unpack('H*', $1)/eg;
			s/\$/\\\$/g;
		    }
		    $_;
		} @_;
	    };
	    do {
		my $dumper = sub {
		    my $val = shift;
		    local $SIG{__WARN__} = sub {};
		    Data::Dumper->new([$val])->Terse(1)->Purity(1)
			    ->Seen({
				($this->_runloop ne $val) ?
				    (current_runloop => $this->_runloop) :
					(),
			    })->Dump."\n";
		};
		map {
		    my $new = $message->clone;
		    $new->param(1, $_);
		    $sender->send_message($new);
		} (
		    $process->(split /\n/, 'method: '.$dumper->($method)),
		    $process->(split /\n/, 'result: '.$dumper->($ret)),
		    $process->(split /\n/, 'error: '.$err),
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
sub shutdown { return ::shutdown(); }
sub reload {
    ReloadTrigger->_install_reload_timer;
    return undef;
}

sub reload_mod {
    my $name = shift;
    $name .= '.pm';
    $name =~ s|::|/|g;
    reload_pm($name);
}

sub reload_pm {
    my $file = shift;
    delete $INC{$file};
    require $file;
}

1;
=pod
info: ���饤����Ȥ��� Perl ����¹ԤǤ���褦�ˤ��롣
default: off

# eval ��¹Ԥ��륳�ޥ��̾����ά�����ȥ��ޥ�ɤ��ɲä��ޤ���
# ���λ����ޥ�ɤ�Tiarra�������٤��Τǡ�IRC�ץ�ȥ�����������줿
# ���ޥ��̾�����ꤹ�٤��ǤϤ���ޤ���
command: eval

# hex eval ��¹Ԥ��륳�ޥ��̾����ά�����ȥ��ޥ�ɤ��ɲä��ޤ���
# ���λ����ޥ�ɤ�Tiarra�������٤��Τǡ�IRC�ץ�ȥ�����������줿
# ���ޥ��̾�����ꤹ�٤��ǤϤ���ޤ���
hex-command: hexeval

# ɽ���������Կ�����ꤷ�ޤ�����ά����Ȥ��٤ƤιԤ�ɽ�����ޤ���
max-line: 30

=cut
