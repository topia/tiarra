# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::Rehash;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use NumericReply;
use Timer;

my $timer_name = __PACKAGE__.'/timer';

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
}

sub destruct {
    my ($this) = shift;

    # timer があれば解除
    foreach my $client (RunLoop->shared_loop->clients_list) {
	my $timer = $client->remark($timer_name);
	if (defined $timer) {
	    $client->remark($timer_name, undef, 'delete');
	    $timer->uninstall;
	}
    }
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    # クライアントからのメッセージか？
    if ($sender->isa('IrcIO::Client')) {
	my $runloop = RunLoop->shared_loop;
	# 指定されたコマンドか?
	if (Mask::match_deep([$this->config->command_nick('all')], $msg->command)) {
	    if (!defined $msg->param(0)) {
	    } elsif ($msg->param(0) eq $runloop->current_nick) {
	    } else {
		$sender->send_message(
		    IRCMessage->new(
			Prefix => $msg->param(0).'!'.$sender->username.'@'.
			    $sender->client_host,
			Command => 'NICK',
			Param => $runloop->current_nick,
		       ));

	    }
	    # ここで消す。
	    return undef;
	} elsif (Mask::match_deep([$this->config->command_names('all')], $msg->command)) {
	    my @channels = map {
		my $network_name = $_->network_name;
		map {
		    [$network_name, $_->name];
		} $_->channels_list;
	    } $runloop->networks_list;
	    $sender->remark($timer_name, Timer->new(
	       Interval => (defined $this->config->interval ?
				$this->config->interval : 2),
	       Repeat => 1,
	       Code => sub {
		   my $timer = shift;
		   my $runloop = RunLoop->shared_loop;
		   while (1) {
		       my $entry = shift(@channels);
		       if (defined $entry && $sender->connected) {
			   my ($network_name, $ch_name) = @$entry;
			   my $network = $runloop->network($network_name);
			   my $flush_namreply = sub {
			       my $msg = shift;
			       $msg->param(0, $runloop->current_nick);
			       $sender->send_message($msg);
			   };
			   if (!defined $network) {
			       # network disconnected. ignore
			       next;
			   }
			   my $ch = $network->channel($ch_name);
			   if (!defined $ch) {
			       # parted channel; ignore
			       next;
			   }
			   $sender->do_namreply($ch, $network,
						undef, $flush_namreply);
		       } else {
			   $sender->remark($timer_name, undef, 'delete');
			   $timer->uninstall;
		       }
		       last;
		   }
	       },
	      )->install);

	    # ここで消す。
	    return undef;
	}
    }

    return $msg;
}

1;
=pod
info: 全チャンネル分の names の内部キャッシュをクライアントに送信する。
default: off

# もともとはクライアントの再初期化目的に作ったのですが、 names を送信しても
# 更新されないクライアントが多いので、主に multi-server-mode な Tiarra の
# 下にさらに Tiarra をつないでいる人向けにします。

# names でニックリストを更新してくれるクライアント:
#   Tiarra
# してくれないクライアント: (括弧内は確認したバージョンまたは注釈)
#   LimeChat(1.18)

# nick rehash に使うコマンドを指定します。
# 第二パラメータとして現在クライアントが認識している nick を指定してください。
command-nick: rehash-nick

# names rehash に使うコマンドを指定します。
command-names: rehash-names

# チャンネルとチャンネルの間のウェイトを指定します。
interval: 2
=cut
