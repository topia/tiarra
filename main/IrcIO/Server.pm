# -----------------------------------------------------------------------------
# $Id: Server.pm,v 1.56 2004/05/08 08:11:31 topia Exp $
# -----------------------------------------------------------------------------
# IrcIO::ServerはIRCサーバーに接続し、IRCメッセージをやり取りするクラスです。
# このクラスはサーバーからメッセージを受け取ってチャンネル情報や現在のnickなどを保持しますが、
# 受け取ったメッセージをモジュールに通したり各クライアントに転送したりはしません。
# それはRunLoopの役目です。
# -----------------------------------------------------------------------------
package IrcIO::Server;
use strict;
use warnings;
use base qw(IrcIO);
use Carp;
use ChannelInfo;
use PersonalInfo;
use PersonInChannel;
use Configuration;
use UNIVERSAL;
use Multicast;
use NumericReply;

sub new {
    my ($class,$network_name) = @_;
    my $obj = $class->SUPER::new;
    $obj->{network_name} = $network_name;
    $obj->{current_nick} = ''; # 現在使用中のnick。ログインしていなければ空。
    $obj->{server_hostname} = ''; # サーバが主張している hostname。こちらもログインしてなければ空。
    $obj->reload_config;

    $obj->{logged_in} = 0; # このサーバーへのログインに成功しているかどうか。
    $obj->{new_connection} = 1;

    $obj->{receiving_namreply} = {}; # RPL_NAMREPLYを受け取ると<チャンネル名,1>になり、RPL_ENDOFNAMESを受け取るとそのチャンネルの要素が消える。
    $obj->{receiving_banlist} = {}; # 同上。RPL_BANLIST
    $obj->{receiving_exceptlist} = {}; # 同上。RPL_EXCEPTLIST
    $obj->{receiving_invitelist} = {}; # 同上、RPL_INVITELIST

    $obj->{channels} = {}; # 小文字チャンネル名 => ChannelInfo
    $obj->{people} = {}; # nick => PersonalInfo

    $obj->connect;
}

sub network_name {
    shift->{network_name};
}

sub current_nick {
    shift->{current_nick};
}

sub server_hostname {
    shift->{server_hostname};
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

sub host {
    shift->{server_host};
}

sub fullname {
    $_[0]->{current_nick}.'!'.$_[0]->{user_shortname}.'@'.$_[0]->{server_host};
}

sub config {
    # このオブジェクトの生成に用いられたConfiguration::Blockを返す。
    shift->{config};
}

sub reload_config {
    my $this = shift;
    my $conf = $this->{config} = Configuration->shared->get($this->{network_name});
    my $general = Configuration->shared->general;
    $this->{server_host} = $conf->host;
    $this->{server_port} = $conf->port;
    $this->{destination} = do {
	if ($this->{server_host} =~ m/^[0-9a-fA-F:]+$/) {
	    "[$this->{server_host}]:$this->{server_port}";
	}
	else {
	    "$this->{server_host}:$this->{server_port}";
	}
    };
    my $def = sub{defined$_[0]?$_[0]:$_[1]};
    $this->{server_password} = $conf->password;
    $this->{initial_nick} = $def->($conf->nick,$general->nick); # ログイン時に設定するnick。
    $this->{user_shortname} = $def->($conf->user,$general->user);
    $this->{user_realname} = $def->($conf->name,$general->name);
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

sub connect {
    my $this = shift;
    return if $this->connected;

    # 初期化すべきフィールドを初期化
    $this->{nick_retry} = 0;
    $this->{logged_in} = undef;

    my $server_host = $this->{server_host};
    my $server_port = $this->{server_port};

    # 追加パラメータ
    my $conf = Configuration->shared;
    my $additional_ipv4 = {};
    my $ipv4_bind_addr =
	$conf->get($this->{network_name})->ipv4_bind_addr ||
	$conf->general->ipv4_bind_addr ||
	$conf->get($this->{network_name})->bind_addr ||
	$conf->general->bind_addr; # 以上二つは過去互換性の為に残す。
    if (defined $ipv4_bind_addr) {
	$additional_ipv4->{LocalAddr} = $ipv4_bind_addr;
    }
    my $additional_ipv6 = {};
    my $ipv6_bind_addr =
	Configuration->shared->get($this->{network_name})->ipv6_bind_addr ||
	Configuration->shared->general->ipv6_bind_addr;
    if (defined $ipv6_bind_addr) {
	$additional_ipv6->{LocalAddr} = $ipv6_bind_addr;
    }

    # ソケットを開く。開けなかったらdie。
    # 接続は次のようにして行なう。
    # 1. ホストがIPv4アドレスであれば、IPv4として接続を試みる。
    # 2. ホストがIPv6アドレスであれば、IPv6として接続を試みる。
    # 3. どちらの形式でもない(つまりホスト名)であれば、
    #    a. IPv6が利用可能ならIPv6での接続を試みた後、駄目ならIPv4にフォールバック
    #    b. IPv6が利用可能でなければ、最初からIPv4での接続を試みる。
    my @new_socket_args = (
	PeerAddr => $server_host,
	PeerPort => $server_port,
	Proto => 'tcp',
	Timeout => 5,
    );
    my $sock = do {
	if ($server_host =~ m/^(?:\d+\.){3}\d+$/) {
	    IO::Socket::INET->new(@new_socket_args,%$additional_ipv4);
	}
	elsif ($server_host =~ m/^[0-9a-fA-F:]+$/) {
	    if (&::ipv6_enabled) {
		IO::Socket::INET6->new(@new_socket_args,%$additional_ipv6);
	    }
	    else {
		die qq{Host $server_host seems to be an IPv6 address, }.
		    qq{but IPv6 support is not enabled. }.
		    qq{Use IPv4 server or install Socket6.pm if possible.\n};
	    }
	}
	else {
	    if (&::ipv6_enabled) {
		my $s = IO::Socket::INET6->new(@new_socket_args,%$additional_ipv6);
		if (defined $s) {
		    # IPv6での接続に成功。
		    $s;
		}
		else {
		    # IPv4にフォールバック。
		    IO::Socket::INET->new(@new_socket_args,%$additional_ipv4);
		}
	    }
	    else {
		IO::Socket::INET->new(@new_socket_args,%$additional_ipv4);
	    }
	}
    };
    if (defined $sock) {
	$sock->autoflush(1);
	$this->{sock} = $sock;
	$this->{connected} = 1;
	my $ip_version = do {
	    if ($sock->isa('IO::Socket::INET')) {
		'IPv4';
	    }
	    else {
		'IPv6';
	    }
	};
	::printmsg("Opened connection to $this->{destination} ($ip_version)");
    }
    else {
	die "Couldn't connect to $this->{destination}\n";
    }

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
    if (my $usermode_str = Configuration->shared->general->user_mode) {
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
    $this;
}

sub disconnect {
    my $this = shift;

    $this->SUPER::disconnect;
    ::printmsg("Disconnected from $this->{destination}.");
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
    #RunLoop->shared->notify_modules('notification_of_message_io',$msg,$this,'out');

    $this->SUPER::send_message(
	$msg,
	Configuration->shared->get($this->{network_name})->out_encoding ||
	Configuration->shared->general->server_out_encoding);
}

sub receive {
    my $this = shift;
    $this->SUPER::receive(
	Configuration->shared->get($this->{network_name})->in_encoding ||
	Configuration->shared->general->server_in_encoding);

    # 接続が切れたら、各モジュールとRunLoopへ通知
    if (!$this->connected) {
	RunLoop->shared->notify_modules('disconnected_from_server',$this);
	RunLoop->shared->disconnected_server($this);
    }
}

sub pop_queue {
    my ($this) = shift;
    my $msg = $this->SUPER::pop_queue;

    # このメソッドはログインしていなければログインするが、
    # パスワードが違うなどで何度やり直してもログイン出来る見込みが無ければ
    # 接続を切ってからdieします。
    if (defined $msg) {
	# 各モジュールに通知
	#RunLoop->shared->notify_modules('notification_of_message_io',$msg,$this,'in');

	# ログイン作業中か？
	if ($this->{logged_in}) {
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
	if (!RunLoop->shared->multi_server_mode_p &&
		RunLoop->shared_loop->current_nick ne $this->{current_nick}) {
	    RunLoop->shared->broadcast_to_clients(
		IRCMessage->new(
		    Command => 'NICK',
		    Param => $first_msg->param(0),
		    Remarks => {'fill-prefix-when-sending-to-client' => 1
			       }));

	    RunLoop->shared_loop->set_current_nick($first_msg->param(0));
	}
	$this->{logged_in} = 1;
	$this->person($this->{current_nick},
		      $this->{user_shortname},
		      $this->{user_realname});

	::printmsg("Logged-in successfuly into $this->{destination}.");

	# 各モジュールにサーバー追加の通知を行なう。
	RunLoop->shared->notify_modules('connected_to_server',$this,$this->{new_connection});
	# 再接続だった場合の処理
	if (!$this->{new_connection}) {
	    RunLoop->shared->reconnected_server($this);
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
    elsif ($reply eq RPL_HELLO) {
	# RPL_HELLO (irc2.11.x)
	return; # 何もしない
    }
    else {
	# それ以外。手の打ちようがないのでconnectionごと切断してしまう。
	# 但し、ニューメリックリプライでもERRORでもなければ無視する。
	if ($reply eq 'ERROR' or $reply =~ m/^\d+/) {
	    $this->disconnect;
	    die "Server replied $reply.\n".$first_msg->serialize."\n";
	}
	else {
	    return;
	}
    }
    return $first_msg;
}

sub _receive_after_logged_in {
    my ($this,$msg) = @_;
      
    $this->person($msg->nick,$msg->name,$msg->host); # nameとhostを覚えておく。

    if ($msg->command eq 'NICK') {
	# nickを変えたのが自分なら、それをクライアントには伝えない。
	my $current_nick = $this->{current_nick};
	if ($msg->nick eq $current_nick) {
	    $this->{current_nick} = $msg->param(0);

	    if (RunLoop->shared->multi_server_mode_p) {
		# ここで消してしまうとプラグインにすらNICKが行かなくなる。
		# 消す代わりに"do-not-send-to-clients => 1"という註釈を付ける。
		$msg->remark('do-not-send-to-clients',1);

		# ローカルnickと違っていれば、その旨を通知する。
		# 但し、networks/always-notify-new-nickが設定されていれば常に通知する。
		my $local_nick = RunLoop->shared_loop->current_nick;
		if (Configuration->shared->networks->always_notify_new_nick ||
		    $this->{current_nick} ne $local_nick) {

		    my $old_nick = $msg->nick;
		    RunLoop->shared_loop->broadcast_to_clients(
			IRCMessage->new(
			    Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv nick::system)),
			    Command => 'NOTICE',
			    Params => [$local_nick,
				       "*** Your global nick in ".
					   $this->{network_name}." changed ".
					       "$old_nick -> ".
						   $this->{current_nick}."."]));
		}
	    } else {
		RunLoop->shared_loop->set_current_nick($msg->param(0));
	    }
	}
	$this->_NICK($msg);
    }
    elsif ($msg->command eq ERR_NICKNAMEINUSE) {
	# nickが既に使用中
	if (RunLoop->shared->multi_server_mode_p) {
	    $this->_set_to_next_nick($msg->param(1));

	    # これもクライアントには伝えない。
	    $msg = undef;
	}
    }
    elsif ($msg->command eq ERR_UNAVAILRESOURCE) {
	# nick/channel temporary unavaliable
	if (Multicast::nick_p($msg->param(1)) && RunLoop->shared->multi_server_mode_p) {
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
	my $isupport = $this->remark('isupport');
	foreach my $param ((@{$msg->params})[1...($msg->n_params - 2)]) {
	    my ($negate, $key, $value) = $param =~ /^(-)?([[:alnum:]]+)(?:=(.+))?$/;
	    if (!defined $negate) {
		# empty value
		$value = '' unless defined $value;
		$isupport->{$key} = $value;
	    } elsif (!defined $value) {
		# negate a previously specified parameter
		delete $isupport->{$key};
	    } else {
		# inconsistency param
		carp("inconsistency RPL_ISUPPORT param: $param");
	    }
	}
	$this->remark('isupport', $isupport);
    }
}

sub _RPL_YOURID {
    my ($this,$msg) = @_;

    $this->remark('uid', $msg->param(1));
}

sub _set_to_next_nick {
    my ($this,$failed_nick) = @_;
    # failed_nickの次のnickを試します。nick重複でログインに失敗した時に使います。
    my $nicklen = do {
	if (defined $this->remark('isupport') &&
		defined $this->remark('isupport')->{NICKLEN}) {
	    $this->remark('isupport')->{NICKLEN};
	} else {
	    9;
	}
    };
    my $next_nick = modify_nick($failed_nick, $nicklen);

    my $msg_for_user = "Nick $failed_nick was already in use in the ".$this->network_name.". Trying ".$next_nick."...";
    $this->send_message(
	new IRCMessage(
	    Command => 'NICK',
	    Param => $next_nick));
    RunLoop->shared_loop->broadcast_to_clients(
	new IRCMessage(
	    Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv nick::system)),
	    Command => 'NOTICE',
	    Params => [RunLoop->shared_loop->current_nick,$msg_for_user]));
    main::printmsg($msg_for_user);
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
