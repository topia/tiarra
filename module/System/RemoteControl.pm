# -----------------------------------------------------------------------------
# $Id: RemoteControl.pm,v 1.2 2003/02/17 08:16:53 topia Exp $
# -----------------------------------------------------------------------------
package System::RemoteControl;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	Mask::match_deep([defined($this->config->mask) ? $this->config->mask('all') : '*!*@*'],
			 $msg->prefix)) {

	my ($nick,$cmd) = $msg->param(1) =~ m/^\+\s+(.+?)\s+(.+)$/;
	# 指定されたnickに自分はマッチするか？
	if (Mask::match($nick,$sender->current_nick) &&
	    defined $cmd) {
	    # 実行。
	    $sender->send_message(
		IRCMessage->new(
		    Line => $cmd,
		    Encoding => 'utf8'));
	}
    }
    $msg;
}

1;

=pod
info: 特定の発言が送られてきたとき、それに反応してIRCコマンドを実行します。
default: off

# 実行を許可する人間を表すマスク。
-mask: *!*example@example.net

# 構文: + <nick> <IRC Message>
# <nick>は反応するbotのnickを表すマスク。
# <IRCMessage>はサーバーに向けて発行するIRCメッセージ。
#
# 例:
# + hoge NICK [hoge]
# hogeというBOTが[hoge]にnickを変更する。
=cut
