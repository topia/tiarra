# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IRCMessage�椫��CTCP��å���������Ф����ꡢCTCP��å����������IRCMessage���ä��ꡣ
# -----------------------------------------------------------------------------
package CTCP;
use strict;
use warnings;
use Carp;
use UNIVERSAL;
use IRCMessage;

use SelfLoader;
1;
__DATA__

sub extract {
    # PRIVMSG��NOTICE�Ǥ���IRCMessage��CTCP��å������������ޤ�Ƥ����顢�������Ф����֤���
    # '\x01CTCP VERSION\x01\x01CTCP USERINFO\x01'�Τ褦�˰�ĤΥ�å��������ʣ����CTCP��å��������ޤޤ�Ƥ������ϡ�
    # �����顼����ƥ����Ȥʤ�ǽ�˸��դ��ä���Τ������֤������󥳥�ƥ����Ȥʤ鸫�դ��ä�������Ƥ��֤���
    # CTCP��å���������Ф��ʤ��ä����ϡ�undef(�����顼)�ޤ��϶�����(����)���֤���
    my $msg = shift;

    if (!defined $msg) {
	croak "CTCP::extract, Arg[0] is undef.\n";
    }
    if (!UNIVERSAL::isa($msg,'IRCMessage')) {
	croak "CTCP::extract, Arg[0] is bad ref: ".ref($msg)."\n";
    }

    my $low_level_dequote = sub {
	my ($symbol) = @_;

	if ($symbol eq '0') {
	    return "\x00";
	} elsif ($symbol eq 'n') {
	    return "\x0a";
	} elsif ($symbol eq 'r') {
	    return "\x0d";
	} elsif ($symbol eq "\x10") {
	    return "\x10";
	} else {
	    # error, but return.
	    return $symbol;
	}
    };

    my $ctcp_level_dequote = sub {
	my ($symbol) = @_;

	if ($symbol eq 'a') {
	    return "\x01";
	} elsif ($symbol eq "\x5c") {
	    return "\x5c";
	} else {
	    # error, but return.
	    return $symbol;
	}
    };

    my @result;
    if ($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE') {
	@result = map {
	    # 2nd Level
	    s/\x10(.)/$low_level_dequote->($1)/eg;

	    # 1st Level
	    s/\x5c(.)/$ctcp_level_dequote->($1)/eg;

	    $_;
	} ($msg->param(1) =~ m/\x01(.*)\x01/g);
    }

    if (wantarray) {
	@result;
    }
    else {
	$result[0];
    }
}

sub make {
    # CTCP��å�������ޤ�IRCMessage���ä��֤���
    #
    # $message: �ޤ��CTCP��å�����
    # $target : ���IRCMessage�κǽ�Υѥ�᡼����nick������ͥ�̾������롣
    # $command: PRIVMSG��NOTICE�Τ������ɤ���Υ��ޥ�ɤǺ�뤫����ά���줿����NOTICE�ˤʤ롣
    my ($message,$target,$command) = @_;

    if (!defined $target) {
	croak "CTCP::make, Arg[1] is undef.\n";
    }
    if (!defined $command) {
	$command = 'NOTICE';
    }

    my $result = IRCMessage->new(
	Command => $command,
	Params => [$target,
		   do {
		       $_ = $message;

		       # 1st Level
		       s/\x5c/\x5c\x5c/g;
		       s/\x01/\x5ca/g;

		       # 2nd Level
		       s/\x10/\x10\x10/g;
		       s/\x00/\x100/g;
		       s/\x0a/\x10n/g;
		       s/\x0d/\x10r/g;

		       "\x01$_\x01";
		   }]);

    $result;
}

1;
