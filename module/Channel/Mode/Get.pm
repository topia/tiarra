# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Channel::Mode::Get;
use strict;
use warnings;
use base qw(Module);
use Multicast;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{buffer} = []; # [IrcIO::Server,IRCMessage]
    $this->{timer} = undef; # Timer：必要な時だけ使われる。
    $this;
}

sub destruct {
    my $this = shift;
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
    }
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    
    if ($sender->isa('IrcIO::Server') &&
	    $msg->command eq 'JOIN' &&
	    defined $msg->nick &&
	    $msg->nick eq RunLoop->shared->current_nick) {
	# 自分のJOINなので、MODE #channelを発行
	foreach (split /,/,$msg->param(0)) {
	    my $ch_shortname = Multicast::detatch($_);
	    my $entry = [$sender,
			 IRCMessage->new(
			     Command => 'MODE',
			     Param => $ch_shortname)];
	    push @{$this->{buffer}},$entry;
	    $this->setup_timer;
	}
    }
    
    $msg;
}

sub setup_timer {
    my ($this) = @_;
    # 既にタイマーが作られていたら何もせずに戻る。
    if (!defined $this->{timer}) {
	$this->{timer} = Timer->new(
	    Interval => 1,
	    Repeat => 1,
	    Code => sub {
		my $timer = shift;
		# 一度に二つずつ送り出す。
		my $msg_per_once = 2;
		my $buffer = $this->{buffer};
		for (my $i = 0;
		     $i < @$buffer && $i < $msg_per_once;
		     $i++) {
		    my $entry = $buffer->[$i];
		    $entry->[0]->send_message($entry->[1]);
		}
		splice @$buffer,0,2;
		# バッファが空になったら終了。
		if (@$buffer == 0) {
		    $timer->uninstall;
		    $this->{timer} = undef;
		}
	    })->install;
    }
}

1;

=pod
info: チャンネルにJOINした時、そのチャンネルのモードを取得します。
default: off

# Channel::Mode::Set等が正しく動くためには
# チャンネルのモードをTiarraが把握しておく必要があります。
# 自動的にモードを取得するクライアントであれば必要ありませんが、
# そうでなければこのモジュールを使うべきです。

# 設定項目は無し。
=cut
