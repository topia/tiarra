# -----------------------------------------------------------------------------
# $Id: Eval.pm,v 1.1 2004/02/14 11:48:20 topia Exp $
# -----------------------------------------------------------------------------
package Client::Eval;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Data::Dumper;
use Configuration;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # クライアントからのメッセージか？
    if ($sender->isa('IrcIO::Client')) {
	# 指定されたコマンドか?
	if (Mask::match_deep([$this->config->command('all')], $msg->command)) {
	    my ($method) = $msg->param(0);
	    my ($ret, $err);
	    do {
		# disable warning
		local $SIG{__WARN__} = sub { };
		# die handler
		local $SIG{__DIE__} = sub { $err = $_[0]; };
		no strict;
		$ret = eval($method);
	    };

	    my $message = IRCMessage->new(
		Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [RunLoop->shared_loop->current_nick,
			   ''],
	       );
	    do {
		local($Data::Dumper::Terse) = 1;
		map {
		    my $new = $message->clone;
		    $new->param(1, $_);
		    $sender->send_message($new);
		} (
		    'method: '.Dumper($method),
		    'result: '.Dumper($ret),
		    'error: '.$err,
		   );
		return undef;
	    };
	}
    }

    return $msg;
}

1;
=pod
info: クライアントから Perl 式を実行できるようにする。
default: off

# eval を実行するコマンド名。省略されるとコマンドを追加しません。
# この時コマンドはTiarraが握り潰すので、IRCプロトコル上で定義された
# コマンド名を設定すべきではありません。
command: eval
=cut
