# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Channel::Mode::Oper::Grant;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use IRCMessage;
use Timer;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{queue} = {}; # network name => [[IrcIO::Server,channel(short),nick]]
    $this->{timer} = undef; # queueが空でない時だけ必要になるTimer
    $this;
}

sub destruct {
    my ($this) = @_;
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
    }
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    # 先に進むための条件:
    # 1. サーバーからのメッセージである
    # 2. コマンドはJOINである
    # 3. 自分のJOINではない
    # 4. @付きのJOINではない
    # 5. そのチャンネルで自分は@を持っている
    # 6. 相手はmaskに一致する
    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'JOIN' &&
	defined $msg->nick &&
	$msg->nick ne RunLoop->shared->current_nick) {
	foreach (split /,/,$msg->param(0)) {
	    my ($ch_full,$mode) = (m/^(.+?)(?:\x07(.*))?$/);
	    my $ch_short = Multicast::detatch($ch_full);
	    my $ch = $sender->channel($ch_short);
	    my $myself = $ch->names($sender->current_nick);
	    if (defined $myself && $myself->has_o && (!defined $mode || $mode !~ /o/)) {
		if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix,$ch_full)) {
		    # waitで指定された秒数の経過後に、キューに入れる。
		    # 同時にキュー消化タイマーを準備する。
		    $this->push_to_queue($sender,$ch_short,$msg->nick);
		}
	    }
	}
    }
    $msg;
}

sub push_to_queue {
    my ($this,$server,$ch_short,$nick) = @_;
    Timer->new(
	After => $this->config->wait || 0,
	Code => sub {
	    # 対象の人が既に+oされていたら中止。
	    my $ch = $server->channel($ch_short);
	    return if !defined $ch;
	    my $target = $ch->names($nick);
	    return if !defined $target;
	    return if $target->has_o;
	    
	    my $queue = $this->{queue}->{$server->network_name};
	    if (!defined $queue) {
		$queue = $this->{queue}->{$server->network_name} = [];
	    }
	    push @$queue,[$server,$ch_short,$nick];
	    $this->prepare_timer;
	})->install;
}

sub prepare_timer {
    my ($this) = @_;
    # キュー消化タイマーが存在しなければ作る
    if (!defined $this->{timer}) {
	$this->{timer} = Timer->new(
	    Interval => 0, # 勿論、最初のtriggerで変更する。
	    Repeat => 1,
	    Code => sub {
		my ($timer) = @_;
		$timer->interval(1);
		
		# 鯖毎に3つずつ消化する。
		# チャンネル毎に最大３つずつ纏める。
		my $queue_has_elem;
		foreach my $queue (values %{$this->{queue}}) {
		    my $channels = {}; # ch_shortname => [nick,nick,...]
		    for (my $i = 0; $i < @$queue && $i < 3; $i++) {
			my $elem = $queue->[$i];
			my $nicks = $channels->{$elem->[1]};
			if (!defined $nicks) {
			    $nicks = $channels->{$elem->[1]} = [];
			}
			push @$nicks,$elem->[2];
		    }
		    while (my ($ch_short,$nicks) = each %$channels) {
			$queue->[0]->[0]->send_message(
			    IRCMessage->new(
				Command => 'MODE',
				Params => [$ch_short,
					   '+'.('o' x @$nicks),
					   @$nicks]));
		    }
		    splice @$queue,0,3;
		    # キューが空でなければ$queue_has_elemに1を入れる。
		    if (@$queue > 0) {
			$queue_has_elem = 1;
		    }
		}

		# 全てのキューが空になったら終了。
		if (!$queue_has_elem) {
		    $timer->uninstall;
		    $this->{timer} = undef;
		}
	    })->install;
    }
}

1;

=pod
info: 特定のチャンネルに特定の人間がjoinした時に、自分がチャンネルオペレータ権限を持っていれば+oする。
default: off

# splitからの復帰などで+o対象の人が一度に大量に入って来ても+oは少しずつ実行します。
# Excess Floodにはならない筈ですが、本格的な防衛BOTに使える程の物ではありません。

# 対象の人間がjoinしてから実際に+oするまで何秒待つか。
# 省略されたら待ちません。
wait: 0

# チャンネルと人間のマスクを定義。Auto::Operと同様。
-mask: * example!~example@*.example.ne.jp
=cut
