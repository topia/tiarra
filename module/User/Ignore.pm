# -----------------------------------------------------------------------------
# $Id: Ignore.pm,v 1.3 2003/08/04 09:29:20 admin Exp $
# -----------------------------------------------------------------------------
package User::Ignore;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    
    # 鯖からクライアントへ向かうメッセージか？
    if ($sender->isa('IrcIO::Server')) {
	# 対象となるコマンドか？
	if (Mask::match(
		$this->config->command,
		$msg->command)) {
	    # 全てのmaskをカンマで繋げてマッチングを行なう。
	    if (Mask::match(
		    join(',',$this->config->mask('all')),
		    $msg->prefix || '')) {
		# 最終的にマッチしたので、このメッセージは捨てる。
		return undef;
	    }
	}
    }
    return $msg;
}

1;
=pod
info: 指定された人間からのPRIVMSGやNOTICEを破棄してクライアントへ送らないようにするモジュール。
default: off

# 対象となるコマンドのマスク。省略時には"privmsg,notice"が設定されている。
# ただしprivmsgとnotice以外を破棄してしまうと、(Tiarraは平気でも)クライアントが混乱する。
command: privmsg,notice

# maskは複数定義可能。定義された順番でマッチングが行なわれます。
mask: example!*@*.example.net
=cut
