# -----------------------------------------------------------------------------
# $Id: Filter.pm,v 1.1 2003/03/23 07:44:50 admin Exp $
# -----------------------------------------------------------------------------
package User::Filter;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE')) {
	# マッチするパターンを探す
	foreach ($this->config->pattern('all')) {
	    my ($user,$replace) = m/^(.+?)\s+(.+)$/;
	    if (Mask::match($user,$msg->prefix)) {
		# 一致した。
		$replace =~ s/#\(message\)/$msg->param(1)/eg;
		$msg->param(1,$replace);
		last;
	    }
	}
    }

    $msg;
}

1;

=pod
info: 指定された人物からのPRIVMSGやNOTICEを書き換える。
default: off

# 人物のマスクと、置換パターンを定義。
# 置換パターン中の#(message)は、発言内容に置換されます。
# 人物が複数のマスクに一致する場合は、最初に一致したものが使われます。
pattern: *!*@* #(message)
=cut
