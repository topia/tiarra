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
use base qw(Tiarra::IRC::NewMessageMixin);

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
    if (!UNIVERSAL::isa($msg, __PACKAGE__->irc_message_class)) {
	croak "CTCP::extract, Arg[0] is bad ref: ".ref($msg)."\n";
    }

    if ($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE') {
	__PACKAGE__->extract_from_text($msg->param(1));
    }
}

sub make {
    # CTCP��å�������ޤ�Tiarra::IRC::Message���ä��֤���
    #
    # $message: �ޤ��CTCP��å�����
    # $target : ���Tiarra::IRC::Message�κǽ�Υѥ�᡼����nick������ͥ�̾������롣
    # $command: PRIVMSG��NOTICE�Τ������ɤ���Υ��ޥ�ɤǺ�뤫����ά���줿����NOTICE�ˤʤ롣
    my ($message,$target,$command) = @_;

    if (!defined $target) {
	croak "CTCP::make, Arg[1] is undef.\n";
    }
    if (!defined $command) {
	$command = 'NOTICE';
    }

    my $result = __PACKAGE__->construct_irc_message(
	Command => $command,
	Params => [$target,
		   __PACKAGE__->make_text($message),
		  ]);

    $result;
}

sub _low_level_dequote {
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
}

sub _ctcp_level_dequote {
    my ($symbol) = @_;

    if ($symbol eq 'a') {
	return "\x01";
    } elsif ($symbol eq "\x5c") {
	return "\x5c";
    } else {
	# error, but return.
	return $symbol;
    }
}

sub dequote {
    shift; # drop
    local $_ = shift;

    # 2nd Level
    s/\x10(.)/_low_level_dequote($1)/eg;

    # 1st Level
    s/\x5c(.)/_ctcp_level_dequote($1)/eg;

    $_;
}

sub extract_from_text {
    my $this = shift;
    grep {
	if (!wantarray) {
	    return $_;
	}
	1;
    } map {
	$this->dequote($1);
    } (shift =~ m/\x01(.*)\x01/g);
}

sub quote {
    shift; # drop
    local $_ = shift;
    # 1st Level
    s/\x5c/\x5c\x5c/g;
    s/\x01/\x5ca/g;

    # 2nd Level
    s/\x10/\x10\x10/g;
    s/\x00/\x100/g;
    s/\x0a/\x10n/g;
    s/\x0d/\x10r/g;

    $_;
}

sub make_text {
    my $this = shift;
    my @ctcps = map {
	"\x01" . $this->quote($_) . "x01";
    } @_;
    return wantarray ? @ctcps : join('', @ctcps);
}

1;
