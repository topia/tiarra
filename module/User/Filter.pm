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
