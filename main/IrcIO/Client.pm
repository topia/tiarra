# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IrcIO::Clientはクライアントからの接続を受け、
# IRCメッセージをやり取りするクラスです。
# -----------------------------------------------------------------------------
package IrcIO::Client;
use strict;
use warnings;
use Carp;
use IrcIO;
use base qw(IrcIO);
use Net::hostent;
use Crypt;
use Multicast;
use Mask;
use LocalChannelManager;
use NumericReply;
use Tiarra::Utils;
# shorthand
my $utils = Tiarra::Utils->shared;

# 複数のパッケージを混在させてるとSelfLoaderが使えない…？
#use SelfLoader;
#SelfLoader->load_stubs; # このクラスには親クラスがあるから。(SelfLoaderのpodを参照)
#1;
#__DATA__

sub new {
    my ($class,$runloop,$sock) = @_;
    my $this = $class->SUPER::new($runloop);
    $this->{sock} = $sock;
    $this->{connected} = 1;
    $this->{client_host} = do {
	my $hostent = Net::hostent::gethost($sock->peerhost); # 逆引き
	defined $hostent ? $hostent->name : $sock->peerhost;
    };
    $this->{pass_received} = ''; # クライアントから受け取ったパスワード
    $this->{nick} = ''; # ログイン時にクライアントから受け取ったnick。変更されない。
    $this->{username} = ''; # 同username
    $this->{logging_in} = 1; # ログイン中なら1
    $this->{options} = {}; # クライアントが接続時に$key=value$で指定したオプション。

    # このホストからの接続は許可されているか？
    my $allowed_host = $this->_conf_general->client_allowed;
    if (defined $allowed_host) {
	unless (Mask::match($allowed_host,$this->{client_host})) {
	    # マッチしないのでdie。
	    die "One client at ".$this->{client_host}." connected to me, but the host is not allowed.\n";
	}
    }
    ::printmsg("One client at ".$this->{client_host}." connected to me.");
    $this->_runloop->register_receive_socket($sock);
    $this;
}

sub logging_in {
    shift->{logging_in};
}

sub username {
    shift->{username};
}

sub client_host {
    shift->{client_host};
}

sub fullname {
    # このクライアントをtiarraから見たnick!username@userhostの形式で表現する。
    my ($this,$type) = @_;
    if (defined $type && $type eq 'error') {
	$this->_runloop->current_nick.'['.$this->{username}.'@'.$this->{client_host}.']';
    }
    else {
	$this->_runloop->current_nick.'!'.$this->{username}.'@'.$this->{client_host};
    }
}

sub fullname_from_client {
    # このクライアントをクライアントから見たnick!username@userhostの形式で表現する。
    # この関数が返すnickは初めに受け取ったものである点に注意。
    my $this = shift;
    $this->{nick}.'!'.$this->{username}.'@'.$this->{client_host};
}

sub parse_realname {
    my ($this,$realname) = @_;
    return if !defined $realname;
    # $key=value;key=value;...$
    #
    # 以下は全て有効で、同じ意味である。
    # $ foo = bar; key=  value$
    # $ foo=bar;key=value $
    # $foo    =bar;key=  value    $

    my $key = qr{[^=]+?}; # キーとして許されるパターン
    my $value = qr{[^;]*?}; # 値として許されるパターン
    my $lastpair = qr{$key\s*=\s*$value};
    my $pair = qr{$lastpair\s*;};

    my $line = qr{^\$(?:\s*($pair)\s*)*\s*($lastpair)\s*\$$};
    if (my @pairs = ($realname =~ m/$line/g)) {
	%{$this->{options}} = map {
	    m/^\s*($key)\s*=\s*($value)\s*;?$/;
	} grep {
	    defined;
	} @pairs;
    }
}

sub option {
    # ログイン時に$key=value$で指定されたオプションを取得する。
    # 指定されたキーに対する値が存在しなかった場合はundefを返す。
    my ($this,$key) = @_;
    if (defined $key) {
	$this->{options}->{$key};
    }
    else {
	croak "IrcIO::Client->option, Arg[1] was undef.";
    }
}

sub option_or_default {
    my ($this, $base, $config_prefix, $option_prefix, $default) = @_;
    my $value;

    $utils->get_first_defined(
	$this->option($utils->to_str($option_prefix).$base),
	$this->_conf_general->get($utils->to_str($option_prefix).$base),
	$default);
}

sub option_or_default_multiple {
    my ($this, $base, $types, $config_prefix) = @_;

    return $utils->get_first_defined(
	(map {
	    $this->option(join('',$utils->to_str($_, $base)));
	} @$types),
	(map {
	    $this->_conf_general->get(
		join('',$utils->to_str($config_prefix, $_, $base)));
	} @$types));
}

sub send_message {
    my ($this,$msg) = @_;

    # 各モジュールに通知
    #$this->_runloop->notify_modules('notification_of_message_io',$msg,$this,'out');

    $this->SUPER::send_message(
	$msg,
	$this->option_or_default_multiple('encoding', ['out-', ''], 'client-'));
}

sub receive {
    my ($this) = shift;
    $this->SUPER::receive(
	$this->option_or_default_multiple('encoding', ['in-', ''], 'client'));

    # 接続が切れたら、各モジュールへ通知
    if (!$this->connected) {
	$this->_runloop->notify_modules('client_detached',$this);
    }
}

sub pop_queue {
    my $this = shift;
    my $msg = $this->SUPER::pop_queue;

    # クライアントがログイン中なら、ログインを受け付ける。
    if (defined $msg) {
	# 各モジュールに通知
	#$this->_runloop->notify_modules('notification_of_message_io',$msg,$this,'in');

	# ログイン作業中か？
	if ($this->{logging_in}) {
	    return $this->_receive_while_logging_in($msg);
	}
	else {
	    return $this->_receive_after_logged_in($msg);
	}
    }
    return $msg;
}

sub _receive_while_logging_in {
    my ($this,$msg) = @_;

    # NICK及びUSERを受け取った時点でそのログインの正当性を確認し、作業を終了する。
    my $command = $msg->command;
    if ($command eq 'PASS') {
	$this->{pass_received} = $msg->params->[0];
    }
    elsif ($command eq 'NICK') {
	$this->{nick} = $msg->params->[0];
    }
    elsif ($command eq 'USER') {
	$this->{username} = $msg->param(0);
	$this->parse_realname($msg->param(3));
    }
    elsif ($command eq 'PING') {
	$this->send_message(
	    new IRCMessage(
		Command => 'PONG',
		Param => $msg->param(0)));
    }
    elsif ($command eq 'QUIT') {
	$this->send_message(
	    IRCMessage->new(
		Command => 'ERROR',
		Param => 'Closing Link: ['.$this->fullname_from_client.'] ()'));
	$this->disconnect_after_writing;
    }

    if ($this->{nick} ne '' && $this->{username} ne '') {
	# general/tiarra-passwordを取得
	my $valid_password = $this->_conf_general->tiarra_password;
	my $prefix = $this->_runloop->sysmsg_prefix('system');
	if (defined $valid_password && $valid_password ne '' &&
	    ! Crypt::check($this->{pass_received},$valid_password)) {
	    # パスワードが正しくない。
	    ::printmsg("Refused login of ".$this->fullname_from_client." because of bad password.");

	    $this->send_message(
		new IRCMessage(Prefix => $prefix,
			       Command => ERR_PASSWDMISMATCH,
			       Params => [$this->{nick},'Password incorrect']));
	    $this->send_message(
		new IRCMessage(Command => 'ERROR',
			       Param => 'Closing Link: ['.$this->fullname_from_client.'] (Bad Password)'));
		$this->disconnect_after_writing;
	}
	else {
	    # パスワードが正しいか、指定されていない。
	    ::printmsg('Accepted login of '.$this->fullname_from_client.'.');
	    if ((my $n_options = keys %{$this->{options}}) > 0) {
		# オプションが指定されていたら表示する。
		my $options = join ' ; ',map {
		    "$_ = $this->{options}->{$_}";
		} keys %{$this->{options}};
		::printmsg('Given option'.($n_options == 1 ? '' : 's').': '.$options);
	    }
	    $this->{logging_in} = 0;

	    $this->send_message(
		new IRCMessage(Prefix => $prefix,
			       Command => RPL_WELCOME,
			       Params => [$this->{nick},'Welcome to the Internet Relay Network '.$this->fullname_from_client]));

	    my $current_nick = $this->_runloop->current_nick;
	    if ($this->{nick} ne $current_nick) {
		# クライアントが送ってきたnickとローカルのnickが食い違っているので正しいnickを教える。
		$this->send_message(
		    new IRCMessage(Prefix => $this->fullname_from_client,
				   Command => 'NICK',
				   Param => $current_nick));
	    }

	    my $send_message = sub {
		my ($command, @params) = @_;
		$this->send_message(
		    new IRCMessage(
			Prefix => $prefix,
			Command => $command,
			Params => [$current_nick,
				   @params],
		       ));
	    };

	    map {
		# ローカルnickとグローバルnickが食い違っていたらその旨を伝える。
		my $network_name = $_->network_name;
		my $global_nick = $_->current_nick;
		if ($global_nick ne $current_nick) {
		    $this->send_message(
			new IRCMessage(
			    Prefix => $this->_runloop->sysmsg_prefix(qw(priv system)),
			    Command => 'NOTICE',
			    Params => [$current_nick,
				       "*** Your global nick in $network_name is currently '$global_nick'."]));
		}
	    } values %{$this->_runloop->networks};
	    
	    $send_message->(RPL_YOURHOST, "Your host is $prefix, running version ".::version());
	    if (!$this->_runloop->multi_server_mode_p) {
		# single server mode
		my $network = ($this->_runloop->networks_list)[0];

		if (defined $network) {
		    # send isupport
		    my $msg_tmpl = IRCMessage->new(
			Prefix => $prefix,
			Command => RPL_ISUPPORT,
			Params => [$current_nick],
		       );
		    # last param is reserved for 'are supported...'
		    my $max_params = IRCMessage::MAX_PARAMS - 1;
		    my @params = ();
		    my $length = 0;
		    my $flush_msg = sub {
			if (@params) {
			    my $msg = $msg_tmpl->clone;
			    $msg->push(@params);
			    $msg->push('are supported by this server');
			    $this->send_message($msg);
			}
			@params = ();
			$length = 0;
		    };
		    foreach my $key (keys %{$network->isupport}) {
			my $value = $network->isupport->{$key};
			my $str = length($value) ? ($key.'='.$value) : $key;
			$length += length($str) + 1; # $str and space
			# 余裕を見て400バイトを越えたら行を分ける。
			if ($length >= 400 || scalar(@params) >= $max_params) {
			    $flush_msg->();
			    $length = length($str);
			}
			push(@params, $str);
		    }
		    $flush_msg->();
		}
	    }
	    $send_message->(RPL_MOTDSTART, "- $prefix Message of the Day -");
	    foreach my $line (main::get_credit()) {
		$send_message->(RPL_MOTD, "- ".$line);
	    }
	    $send_message->(RPL_ENDOFMOTD, "End of MOTD command.");

	    # joinしている全てのチャンネルの情報をクライアント送る。
	    $this->inform_joinning_channels;

	    # 各モジュールにクライアント追加の通知を出す。
	    $this->_runloop->notify_modules('client_attached',$this);
	}
    }
    # ログイン作業中にクライアントから受け取ったいかなるメッセージもサーバーには送らない。
    return undef;
}

sub _receive_after_logged_in {
    my ($this,$msg) = @_;

    # ログイン中でない。
    my $command = $msg->command;

    if ($command eq 'NICK') {
	if (defined $msg->params) {
	    # 形式が正しい限りNICKには常に成功して、RunLoopのカレントnickが変更になる。
	    # ただしネットワーク名が明示されていた場合はカレントを変更しない。
	    my ($nick,undef,$specified) = Multicast::detach($msg->params->[0]);
	    if (Multicast::nick_p($nick)) {
		unless ($specified) {
		    #$this->send_message(
		    #    new IRCMessage(
		    #	Prefix => $this->fullname,
		    #	Command => 'NICK',
		    #	Param => $msg->params->[0]));
		    if ($this->_runloop->multi_server_mode_p) {
			$this->_runloop->broadcast_to_clients(
			    IRCMessage->new(
				Command => 'NICK',
				Param => $msg->param(0),
				Remarks => {'fill-prefix-when-sending-to-client' => 1}));

			$this->_runloop->set_current_nick($msg->params->[0]);
		    }
		}
	    } else {
		$this->send_message(
		    new IRCMessage(
			Prefix => $this->_runloop->sysmsg_prefix('system'),
			Command => ERR_ERRONEOUSNICKNAME,
			Params => [$this->_runloop->current_nick,
				   $msg->params->[0],
				   'Erroneous nickname']));
		# これは鯖に送らない。
		$msg = undef;
	    }
	} else {
	    $this->send_message(
		new IRCMessage(
		    Prefix => $this->_runloop->sysmsg_prefix('system'),
		    Command => ERR_NONICKNAMEGIVEN,
		    Params => [$this->_runloop->current_nick,
			       'No nickname given']));
	    # これは鯖に送らない。
	    $msg = undef;
	}
    }
    elsif ($command eq 'QUIT') {
	my $quit_message = $msg->param(0);
	$quit_message = '' unless defined $quit_message;

	$this->send_message(
	    new IRCMessage(Command => 'ERROR',
			   Param => 'Closing Link: '.$this->fullname('error').' ('.$quit_message.')'));
	$this->disconnect_after_writing;

	# 接続が切れた事にする。
	$this->_runloop->notify_modules('client_detached',$this);

	# これは鯖に送らない。
	$msg = undef;
    }
    else {
	$msg = LocalChannelManager->shared
	    ->message_arrived($msg, $this);
    }
    return $msg;
}

sub do_namreply {
    my ($this, $ch, $network, $max_length, $flush_func) = @_;

    $max_length = 400 if !defined $max_length;
    croak('$ch is not specified') if !defined $ch;
    croak('$network is not specified') if !defined $network;
    croak('$flush_func is not specified') if !defined $flush_func;
    my $global_to_local = sub {
	Multicast::global_to_local(shift, $network);
    };
    my $ch_property_char = do {
	if ($ch->switches('s')) {
	    '@';
	}
	elsif ($ch->switches('p')) {
	    '*';
	}
	else {
	    '=';
	}
    };
    # 余裕を見てnickの列挙部が $max_length(デフォルト:400) バイトを越えたら行を分ける。
    my $nick_enumeration = '';
    my $flush_enum_buffer = sub {
	if ($nick_enumeration ne '') {
	    $flush_func->(
		IRCMessage->new(
		    Prefix => $this->fullname,
		    Command => RPL_NAMREPLY,
		    Params => [$this->_runloop->current_nick,
			       $ch_property_char,
			       Multicast::attach_for_client($ch->name, $network->network_name),
			       $nick_enumeration]));
	    $nick_enumeration = '';
	}
    };
    my $append_to_enum_buffer = sub {
	my $nick_to_append = shift;
	if ($nick_enumeration eq '') {
	    $nick_enumeration = $nick_to_append;
	}
	else {
	    $nick_enumeration .= ' '.$nick_to_append;
	}
    };
    map {
	my $person = $_;
	my $mode_char = do {
	    if ($person->has_o) {
		'@';
	    }
	    elsif ($person->has_v) {
		'+';
	    }
	    else {
		'';
	    }
	};
	$append_to_enum_buffer->($mode_char . $global_to_local->($person->person->nick));
	if (length($nick_enumeration) > $max_length) {
	    $flush_enum_buffer->();
	}
    } values %{$ch->names};
    $flush_enum_buffer->();

    undef;
}

sub inform_joinning_channels {
    my $this = shift;
    my $local_nick = $this->_runloop->current_nick;

    my $send_channelinfo = sub {
	my ($network, $ch) = @_;
	my $ch_name = Multicast::attach_for_client($ch->name, $network->network_name);

	# まずJOIN
	$this->send_message(
	    IRCMessage->new(
		Prefix => $this->fullname,
		Command => 'JOIN',
		Param => $ch_name));
	# 次にRPL_TOPIC(あれば)
	if ($ch->topic ne '') {
	    $this->send_message(
		IRCMessage->new(
		    Prefix => $this->fullname,
		    Command => RPL_TOPIC,
		    Params => [$local_nick,$ch_name,$ch->topic]));
	}
	# 次にRPL_TOPICWHOTIME(あれば)
	if (defined($ch->topic_who)) {
	    $this->send_message(
		IRCMessage->new(
		    Prefix => $this->fullname,
		    Command => RPL_TOPICWHOTIME,
		    Params => [$local_nick,$ch_name,$ch->topic_who,$ch->topic_time]));
	}
	# 次にRPL_NAMREPLY
	my $flush_namreply = sub {
	    my $msg = shift;
	    $this->send_message($msg);
	};
	$this->do_namreply($ch, $network, undef, $flush_namreply);
	# 最後にRPL_ENDOFNAMES
	$this->send_message(
	    IRCMessage->new(
		Prefix => $this->fullname,
		Command => RPL_ENDOFNAMES,
		Params => [$local_nick,$ch_name,'End of NAMES list']));

	# channel-infoフックの引数は (IrcIO::Client, 送信用チャンネル名, ネットワーク, ChannelInfo)
	eval {
	    IrcIO::Client::HookTarget->shared->call(
		'channel-info', $this, $ch_name, $network, $ch);
	}; if ($@) {
	    # エラーメッセージは表示するが、送信処理は続ける
	    $this->_runloop->notify_error(__PACKAGE__." hook call error: $@");
	}
    };

    my %channels = map {
	my $network = $_;
	map {
	    my $ch = $_;
	    (Multicast::attach($ch->name, $network->network_name) =>
		    [$network, $ch]);
	} values %{$network->channels};
    } values %{$this->_runloop->networks};

    # Mask を使って、マッチしたものを出力
    foreach ($this->_conf_networks->
		 fixed_channels('block')->channel('all')) {
	my $mask = $_;
	foreach (keys %channels) {
	    my $ch_name = $_;
	    if (Mask::match($mask, $ch_name)) {
		$send_channelinfo->(@{$channels{$ch_name}});
		delete $channels{$ch_name};
	    }
	}
    }

    # のこりを出力
    foreach (values %channels) {
	$send_channelinfo->(@$_);
    }
}

# -----------------------------------------------------------------------------
# クライアントにチャンネル情報(JOIN,TOPIC,NAMES等)を渡した直後に呼ばれるフック。
# チャンネル名(multi server modeならネットワーク名付き)を引数として、
# チャンネル一つにつき一度ずつ呼ばれる。
#
# my $hook = IrcIO::Client::Hook->new(sub {
#     my $hook_itself = shift;
#     # 何らかの処理を行なう。
# })->install('channel-info'); # チャンネル情報転送時にこのフックを呼ぶ。
# -----------------------------------------------------------------------------
package IrcIO::Client::Hook;
use FunctionalVariable;
use base 'Hook';

our $HOOK_TARGET_NAME = 'IrcIO::Client::HookTarget';
our @HOOK_NAME_CANDIDATES = qw/channel-info/;
our $HOOK_NAME_DEFAULT = 'channel-info';
our $HOOK_TARGET_DEFAULT;
FunctionalVariable::tie(
    \$HOOK_TARGET_DEFAULT,
    FETCH => sub {
	IrcIO::Client::HookTarget->shared;
    },
   );

# -----------------------------------------------------------------------------
package IrcIO::Client::HookTarget;
use Hook;
our @ISA = 'HookTarget';
our $_shared;

sub shared {
    my $class = shift;
    if (!defined $_shared) {
	$_shared = bless {} => $class; # 繼承するなら問題になるが…
    }
    $_shared;
}

sub call {
    my ($this, $name, @args) = @_;
    $this->call_hooks($name, @args);
}

1;
