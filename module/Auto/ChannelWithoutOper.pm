# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::ChannelWithoutOper;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use IRCMessage;

sub new {
    my ($class) = @_;
    my $this = $class->SUPER::new;
    $this->{last_message_time} = 0; # 最後にこのモジュールが発言した時刻。
    $this->{table} = do {
	my %hash = map {
	    my ($ch_long,$msg) = m/^(.+?)\s+(.+)$/;
	    $ch_long => $msg;
	} $this->config->channel('all');
	\%hash;
    };
    $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my $notify = sub {
	my ($ch_long,$ch_short,$str) = @_;
	my $msg_to_send = IRCMessage->new(
	    Command => 'NOTICE',
	    Params => ['',$str]); # チャンネル名は後で設定
	# 鯖にはネットワーク名を付けない。
	my $for_server = $msg_to_send->clone;
	$for_server->param(0,$ch_short);
	$sender->send_message($for_server);

	# クライアントには付ける。Prefixも自動設定する。
	my $for_client = $msg_to_send->clone;
	$for_client->param(0,$ch_long);
	$for_client->remark('fill-prefix-when-sending-to-client',1);
	push @result,$for_client;
    };
    
    if ($sender->isa('IrcIO::Server') &&
	defined $msg->nick &&
	$msg->nick ne RunLoop->shared->current_nick &&
	$msg->command eq 'JOIN') {

	foreach (split /,/,$msg->param(0)) {
	    my ($ch_long) = m/^([^\x07]+)/;
	    # このチャンネルに割り当てられたメッセージはあるか？
	    my $msg_for_ch = $this->{table}->{$ch_long};
	    if (defined $msg_for_ch) {
		my $ch_short = Multicast::detach($ch_long);
		my $ch = $sender->channel($ch_short);
		# このチャンネルは+チャンネルでもなく、+aや+rが設定されていないか？
		if (defined $ch &&
		    $ch->name !~ m/^\+/ &&
		    !$ch->switches('a') &&
		    !$ch->switches('r')) {
		    
		    # なるとを誰か持っているか？
		    my $oper_exists;
		    foreach my $person (values %{$ch->names}) {
			if ($person->has_o) {
			    $oper_exists = 1;
			}
		    }
		    if (!$oper_exists) {
			# 発言してから1秒以上経っていれば、発言。
			if (time > $this->{last_message_time} + 1) {
			    $notify->($ch_long,$ch_short,$msg_for_ch);
			    $this->{last_message_time} = time;
			}
		    }
		}
	    }
	}
    }
    @result;
}

1;

=pod
info: チャンネルオペレータ権限がなくなってしまったときに発言する。
default: off

# +で始まらない特定のチャンネルで、+aモードでも+rモードでもないのに
# 誰もチャンネルオペレータ権限を持っていない状態になっている時、
# そこに誰かがJOINする度に特定のメッセージを発言するモジュールです。

# 書式: <チャンネル名> <メッセージ>
-channel: #IRC談話室@ircnet なると消失しました。
=cut
