# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package System::PrivTranslator;
use strict;
use warnings;
use base qw(Module);
use Multicast;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server') &&
	defined $msg->nick) {

	my $cmd = $msg->command;
	if (($cmd eq 'PRIVMSG' || $cmd eq 'NOTICE') &&
	    Multicast::nick_p($msg->param(0))) {
	    
	    $msg->nick(
		Multicast::attach($msg->nick,$sender->network_name));
	}
    }
    $msg;
}

1;
=pod
info: クライアントからの個人的なprivが相手に届かなくなる現象を回避する。
default: off

# このモジュールは個人宛てのprivmsgの送信者のnickにネットワーク名を付加します。
# 設定項目はありません。
=cut
