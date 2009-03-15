# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# emulate single-server-mode for client only
# -----------------------------------------------------------------------------
# copyright (C) 2009 Topia <topia@clovery.jp>. all rights reserved.
package Client::SingleServer;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use NumericReply;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);

    ## FIXME: please implement switching multi-server-mode on loading
    ## FIXME: and handle module reloading

    return $this;
}

sub destruct {
    my $this = shift;

    ## FIXME: please implement switching multi-server-mode on unloading
    ## FIXME: and handle module reloading
}

sub config_reload {
    my ($this, $old_config) = @_;
    # モジュールの設定が変更された時に呼ばれる。
    # 新しい config は $this->config で取得できます。

    ## FIXME: handle config reloading
}

## client-attached よりも先に message_io_hook が呼ばれる。
## (inform_joinning_channels とか)

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server') && $msg->command eq 'NICK') {
	my $network_name = $sender->network_name;
	foreach my $client ($this->_runloop->clients_list) {
	    my $optval = $client->option('server-only');
	    if (defined $optval && $network_name eq $optval) {
		$client->send_message($msg);
	    }
	}
    }
    return $msg;
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;
    return $msg unless $io->isa('IrcIO::Client');
    my $optval = $io->option('server-only');
    if (defined $optval) {
	my @forwards;
	local $Multicast::hijack_forward_to_server = sub {
	    my ($msg, $network_name) = @_;
	    if ($network_name eq $optval) {
		push(@forwards, $msg);
	    }
	};
	# local_to_global は乗っ取らない
	## FIXME: NICK 系のメッセージは既に握りつぶされているはず
	my $network = $this->_runloop->network($optval);
	my $command = $msg->command;
	if (defined $network) {
	    if ($type eq 'out') {
		## server -> runloop -> client
		my $generator = $msg->generator;
		if (defined $generator) {
		    if ($generator->isa('IrcIO::Server')) {
			return undef unless $generator == $network;
			Multicast::from_client_to_server($msg->clone, $generator);
			return @forwards;
		    }
		}
		if ($command eq 'NICK') {
		    ## NICK from runloop
		    return undef;
		}
		Multicast::from_client_to_server($msg->clone, $network);
		return @forwards;
	    } else {
		## client -> runloop -> server
		if ($command eq 'NICK') {
		    $msg = $msg->clone;
		    $msg->params->[0] = Multicast::attach($msg->params->[0], $optval);
		    return $msg;
		} else {
		    return Multicast::from_server_to_client($msg->clone, $network);
		}
	    }
	} else {
	    # 指定されたネットワークが存在していないときは切る。
	    $io->send_message(
		$this->construct_irc_message(
		    Command => 'ERROR',
		    Param => 'Closing Link: ['.$this->fullname_from_client.'] ('.
			'Specified network not found: '.$optval.')'));
	    $this->disconnect_after_writing;
	    return undef;
	}
    }
    return $msg;
}


sub client_attached {
    my ($this,$client) = @_;

    my $optval = $client->option('server-only');
    if (defined $optval) {
	my $network = $this->_runloop->network($optval);
	if (defined $network) {
	    my $nick = $network->current_nick;
	    my $prefix = $this->_runloop->sysmsg_prefix(qw(priv nick::system));
	    $client->send_message(
		$this->construct_irc_message(
		    Prefix => $prefix,
		    Command => 'NOTICE',
		    Params => [
			$nick,
			"*** This client send/receive '".$optval."' network's conversation only."]));
	}
    }
}


1;

=begin tiarra-doc

info:    指定したクライアントのためにシングルサーバモードをエミュレーションする
default: off
section: experimental

# このモジュールは実験的なモジュールです。
# 本番環境に適用する前には、動作について十分に確認してください。

# 使用する client option は server-only=network name の形式で指定してください。

# realname (クライアントにより 名前 / 名前の説明 などになっている場合もあり) に
# $server-only=ircnet$ などと指定すれば動作するかと思います。

# 設定されたクライアントを接続している最中にモジュールのロード・アンロードを
# 行った場合の動作は未定義です。
# かならずクライアントを切断してから切り替えてください。
# また、アップデート等で本モジュールの更新を行う際にもクライアントの切断を推奨します。

=end tiarra-doc

=cut
