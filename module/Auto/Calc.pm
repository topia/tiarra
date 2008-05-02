# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.
package Auto::Calc::Share;
use strict;
our $__export = [qw(pi pie e frac)];
sub export () { $__export }

sub pi () { 3.141592653589793238 }
sub pie () { pi }
sub e () { exp(1) }
sub frac ($) { $_[0] - int($_[0]) }

package Auto::Calc;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Auto::Calc::Share);
use Auto::Utils;
use Mask;

use Symbol ();
use Safe;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{safe} = Safe->new(__PACKAGE__.'::Root');
    $this->{safe}->erase;
    $this->{safe}->permit_only(qw(:base_core :base_math :base_orig),
			       qw(pack unpack),
			       qw(atan2 sin cos exp log sqrt),
			      );
    if (!$this->config->permit_sub) {
	$this->{safe}->deny(qw(leavesub));
    }
    my $pkg = __PACKAGE__.'::Share';
    $this->{safe}->share_from($pkg, $pkg->export);

    return $this;
}

sub destruct {
    my ($this) = shift;

    Symbol::delete_package(__PACKAGE__.'::Root')
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my $return_value = sub {
	return @result;
    };

    my (undef,undef,undef,$reply_anywhere,$get_full_ch_name)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

    if ($msg->command eq 'PRIVMSG') {
	my $method = $msg->param(1);
	$method =~ s/^\s*(.*)\s*$/$1/;

	# init
	if (Mask::match_deep([$this->config->init('all')], $method)) {
	    if (Mask::match_deep_chan([$this->config->init_mask('all')],
				      $msg->prefix, $get_full_ch_name->())) {
		$this->{safe}->reinit;
		$reply_anywhere->([$this->config->init_format('all')]);
		return $return_value->();
	    }
	}

	my $keyword;
	($keyword, $method) = split(/\s+/, $method, 2);

	# request
	if (Mask::match_deep([$this->config->request('all')], $keyword)) {
	    if (Mask::match_deep_chan([$this->config->mask('all')],
				      $msg->prefix, $get_full_ch_name->())) {
		my ($ret, $err, $signal);
		do {
		    # disable warning
		    local $SIG{__WARN__} = sub { };
		    #
		    my $signal_handler = sub {
			$signal = shift;
			die "$signal called";
		    };
		    # floating point exceptions
		    local $SIG{FPE} = sub { $signal_handler->('SIGFPE'); }
			if exists $SIG{FPE};
		    # alarm
		    local $SIG{ALRM} = sub { $signal_handler->('ALARM'); }
			if exists $SIG{ALRM};
		    my $timeout = $this->config->timeout;
		    $timeout = 1 unless defined $timeout;
		    # die handler
		    local $SIG{__DIE__} = sub {
			$err = shift;
			die '';
		    };

		    alarm $timeout if ($timeout);
		    no strict;
		    $ret = $this->{safe}->reval($method);
		    alarm 0 if ($timeout);
		};

		my $reply = sub {
		    my $array = shift;

		    map {
			if (defined($$_)) {
			    # �����ν���
			    $$_ =~ tr/\t\x0a\x0d/ /;
			    $$_ =~ tr/\x00-\x19//d;
			    $$_ =~ s/^\s+//;
			    $$_ =~ s/\s+$//;
			    $$_ =~ s/\s{2,}/ /;
			} else {
			    $$_ = $this->config->undef || 'undef';
			}
		    } (\$ret, \$err);

		    if ($err) {
			$err =~ s/ +at \(eval \d+\) line \d+//;
			$err =~ s/, <DATA> line \d+//;
		    }

		    map {
			$reply_anywhere->(
			    $_,
			    method => $method,
			    result => $ret,
			    error => $err,
			    signal => $signal,
			   );
		    } @$array;
		};

		my @format_names;
		if ($signal) {
		    push(@format_names, 'signal-'.lc($signal).'-format');
		    push(@format_names, 'signal-format');
		}
		if ($err) {
		    my $format = undef;
		    # format �θ��̲�
		    my $error_name = $err;
		    if ($this->config->error_name_formatter) {

		    }
		    $error_name =~ s/'.+' (trapped by operation mask)/$1/;
		    $error_name =~ s/(Undefined subroutine) \&.+ (called)/$1 $2/;
		    $error_name =~ tr/ _/-/;
		    $error_name =~ tr/'`//d;
		    $error_name =~ s/\.$//;
		    $error_name =~ s/-+$//;
		    $error_name = lc($error_name);
		    #::debug_printmsg("error_name: $error_name");

		    push(@format_names, 'error-format');
		} else {
		    push(@format_names, 'reply-format');
		}
		foreach my $format_name (@format_names) {
		    my @formats = $this->config->get($format_name, 'all');
		    next if $#formats != 0;
		    $reply->(\@formats);
		    last;
		}
	    }
	}
    }

    return $return_value->();
}

1;
=pod
info: Perl�μ���׻�������⥸�塼�롣
default: off

# ȿ������ȯ������ꤷ�ޤ���
request: �׻�

# ���Ѥ���Ĥ����&�����ͥ�Υޥ�����
# ���Tiarra�⡼�ɻ��� [default: �ʤ�]
mask: * +*!*@*
# [plum-mode] mask: +*!*@*

# ��̤�̤������ä��Ȥ����֤���������ʸ���󡣾�ά������ undef ��
-undef: (̤���)

# ����˷׻��Ǥ����Ȥ��Υե����ޥå�
# method: �׻���, result: ���, error: ���顼, signal: �����ʥ�
reply-format: #(method): #(result)

# ���顼���������Ȥ��Υե����ޥå�
# method: �׻���, result: ���, error: ���顼, signal: �����ʥ�
error-format: #(method): ���顼�Ǥ���(#(error))

# �����ʥ뤬ȯ�������Ȥ��Υե����ޥå�
-signal-format: #(method): �����ʥ�Ǥ���(#(signal))

# signal-$SIGNALNAME-format ������
# $SIGNALNAME �ˤϸ��� alarm/sigfpe ������ޤ���
# �������ʤ���� signal-format �˥ե�����Хå����ޤ���

# �����Ĥ������󤲤ޤ���
-signal-alarm-format: #(method): �����ڤ�Ǥ���
-signal-sigfpe-format: #(method): ��ư�������׻��㳰�Ǥ���

# �����ॢ���Ȥ����ÿ�����ꤷ�ޤ��� alarm ���Ϥ���ޤ���
# �Ƶ���ߤ��Τ˻Ȥ��ޤ������ɤ������꡼�����Ƥ�������ʷ�ϵ��Ǥ���
timeout: 1

# ���֥롼�����������Ĥ��뤫�ɤ�������ꤹ�롣
# �Ƶ��������ǽ�ʤΤǡ����Ĥ�����Ϥ��Υ⥸�塼�����Ѥ�
# Tiarra ��ư�������Ȥ򤪴��ᤷ�ޤ���
permit-sub: 0

# ���������ȯ������ꤷ�ޤ���
# ���Υ⥸�塼��Ǥϸ����ѿ���ؿ�����ʤɤ�Ԥ��ޤ���
# ���Υ��ޥ�ɤ�ȯ�Ԥ����Ȥ����򥯥ꥢ���ޤ���
init: �׻������

# ���������Ĥ����&�����ͥ�Υޥ�����
# ���Tiarra�⡼�ɻ��� [default: �ʤ�]
init-mask: * +*!*@*
# [plum-mode] mask: +*!*@*

# �ƽ���������Ȥ���ȯ������ꤷ�ޤ���
init-format: ��������ޤ�����

=cut
