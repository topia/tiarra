# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IrcIO::ServerはIRCサーバーに接続し、IRCメッセージをやり取りするクラスです。
# このクラスはサーバーからメッセージを受け取ってチャンネル情報や現在のnickなどを保持しますが、
# 受け取ったメッセージをモジュールに通したり各クライアントに転送したりはしません。
# それはRunLoopの役目です。
# -----------------------------------------------------------------------------
package IrcIO::Server;
use strict;
use warnings;
use IrcIO;
use base qw(IrcIO);
use Carp;
use ChannelInfo;
use PersonalInfo;
use PersonInChannel;
use UNIVERSAL;
use Multicast;
use NumericReply;
use Tiarra::Utils;
use Tiarra::Socket::Connect;
use Tiarra::Resolver;
use base qw(Tiarra::Utils);
__PACKAGE__->define_attr_getter(0,
				qw(network_name current_nick logged_in),
				qw(server_hostname isupport config),
				[qw(host server_host)]);
__PACKAGE__->define_attr_accessor(0, qw(state finalizing));
__PACKAGE__->define_attr_enum_accessor('state', 'eq',
				       qw(connecting finalizing terminating),
				       qw(terminated finalized connected),
				       qw(reconnecting));


sub new {
    my ($class,$runloop,$network_name) = @_;
    my $this = $class->SUPER::new(
	$runloop,
	name => "network/$network_name");
    $this->{network_name} = $network_name;
    $this->{current_nick} = ''; # 現在使用中のnick。ログインしていなければ空。
    $this->{server_hostname} = ''; # サーバが主張している hostname。こちらもログインしてなければ空。

    $this->{logged_in} = 0; # このサーバーへのログインに成功しているかどうか。
    $this->{new_connection} = 1;

    $this->{receiving_namreply} = {}; # RPL_NAMREPLYを受け取ると<チャンネル名,1>になり、RPL_ENDOFNAMESを受け取るとそのチャンネルの要素が消える。
    $this->{receiving_banlist} = {}; # 同上。RPL_BANLIST
    $this->{receiving_exceptlist} = {}; # 同上。RPL_EXCEPTLIST
    $this->{receiving_invitelist} = {}; # 同上、RPL_INVITELIST

    $this->{channels} = {}; # 小文字チャンネル名 => ChannelInfo
    $this->{people} = {}; # nick => PersonalInfo
    $this->{isupport} = {}; # isupport

    $this->{connecting} = undef;
    $this->{finalizing} = undef;
    $this->state('initializing');

    $this->reconnect;
}

sub connecting { defined shift->{connecting}; }

sub _connect_interrupted {
    my $this = shift;
    $this->state_terminating || $this->state_finalizing ||
	$this->state_terminated || $this->state_finalized;
}

sub _gen_msg {
    my ($this, $msg) = @_;

    $this->name.': '.$msg;
}

sub die {
    my ($this, $msg) = @_;
    CORE::die($this->_gen_msg($msg));
}

sub warn {
    my ($this, $msg) = @_;
    CORE::warn($this->_gen_msg($msg));
}

sub printmsg {
    my ($this, $msg) = @_;

#    if (defined $this->{last_msg} &&
#	    $this->{last_msg}->[0] eq $msg &&
#		$this->{last_msg}->[1] <= (time - 10)) {
#	# repeated
#	return
#    }
#    $this->{last_msg} = [$msg, time];
    ::printmsg($this->_gen_msg($msg));
}

sub nick_p {
    my ($this, $nick) = @_;

    Multicast::nick_p($nick, $this->isupport->{NICKLEN});
}

sub channel_p {
    my ($this, $name) = @_;

    Multicast::channel_p($name, $this->isupport->{CHANTYPES});
}

sub channels {
    # {小文字チャンネル名 => ChannelInfo}のハッシュリファを返す。
    # @options(省略可能):
    #   'even-if-kicked-out': 既に自分が蹴り出されてゐるチャンネルも返す。この動作は高速である。
    my ($this, @options) = @_;
    if (defined $options[0] && $options[0] eq 'even-if-kicked-out') {
	$this->{channels};
    }
    else {
	# kicked-outフラグが立つてゐないチャンネルのみ返す。
	my %result;
	while (my ($name, $ch) = each %{$this->{channels}}) {
	    if (!$ch->remark('kicked-out')) {
		$result{$name} = $ch;
	    }
	}
	\%result;
    }
}

sub channels_list {
    # @options(省略可能):
    #   'even-if-kicked-out': 既に自分が蹴り出されてゐるチャンネルも返す。この動作は高速である。
    my ($this, @options) = @_;
    if (defined $options[0] && $options[0] eq 'even-if-kicked-out') {
	values %{$this->{channels}};
    }
    else {
	# kicked-outフラグが立つてゐないチャンネルのみ返す。
	grep {
	    !$_->remarks('kicked-out');
	} values %{$this->{channels}};
    }
}

sub person_list {
    values %{shift->{people}};
}

sub fullname {
    $_[0]->{current_nick}.'!'.$_[0]->{user_shortname}.'@'.$_[0]->{server_host};
}

sub config_or_default {
    my ($this, $base, $general_prefix, $local_prefix, $default) = @_;

    foreach ([$this->config, $local_prefix],
	     [$this->_conf_general, $general_prefix]) {
	my ($conf, $prefix) = @$_;
	$prefix = '' unless defined $prefix;
	my $value = $conf->get("$prefix$base");
	if (defined $value) {
	    return $value;
	}
    }
    return $default;
}

sub reload_config {
    my $this = shift;
    my $conf = $this->{config} = $this->_conf->get($this->{network_name});
    $this->{server_host} = $conf->host;
    $this->{server_port} = $conf->port;
    $this->{server_password} = $conf->password;
    $this->{initial_nick} = $this->config_or_default('nick'); # ログイン時に設定するnick。
    $this->{user_shortname} = $this->config_or_default('user');
    $this->{user_realname} = $this->config_or_default('name');
    $this->{prefer_socket_types} = [qw(ipv6 ipv4)];
}

sub destination {
    my $this = shift;
    Tiarra::Socket->repr_destination(
	host => $this->{server_host},
	addr => $this->{server_addr},
	port => $this->{server_port},
	type => $this->{proto});
}

sub person_if_exists {
    my ($this, $nick) = @_;
    $this->{people}{$nick};
}

sub person {
    # nick以外は全て省略可能。
    # 未知のnickが指定された場合は新規に追加する。
    my ($this,$nick,$username,$userhost,$realname,$server) = @_;
    return if !defined $nick;

    my $info = $this->{people}->{$nick};
    if (!defined($info)) {
	$info = $this->{people}->{$nick} =
	    new PersonalInfo(Nick => $nick,
			     UserName => $username,
			     UserHost => $userhost,
			     RealName => $realname,
			     Server => $server);
    }
    else {
	$info->username($username);
	$info->userhost($userhost);
	$info->realname($realname);
	$info->server($server);
    }
    $info;
}

sub channel {
    my $this = $_[0];
    my $channel_name = Multicast::lc($_[1]);
    $this->{channels}->{$channel_name};
}

sub _queue_retry {
    my $this = shift;

    $this->state_reconnecting(1);

    $this->_cleanup if defined $this->{timer};
    $this->{timer} = Timer->new(
	Name => $this->_gen_msg('retry timer'),
	After => 15,
	Code => sub {
	    $this->{timer} = undef;
	    $this->{connecting} = undef;
	    return if $this->finalizing;
	    $this->reconnect;
	})->install;
}

sub reconnect {
    my $this = shift;
    $this->reload_config;
    $this->connect;
}

sub connect {
    my $this = shift;
    #return if $this->connected;
    croak 'connected!' if $this->connected;
    croak 'connecting!' if $this->connecting;
    $this->finalizing(undef);

    # 初期化すべきフィールドを初期化
    $this->{nick_retry} = 0;
    $this->{logged_in} = undef;
    $this->state_connecting(1);
    my $conn_stat = $this->{connection_status} = {
	start => time,
	tried => [],
    };

    Tiarra::Resolver->resolve('addr', $this->{server_host}, sub {
				  $this->_connect_stage_1(@_);
			      });
    $this;
}

sub _connect_stage_1 {
    my ($this, $entry) = @_;

    my %addrs_by_types;
    my $server_port = $this->{server_port};

    return if $this->finalizing;

    if ($entry->answer_status eq $entry->ANSWER_OK) {
	foreach my $addr (@{$entry->answer_data}) {
	    if ($addr =~ m/^(?:\d+\.){3}\d+$/) {
		push (@{$addrs_by_types{ipv4}}, $addr);
	    } elsif ($addr =~ m/^[0-9a-fA-F:]+$/) {
		push (@{$addrs_by_types{ipv6}}, $addr);
	    } else {
		$this->die("unsupported addr type: $addr");
	    }
	}
    } else {
	$this->printmsg("Couldn't resolve hostname: $this->{server_host}");
	$this->_queue_retry;
	return;
    }

    foreach my $sock_type (@{$this->{prefer_socket_types}}) {
	my $struct;
	push (@{$this->{connection_queue}},
	      map {
		  $struct = {
		      type => $sock_type,
		      addr => $_,
		      host => $entry->query_data,
		      port => $server_port,
		  };
	      } @{$addrs_by_types{$sock_type}});
    }
    $this->_connect_try_next;
}

sub _connect_try_next {
    my $this = shift;

    return if $this->finalizing;
    my $trying =
	$this->{connecting} = shift @{$this->{connection_queue}};
    if (defined $trying) {
	my $methodname = '_try_connect_' . $this->{connecting}->{type};
	$this->$methodname($trying);
    } else {
	$this->printmsg("Couldn't connect to any host");
	$this->_queue_retry;
	return;
    }
}

sub _try_connect_ipv4 {
    my ($this, $conn_struct) = @_;

    my %additional;
    my $ipv4_bind_addr =
	$this->config_or_default('ipv4-bind-addr') ||
	    $this->config_or_default('bind-addr'); # 下は過去互換性の為に残す。
    if (defined $ipv4_bind_addr) {
	$additional{bind_addr} = $ipv4_bind_addr;
    }
    $this->_try_connect_socket($conn_struct, %additional);
}

sub _try_connect_ipv6 {
    my ($this, $conn_struct) = @_;

    my %additional;
    my $ipv6_bind_addr = $this->config_or_default('ipv6-bind-addr');
    if (defined $ipv6_bind_addr) {
	$additional{bind_addr} = $ipv6_bind_addr;
    }

    $this->_try_connect_socket($conn_struct, %additional);
}

sub _try_connect_socket {
    my ($this, $conn_struct, %additional) = @_;

    $this->{connector} = Tiarra::Socket::Connect->new(
	host => $conn_struct->{host},
	addr => $conn_struct->{addr},
	port => $conn_struct->{port},
	callback => sub {
	    my ($subject, $socket, $obj) = @_;

	    if ($subject eq 'sock') {
		$this->attach($socket);
	    } elsif ($subject eq 'error') {
		$this->_connect_error($obj);
	    } elsif ($subject eq 'warn') {
		$this->_connect_warn($obj);
	    }
	},
	%additional);
    $this;
}

sub attach {
    my ($this, $connector) = @_;

    $this->SUPER::attach($connector->sock);
    $this->{connecting} = undef;
    $this->{server_addr} = $connector->addr;
    $this->{proto} = $connector->type_name;
    $this->state_connected(1);

    $this->_send_connection_messages;

    $this->{connector} = undef;
    $this->printmsg("Opened connection to ". $this->destination .".");
    $this->install;
    $this;
}

sub _connect_error {
    my ($this, $msg) = @_;

    $this->printmsg("Couldn't connect to ".$this->destination.": $msg\n");
    $this->_connect_try_next;
}

sub _connect_warn {
    my ($this, $msg) = @_;

    $this->printmsg("** $msg\n");
}

sub _send_connection_messages {
    my $this = shift;
    # (PASS) -> NICK -> USERの順に送信し、中に入る。
    # NICKが成功したかどうかは接続後のreceiveメソッドが判断する。
    my $server_password = $this->{server_password};
    if (defined $server_password && $server_password ne '') {
	$this->send_message(new IRCMessage(
	    Command => 'PASS',
	    Param => $this->{server_password}));
    }
    if (!defined $this->{current_nick} || $this->{current_nick} eq '') {
	$this->{current_nick} = $this->{initial_nick};
    }
    $this->send_message(new IRCMessage(
	Command => 'NICK',
	Param => $this->{current_nick}));

    # +iなどの文字列からユーザーモード値を算出する。
    my $usermode = 0;
    if (my $usermode_str = $this->_conf_general->user_mode) {
	if ($usermode_str =~ /^\+/) {
	    foreach my $c (split //,substr($usermode_str,1)) {
		if ($c eq 'w') {
		    $usermode |= (1 << 2);
		}
		elsif ($c eq 'i') {
		    $usermode |= (1 << 3);
		}
	    }
	}
    }
    $this->send_message(new IRCMessage(
	Command => 'USER',
	Params => [$this->{user_shortname},
		   $usermode,
		   '*',
		   $this->{user_realname}]));
}

sub terminate {
    my ($this, $msg) = @_;

    $this->_interrupt($msg, 'terminating');
}

sub finalize {
    my ($this, $msg) = @_;

    $this->_interrupt($msg, 'finalizing');
    $this->finalizing(1);
}

sub _interrupt {
    my ($this, $msg, $state) = @_;

    if ($this->logged_in) {
	$this->state($state);
	$this->quit($msg);
    } elsif ($this->state_connecting || $this->state_reconnecting) {
	$this->state($state);
	$this->_cleanup;
    } else {
	if (!$this->state_connected) {
	    $this->warn('_interrupt/unexpected state: '.$this->state)
		if &::debug_mode;
	}
	$this->state($state);
	$this->disconnect;
    }
}

sub disconnect {
    my $this = shift;

    $this->_cleanup;
    $this->SUPER::disconnect;
    $this->printmsg("Disconnected from ".$this->destination.".");
    if ($this->state_reconnecting || $this->state_connected) {
	$this->state_reconnecting(1);
	$this->reload_config;
	$this->_queue_retry;
    }
    $this->{logged_in} = undef;
}

sub _cleanup {
    my ($this, $mode) = @_;

    if (defined $this->{connector}) {
	$this->{connector}->interrupt;
	$this->{connector} = undef;
    }
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }
    if ($this->state_terminating) {
	$this->state_terminated(1);
    } elsif ($this->state_finalizing) {
	$this->state_finalized(1);
    }
}

sub quit {
    my ($this, $msg) = @_;
    return $this->send_message(
	IRCMessage->new(
	    Command => 'QUIT',
	    Param => $msg));
}

sub send_message {
    my ($this,$msg) = @_;

    if (!defined $msg) {
	croak "IrcIO::Server->send_message, Arg[1] was undef.\n";
    }
    elsif (!ref($msg)) {
	croak "IrcIO::Server->send_message, Arg[1] was not ref.\n";
    }
    elsif (!UNIVERSAL::isa($msg, 'IRCMessage')) {
	croak "IrcIO::Server->send_message, Arg[1] was bad ref: ".ref($msg)."\n";
    }

    # 各モジュールへ通知
    #$this->_runloop->notify_modules('notification_of_message_io',$msg,$this,'out');

    $this->SUPER::send_message(
	$msg,
	$this->config_or_default('out-encoding', 'server-'));
}

sub read {
    my $this = shift;
    $this->SUPER::read($this->config_or_default('in-encoding', 'server-'));

    # 接続が切れたら、各モジュールとRunLoopへ通知
    if (!$this->connected) {
	$this->_runloop->notify_modules('disconnected_from_server',$this);
	$this->_runloop->disconnected_server($this);
    }
}

sub pop_queue {
    my ($this) = shift;
    my $msg = $this->SUPER::pop_queue;

    # このメソッドはログインしていなければログインするが、
    # パスワードが違うなどで何度やり直してもログイン出来る見込みが無ければ
    # 接続を切ってからdieします。
    if (defined $msg) {
	# ログイン作業中か？
	if ($this->logged_in) {
	    # ログイン作業中でない。
	    return $this->_receive_after_logged_in($msg);
	}
	else {
	    return $this->_receive_while_logging_in($msg);
	}
    }
    return $msg;
}

sub _receive_while_logging_in {
    my ($this,$first_msg) = @_;

    # まだログイン作業中であるのなら、ログインに成功したかどうかを
    # 最初に受け取った行が001(成功)か433(nick重複)かそれ以外かで判断する。
    my $reply = $first_msg->command;
    if ($reply eq RPL_WELCOME) {
	# 成功した。
	$this->{current_nick} = $first_msg->param(0);
	$this->{server_hostname} = $first_msg->prefix;
	if (!$this->_runloop->multi_server_mode_p &&
		$this->_runloop->current_nick ne $this->{current_nick}) {
	    $this->_runloop->broadcast_to_clients(
		IRCMessage->new(
		    Command => 'NICK',
		    Param => $first_msg->param(0),
		    Remarks => {'fill-prefix-when-sending-to-client' => 1
			       }));

	    $this->_runloop->set_current_nick($first_msg->param(0));
	}
	$this->{logged_in} = 1;
	$this->person($this->{current_nick},
		      $this->{user_shortname},
		      $this->{user_realname});

	$this->printmsg("Logged-in successfuly into ".$this->destination.".");

	# 各モジュールにサーバー追加の通知を行なう。
	$this->_runloop->notify_modules('connected_to_server',$this,$this->{new_connection});
	# 再接続だった場合の処理
	if (!$this->{new_connection}) {
	    $this->_runloop->reconnected_server($this);
	}
	$this->{new_connection} = undef;
    }
    elsif ($reply eq ERR_NICKNAMEINUSE) {
	# nick重複。
	$this->_set_to_next_nick($first_msg->param(1));
	return; # 何も返さない→クライアントにはこの結果を知らせない。
    }
    elsif ($reply eq ERR_UNAVAILRESOURCE) {
	# nick/channel is temporarily unavailable(この場合は nick)
	$this->_set_to_next_nick($first_msg->param(1));
	return; # 何も返さない→クライアントにはこの結果を知らせない。
    }
    elsif (grep { $_ eq $reply } (RPL_HELLO, RPL_WELCOME, qw(NOTICE PRIVMSG))) {
	# RPL_HELLO (irc2.11.x) / NOTICE / PRIVMSG
	return; # 何もしない
    }
    elsif ($reply eq 'PING') {
	$this->send_message(
	    new IRCMessage(
		Command => 'PONG',
		Param => $first_msg->param(0)));
    }
    else {
	# それ以外。手の打ちようがないのでconnectionごと切断してしまう。
	# 但し、ニューメリックリプライでもERRORでもなければ無視する。
	if ($reply eq 'ERROR' or $reply =~ m/^\d+/) {
	    $this->disconnect;
	    $this->die("Server replied $reply.\n".$first_msg->serialize."\n");
	}
	else {
	    $this->printmsg("Server replied $reply, ignored.\n".$first_msg->serialize."\n");
	    return;
	}
    }
    return $first_msg;
}

sub _receive_after_logged_in {
    my ($this,$msg) = @_;

    $this->person($msg->nick,$msg->name,$msg->host); # nameとhostを覚えておく。

    if (defined $msg->nick &&
	    $msg->nick ne $this->current_nick) {
	$msg->remark('message-send-by-other', 1);
    }

    if ($msg->command eq 'NICK') {
	# nickを変えたのが自分なら、それをクライアントには伝えない。
	my $current_nick = $this->{current_nick};
	if ($msg->nick eq $current_nick) {
	    $this->{current_nick} = $msg->param(0);

	    if ($this->_runloop->multi_server_mode_p) {
		# ここで消してしまうとプラグインにすらNICKが行かなくなる。
		# 消す代わりに"do-not-send-to-clients => 1"という註釈を付ける。
		$msg->remark('do-not-send-to-clients',1);

		# ローカルnickと違っていれば、その旨を通知する。
		# 但し、networks/always-notify-new-nickが設定されていれば常に通知する。
		my $local_nick = $this->_runloop->current_nick;
		if ($this->_conf_networks->always_notify_new_nick ||
		    $this->{current_nick} ne $local_nick) {

		    my $old_nick = $msg->nick;
		    $this->_runloop->broadcast_to_clients(
			IRCMessage->new(
			    Prefix => $this->_runloop->sysmsg_prefix(qw(priv nick::system)),
			    Command => 'NOTICE',
			    Params => [$local_nick,
				       "*** Your global nick in ".
					   $this->{network_name}." changed ".
					       "$old_nick -> ".
						   $this->{current_nick}."."]));
		}
	    } else {
		$this->_runloop->set_current_nick($msg->param(0));
	    }
	}
	$this->_NICK($msg);
    }
    elsif ($msg->command eq ERR_NICKNAMEINUSE) {
	# nickが既に使用中
	if ($this->_runloop->multi_server_mode_p) {
	    $this->_set_to_next_nick($msg->param(1));

	    # これもクライアントには伝えない。
	    $msg = undef;
	}
    }
    elsif ($msg->command eq ERR_UNAVAILRESOURCE) {
	# nick/channel temporary unavaliable
	if (Multicast::nick_p($msg->param(1)) && $this->_runloop->multi_server_mode_p) {
	    $this->_set_to_next_nick($msg->param(1));

	    # これもクライアントには伝えない。
	    $msg = undef;
	}
    }
    elsif ($msg->command eq 'JOIN') {
	$this->_JOIN($msg);
    }
    elsif ($msg->command eq 'KICK') {
	$this->_KICK($msg);
    }
    elsif ($msg->command eq 'MODE') {
	$this->_MODE($msg);
    }
    elsif ($msg->command eq 'NJOIN') {
	$this->_NJOIN($msg);
    }
    elsif ($msg->command eq 'PART') {
	$this->_PART($msg);
    }
    elsif ($msg->command eq 'QUIT' || $msg->command eq 'KILL') {
	# QUITとKILLは同じように扱う。
	$this->_QUIT($msg);
    }
    elsif ($msg->command eq 'TOPIC') {
	$this->_TOPIC($msg);
    }
    else {
	my $name = NumericReply::fetch_name($msg->command);
	if (defined $name) {
	    foreach (
		map("RPL_$_",
		    qw(CHANNELMODEIS NOTOPIC TOPIC TOPICWHOTIME
		       CREATIONTIME WHOREPLY NAMREPLY ENDOFNAMES
		       WHOISUSER WHOISSERVER AWAY ENDOFWHOIS
		       ISUPPORT YOURID),
		    map({("${_}LIST", "ENDOF${_}LIST");}
			    qw(INVITE EXCEPT BAN)),
		   )) {
		if ($name eq $_) {
		    no strict 'refs';
		    my $funcname = "_$_";
		    &$funcname($this, $msg); # $this->$funcname($msg)
		    last;
		}
	    }
	}
    }
    return $msg;
}

sub _KICK {
    my ($this,$msg) = @_;
    my @ch_names = split(/,/,$msg->param(0));
    my @nicks = split(/,/,$msg->param(1));
    my $kick = sub {
	my ($ch,$nick_to_kick) = @_;
	if ($nick_to_kick eq $this->{current_nick}) {
	    # KICKされたのが自分だった
	    $ch->remarks('kicked-out','1');
	}
	else {
	    $ch->names($nick_to_kick,undef,'delete');
	}
    };
    if (@ch_names == @nicks) {
	# チャンネル名とnickが1対1で対応
	map {
	    my ($ch_name,$nick) = ($ch_names[$_],$nicks[$_]);
	    my $ch = $this->channel($ch_name);
	    if (defined $ch) {
		#$ch->names($nick,undef,'delete');
		$kick->($ch,$nick);
	    }
	} 0 .. $#ch_names;
    }
    elsif (@ch_names == 1) {
	# 一つのチャンネルから1人以上をkick
	my $ch = $this->channel($ch_names[0]);
	if (defined $ch) {
	    map {
		#$ch->names($_,undef,'delete');
		$kick->($ch,$_);
	    } @nicks;
	}
    }
}

sub _MODE {
    my ($this,$msg) = @_;
    if ($msg->param(0) eq $this->{current_nick}) {
	# MODEの対象が自分なのでここでは無視。
	return;
    }

    my $ch = $this->channel($msg->param(0));
    if (defined $ch) {
	my $n_params = @{$msg->params};

	my $plus = 0; # 現在評価中のモードが+なのか-なのか。
	my $mode_char_pos = 1; # 現在評価中のmode characterの位置。
	my $mode_param_offset = 0; # $mode_char_posから幾つの追加パラメタを拾ったか。

	my $fetch_param = sub {
	    $mode_param_offset++;
	    return $msg->param($mode_char_pos + $mode_param_offset);
	};

	for (;$mode_char_pos < $n_params;$mode_char_pos += $mode_param_offset + 1) {
	    $mode_param_offset = 0; # これは毎回リセットする。
	    foreach my $c (split //,$msg->param($mode_char_pos)) {
		my $add_or_delete = ($plus ? 'add' : 'delete');
		my $undef_or_delete = ($plus ? undef : 'delete');
		if ($c eq '+') {
		    $plus = 1;
		}
		elsif ($c eq '-') {
		    $plus = 0;
		}
		elsif (index('aimnpqrst',$c) != -1) {
		    $ch->switches($c,1,$undef_or_delete);
		}
		elsif ($c eq 'b') {
		    $ch->banlist($add_or_delete,&$fetch_param);
		}
		elsif ($c eq 'e') {
		    $ch->exceptionlist($add_or_delete,&$fetch_param);
		}
		elsif ($c eq 'I') {
		    $ch->invitelist($add_or_delete,&$fetch_param);
		}
		elsif ($c eq 'k') {
		    $ch->parameters('k',&$fetch_param,$undef_or_delete);
		}
		elsif ($c eq 'l') {
		    $ch->parameters('l',($plus ? &$fetch_param : undef),$undef_or_delete);
		}
		elsif ($c eq 'o' || $c eq 'O') {
		    # oとOは同一視
		    eval {
			$ch->names(&$fetch_param)->has_o($plus);
		    };
		}
		elsif ($c eq 'v') {
		    eval {
			$ch->names(&$fetch_param)->has_v($plus);
		    };
		}
	    }
	}
    }
}

sub _JOIN {
    my ($this,$msg) = @_;

    map {
	m/^([^\x07]+)(?:\x07(.*))?/;
	my ($ch_name,$mode) = ($1,(defined $2 ? $2 : ''));

	my $ch = $this->channel($ch_name);
	if (defined $ch) {
	    # 知っているチャンネル。もしkickedフラグが立っていたらクリア。
	    $ch->remarks('kicked-out',undef,'delete');
	}
	else {
	    # 知らないチャンネル。
	    $ch = ChannelInfo->new($ch_name,$this->{network_name});
	    $this->{channels}{Multicast::lc($ch_name)} = $ch;
	}
	$ch->names($msg->nick,
		   new PersonInChannel(
		       $this->person($msg->nick,$msg->name,$msg->host),
		       index($mode,"o") != -1 || index($mode,"O") != -1, # oもOも今は同一視
		       index($mode,"v") != -1));
    } split(/,/,$msg->param(0));
}

sub _NJOIN {
    my ($this,$msg) = @_;
    my $ch_name = $msg->param(0);
    my $ch = $this->channel($ch_name);
    unless (defined $ch) {
		# 知らないチャンネル。
	$ch = ChannelInfo->new($ch_name,$this->{network_name});
	$this->{channels}{Multicast::lc($ch_name)} = $ch;
    }
    map {
	m/^([@+]*)(.+)$/;
	my ($mode,$nick) = ($1,$2);

	$ch->names($nick,
		   new PersonInChannel(
		       $this->person($nick),
		       index($mode,"@") != -1, # 今は@と@@を同一視。
			       index($mode,"+") != -1));
    } split(/,/,$msg->param(1));
}

sub _PART {
    my ($this,$msg) = @_;
    map {
	my $ch_name = $_;
	my $ch = $this->channel($ch_name);
	if (defined $ch) {
	    if ($msg->nick eq $this->{current_nick}) {
		# PARTしたのが自分だった
		delete $this->{channels}->{Multicast::lc($ch_name)};
	    }
	    else {
		$ch->names($msg->nick,undef,'delete');
	    }
	}
    } split(/,/,$msg->param(0));

    # 全チャンネルを走査し、このnickを持つ人物が一人も居なくなつてゐたらpeopleからも消す。
    my $alive;
    foreach my $ch (values %{$this->{channels}}) {
	if (defined $ch->names($msg->nick)) {
	    $alive = 1;
	}
    }
    if (!$alive) {
	delete $this->{people}{$msg->nick};
    }
}

sub _NICK {
    my ($this,$msg) = @_;
    # PersonalInfoとChannelInfoがnickを持っているので書き換える。
    my ($old,$new) = ($msg->nick,$msg->param(0));

    if (!defined $this->{people}->{$old}) {
	return;
    }

    $this->{people}->{$old}->nick($new);
    $this->{people}->{$new} = $this->{people}->{$old};
    delete $this->{people}->{$old};

    my @channels = grep {
	defined $_->names($old);
    } values %{$this->{channels}};

    # このNICKが影響を及ぼした全チャンネル名のリストを
    # "affected-channels"として註釈を付ける。
    my @affected = map {
	my $ch = $_;
	$ch->names($new,$ch->names($old));
	$ch->names($old,undef,'delete');
	$ch->name;
    } @channels;
    $msg->remark('affected-channels',\@affected);
}

sub _QUIT {
    my ($this,$msg) = @_;
    # people及びchannelsから削除する。
    delete $this->{people}->{$msg->nick};

    my @channels = grep {
	defined $_->names($msg->nick);
    } values %{$this->{channels}};

    # このNICKが影響を及ぼした全チャンネル名のリストを
    # "affected-channels"として註釈を付ける。
    my @affected = map {
	my $ch = $_;
	$ch->names($msg->nick,undef,'delete');
	$ch->name;
    } @channels;
    $msg->remark('affected-channels',\@affected);
}

sub _TOPIC {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(0));
    if (defined $ch) {
	# 古いトピックを"old-topic"として註釈を付ける。
	$msg->remark('old-topic', $ch->topic);
	$ch->topic($msg->param(1));

	# topic_who と topic_time を指定する
	$ch->topic_who($msg->prefix);
	$ch->topic_time(time);
    }
}

sub _RPL_NAMREPLY {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(2));
    return unless defined $ch;

    my $receiving_namreply = $this->{receiving_namreply}->{$msg->param(2)};
    unless (defined $receiving_namreply &&
	    $receiving_namreply == 1) {
	# NAMESを初期化
	$ch->names(undef,undef,'clear');
	# NAMREPLY受信中フラグを立てる
	$this->{receiving_namreply}->{$msg->param(2)} = 1;
    }

    if (defined $ch) {
	# @なら+s,*なら+p、=ならそのどちらでもない事が確定している。
	my $ch_property = $msg->param(1);
	if ($ch_property eq '@') {
	    $ch->switches('s',1);
	    $ch->switches('p',undef,'delete');
	}
	elsif ($ch_property eq '*') {
	    $ch->switches('s',undef,'delete');
	    $ch->switches('p',1);
	}
	else {
	    $ch->switches('s',undef,'delete');
	    $ch->switches('p',undef,'delete');
	}

	my @people = map {
	    m/^([@\+]{0,2})(.+)$/;
	    my ($mode,$nick) = ($1,$2);

	    $ch->names($nick,
		       new PersonInChannel(
			   $this->person($nick),
			   index($mode,"@") != -1,
			   index($mode,"+") != -1));
	} split(/ /,$msg->param(3));
    }
}

sub _RPL_ENDOFNAMES {
    my ($this,$msg) = @_;
    delete $this->{receiving_namreply}->{$msg->param(1)};
}

sub _RPL_WHOISUSER {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	$p->username($msg->param(2));
	$p->userhost($msg->param(3));
	$p->realname($msg->param(5));
	$this->_START_WHOIS_REPLY($p);
    }
}

sub _START_WHOIS_REPLY {
    my ($this,$p) = @_;
    $p->remark('wait-rpl_away', 1);
}

sub _RPL_ENDOFWHOIS {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	if ($p->remark('wait-rpl_away')) {
	    $p->remark('wait-rpl_away', 0);
	    $p->away('');
	}
    }
}

sub _RPL_AWAY {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	$p->remark('wait-rpl_away', 0);
	$p->away($msg->param(2));
    }
}

sub _RPL_WHOISSERVER {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	$p->server($msg->param(2));
    }
}

sub _RPL_NOTOPIC {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->topic('');
    }
}

sub _RPL_TOPIC {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->topic($msg->param(2));
    }
}

sub _RPL_TOPICWHOTIME {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->topic_who($msg->param(2));
	$ch->topic_time($msg->param(3));
    }
}

sub _RPL_CREATIONTIME {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->remark('creation-time', $msg->param(2));
    }
}

sub _RPL_INVITELIST {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));

    my $receiving_invitelist = $this->{receiving_invitelist}->{$msg->param(1)};
    if (defined $receiving_invitelist &&
	$receiving_invitelist == 1) {
	# +Iリストを初期化
	$ch->invitelist(undef,undef,'clear');
	# INVITELIST受信中フラグを立てる
	$this->{receiving_invitelist}->{$msg->param(1)} = 1;
    }

    if (defined $ch) {
	# 重複防止のため、一旦deleteしてからadd。
	$ch->invitelist('delete',$msg->param(2));
	$ch->invitelist('add',$msg->param(2));
    }
}

sub _RPL_ENDOFINVITELIST {
    my ($this,$msg) = @_;
    delete $this->{receiving_invitelist}->{$msg->param(1)};
}

sub _RPL_EXCEPTLIST {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));

    my $receiving_exceptlist = $this->{receiving_exceptlist}->{$msg->param(1)};
    if (defined $receiving_exceptlist &&
	$receiving_exceptlist == 1) {
	# +eリストを初期化
	$ch->exceptionlist(undef,undef,'clear');
	# EXCEPTLIST受信中フラグを立てる
	$this->{receiving_exceptlist}->{$msg->param(1)} = 1;
    }

    if (defined $ch) {
	# 重複防止のため、一旦deleteしてからadd。
	$ch->exceptionlist('delete',$msg->param(2));
	$ch->exceptionlist('add',$msg->param(2));
    }
}

sub _RPL_ENDOFEXCEPTLIST {
    my ($this,$msg) = @_;
    delete $this->{receiving_exceptlist}->{$msg->param(1)};
}

sub _RPL_BANLIST {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));

    my $receiving_banlist = $this->{receiving_banlist}->{$msg->param(1)};
    if (defined $receiving_banlist &&
	$receiving_banlist == 1) {
	# +bリストを初期化
	$ch->banlist(undef,undef,'clear');
	# BANLIST受信中フラグを立てる
	$this->{receiving_banlist}->{$msg->param(1)} = 1;
    }

    if (defined $ch) {
	# 重複防止のため、一旦deleteしてからadd。
	$ch->banlist('delete',$msg->param(2));
	$ch->banlist('add',$msg->param(2));
    }
}

sub _RPL_ENDOFBANLIST {
    my ($this,$msg) = @_;
    delete $this->{receiving_banlist}->{$msg->param(1)};
}

sub _RPL_WHOREPLY {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(5)};
    if (defined $p) {
	$p->username($msg->param(2));
	$p->userhost($msg->param(3));
	$p->server($msg->param(4));
	$p->realname((split / /,$msg->param(7),2)[1]);
	if ($msg->param(6) =~ /^G/) {
	    $p->away('Gone.');
	} else {
	    $p->away('');
	}
	my $hops = $this->remark('server-hops') || {};
	$hops->{$p->server} = (split / /,$msg->param(7),2)[0];
	$this->remark('server-hops', $hops);
    }

    #use Data::Dumper;
    #open(LOG,"> log.txt");
    #print LOG "------- people --------\n";
    #print LOG Dumper($this->{people}),"\n";
    #print LOG "------- channels --------\n";
    #print LOG Dumper($this->{channels}),"\n";
    #close(LOG);
}

sub _RPL_CHANNELMODEIS {
    my ($this,$msg) = @_;
    # 既知のチャンネルなら、そのチャンネルに
    # switches-are-known => 1という備考を付ける。
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->remarks('switches-are-known',1);

	# switches と parameters は必ず得られると仮定して、クリア処理を行う
	$ch->switches(undef, undef, 'clear');
	$ch->parameters(undef, undef, 'clear');
    }

    # 鯖がMODEを実行したことにして、_MODEに処理を代行させる。
    my @args = @{$msg->params};
    @args = @args[1 .. $#args];

    $this->_MODE(
	new IRCMessage(Prefix => $msg->prefix,
		       Command => 'MODE',
		       Params => \@args));
}

sub _RPL_ISUPPORT {
    # 歴史的な理由で、 RPL_ISUPPORT(005) は
    # RPL_BOUNCE(005) として使われていることがある。
    my ($this,$msg) = @_;
    if ($msg->n_params >= 2 && # nick + [params] + 'are supported by this server'
	    $msg->param($msg->n_params - 1) =~ /supported/i) {
	foreach my $param ((@{$msg->params})[1...($msg->n_params - 2)]) {
	    my ($negate, $key, $value) = $param =~ /^(-)?([[:alnum:]]+)(?:=(.+))?$/;
	    if (!defined $negate) {
		# empty value
		$value = '' unless defined $value;
		$this->{isupport}->{$key} = $value;
	    } elsif (!defined $value) {
		# negate a previously specified parameter
		delete $this->{isupport}->{$key};
	    } else {
		# inconsistency param
		carp("inconsistency RPL_ISUPPORT param: $param");
	    }
	}
    }
}

sub _RPL_YOURID {
    my ($this,$msg) = @_;

    $this->remark('uid', $msg->param(1));
}

sub _set_to_next_nick {
    my ($this,$failed_nick) = @_;
    # failed_nickの次のnickを試します。nick重複でログインに失敗した時に使います。
    my $next_nick = modify_nick($failed_nick, $this->isupport->{NICKLEN});

    my $msg_for_user = "Nick $failed_nick was already in use in the ".$this->network_name.". Trying ".$next_nick."...";
    $this->send_message(
	new IRCMessage(
	    Command => 'NICK',
	    Param => $next_nick));
    $this->_runloop->broadcast_to_clients(
	new IRCMessage(
	    Prefix => $this->_runloop->sysmsg_prefix(qw(priv nick::system)),
	    Command => 'NOTICE',
	    Params => [$this->_runloop->current_nick,$msg_for_user]));
    $this->printmsg($msg_for_user);
}

sub modify_nick {
    my $nick = shift;
    my $nicklen = shift || 9;

    if ($nick =~ /^(.*\D)?(\d+)$/) {
	# 最後の数文字が数字だったら、それをインクリメント
	my $base = $1;
	my $next_num = $2 + 1;
	if (($next_num - 1) eq $next_num) {
	    # 桁あふれしているので数字部分を全部消す。
	    $nick = $base;
	} elsif (length($base . $next_num) <= $nicklen) {
	    # $nicklen 文字以内に収まるのでこれで試す。
	    $nick = $base . $next_num;
	}
	else {
	    # 収まらないので $nicklen 文字に縮める。
	    $nick = substr($base,0,$nicklen - length($next_num)) . $next_num;
	}
    }
    elsif ($nick =~ /_$/ && length($nick) >= $nicklen) {
	# 最後の文字が_で、それ以上_を付けられない場合、それを0に。
	$nick =~ s/_$/0/;
    }
    else {
	# 最後に_を付ける。
	if (length($nick) >= $nicklen) {
	    $nick =~ s/.$/_/;
	}
	else {
	    $nick .= '_';
	}
    }
    return $nick;
}

1;
