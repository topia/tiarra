# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IRCMessage中からCTCPメッセージを取り出したり、CTCPメッセージを持つIRCMessageを作ったり。
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
    # PRIVMSGかNOTICEであるIRCMessageにCTCPメッセージが埋め込まれていたら、それを取り出して返す。
    # '\x01CTCP VERSION\x01\x01CTCP USERINFO\x01'のように一つのメッセージ中に複数のCTCPメッセージが含まれていた場合は、
    # スカラーコンテクストなら最初に見付かったものだけを返し、配列コンテクストなら見付かったもの全てを返す。
    # CTCPメッセージを取り出せなかった場合は、undef(スカラー)または空配列(配列)を返す。
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
    # CTCPメッセージを含むTiarra::IRC::Messageを作って返す。
    #
    # $message: 含めるCTCPメッセージ
    # $target : 作るTiarra::IRC::Messageの最初のパラメータ。nickやチャンネル名を入れる。
    # $command: PRIVMSGとNOTICEのうち、どちらのコマンドで作るか。省略された場合はNOTICEになる。
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
