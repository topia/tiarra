# -----------------------------------------------------------------------------
# $Id: Client.pm,v 1.21 2003/09/26 12:07:13 topia Exp $
# -----------------------------------------------------------------------------
# IrcIO::Clientはクライアントからの接続を受け、
# IRCメッセージをやり取りするクラスです。
# -----------------------------------------------------------------------------
package IrcIO::Client;
use strict;
use warnings;
use Carp;
use base qw(IrcIO);
use Net::hostent;
use Crypt;
use Configuration;
use Multicast;
use Mask;
use LocalChannelManager;

use SelfLoader;
SelfLoader->load_stubs; # このクラスには親クラスがあるから。(SelfLoaderのpodを参照)
1;
__DATA__

sub new {
    my ($class,$sock) = @_;
    my $obj = $class->SUPER::new;
    $obj->{sock} = $sock;
    $obj->{connected} = 1;
    $obj->{client_host} = do {
	my $hostent = Net::hostent::gethost($sock->peerhost); # 逆引き
	defined $hostent ? $hostent->name : $sock->peerhost;
    };
    $obj->{pass_received} = ''; # クライアントから受け取ったパスワード
    $obj->{nick} = ''; # ログイン時にクライアントから受け取ったnick。変更されない。
    $obj->{username} = ''; # 同username
    $obj->{logging_in} = 1; # ログイン中なら1
    $obj->{options} = {}; # クライアントが接続時に$key=value$で指定したオプション。

    # このホストからの接続は許可されているか？
    my $allowed_host = Configuration->shared_conf->general->client_allowed;
    if (defined $allowed_host) {
	unless (Mask::match($allowed_host,$obj->{client_host})) {
	    # マッチしないのでdie。
	    die "One client at ".$obj->{client_host}." connected to me, but the host is not allowed.\n";
	}
    }
    ::printmsg("One client at ".$obj->{client_host}." connected to me.");
    $obj;
}

sub logging_in {
    shift->{logging_in};
}

sub fullname {
    # このクライアントをtiarraから見たnick!username@userhostの形式で表現する。
    my ($this,$type) = @_;
    if (defined $type && $type eq 'error') {
	RunLoop->shared_loop->current_nick.'['.$this->{username}.'@'.$this->{client_host}.']';
    }
    else {
	RunLoop->shared_loop->current_nick.'!'.$this->{username}.'@'.$this->{client_host};
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

sub send_message {
    my ($this,$msg) = @_;

    # 各モジュールに通知
    RunLoop->shared->notify_modules('notification_of_message_io',$msg,$this,'out');

    $this->SUPER::send_message(
	$msg,
	$this->option('encoding') || Configuration->shared->general->client_out_encoding);
}

sub receive {
    my ($this) = shift;
    $this->SUPER::receive(
	$this->option('encoding') || Configuration->shared->general->client_in_encoding);

    # 接続が切れたら、各モジュールへ通知
    if (!$this->connected) {
	RunLoop->shared->notify_modules('client_detached',$this);
    }
}

sub pop_queue {
    my $this = shift;
    my $msg = $this->SUPER::pop_queue;

    # クライアントがログイン中なら、ログインを受け付ける。
    if (defined $msg) {
	# 各モジュールに通知
	RunLoop->shared->notify_modules('notification_of_message_io',$msg,$this,'in');

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
	my $valid_password = Configuration->shared_conf->general->tiarra_password;
	if (defined $valid_password && $valid_password ne '' &&
	    ! Crypt::check($this->{pass_received},$valid_password)) {
	    # パスワードが正しくない。
	    ::printmsg("Refused login of ".$this->fullname_from_client." because of bad password.");

	    $this->send_message(
		new IRCMessage(Prefix => 'tiarra',
			       Command => '464',
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
		new IRCMessage(Prefix => 'tiarra',
			       Command => '001',
			       Params => [$this->{nick},'Welcome to the Internet Relay Network '.$this->fullname_from_client]));

	    my $current_nick = RunLoop->shared_loop->current_nick;
	    if ($this->{nick} ne $current_nick) {
		# クライアントが送ってきたnickとローカルのnickが食い違っているので正しいnickを教える。
		$this->send_message(
		    new IRCMessage(Prefix => $this->fullname_from_client,
				   Command => 'NICK',
				   Param => $current_nick));
	    }

	    map {
		# ローカルnickとグローバルnickが食い違っていたらその旨を伝える。
		my $network_name = $_->network_name;
		my $global_nick = $_->current_nick;
		if ($global_nick ne $current_nick) {
		    $this->send_message(
			new IRCMessage(Prefix => 'tiarra',
				       Command => 'NOTICE',
				       Params => [$current_nick,
						  "*** Your global nick in $network_name is currently '$global_nick'."]));
		}
	    } values %{RunLoop->shared_loop->networks};

	    foreach my $line (main::get_credit()) {
		$this->send_message(
		    new IRCMessage(Prefix => 'tiarra',
				   Command => '002',
				   Params => [$current_nick,$line]));
	    }

	    # joinしている全てのチャンネルの情報をクライアント送る。
	    $this->inform_joinning_channels;

	    # 各モジュールにクライアント追加の通知を出す。
	    RunLoop->shared->notify_modules('client_attached',$this);
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
		    if (RunLoop->shared->multi_server_mode_p) {
			RunLoop->shared->broadcast_to_clients(
			    IRCMessage->new(
				Command => 'NICK',
				Param => $msg->param(0),
				Remarks => {'fill-prefix-when-sending-to-client' => 1}));

			RunLoop->shared_loop->set_current_nick($msg->params->[0]);
		    }
		}
	    } else {
		$this->send_message(
		    new IRCMessage(
			Prefix => 'tiarra',
			Command => '432',
			Params => [RunLoop->shared_loop->current_nick,
				   $msg->params->[0],
				   'Erroneous nickname']));
		# これは鯖に送らない。
		$msg = undef;
	    }
	} else {
	    $this->send_message(
		new IRCMessage(
		    Prefix => 'tiarra',
		    Command => '431',
		    Params => [RunLoop->shared_loop->current_nick,
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
	RunLoop->shared->notify_modules('client_detached',$this);

	# これは鯖に送らない。
	$msg = undef;
    }
    else {
	$msg = LocalChannelManager->shared
	    ->message_arrived($msg, $this);
    }
    return $msg;
}

sub inform_joinning_channels {
    my $this = shift;
    my $multi = RunLoop->shared->multi_server_mode_p;
    my $local_nick = RunLoop->shared_loop->current_nick;
    map {
	my $network = $_;
	my $global_nick = $network->current_nick;
	my $global_to_local = sub {
	    $_[0] eq $global_nick ? $local_nick : $_[0];
	};

	map {
	    my $ch = $_;
	    my $ch_name = do {
		if ($multi) {
		    Multicast::attach($ch->name, $network->network_name);
		}
		else {
		    $ch->name;
		}
	    };

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
			Command => '332',
			Params => [$local_nick,$ch_name,$ch->topic]));
	    }
	    # 次にRPL_TOPICWHOTIME(あれば)
	    if (defined($ch->topic_who)) {
		$this->send_message(
		    IRCMessage->new(
			Prefix => $this->fullname,
			Command => '333',
			Params => [$local_nick,$ch_name,$ch->topic_who,$ch->topic_time]));
	    }
	    # 次にRPL_NAMREPLY
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
	    # 余裕を見てnickの列挙部が400バイトを越えたら行を分ける。
	    my $nick_enumeration = '';
	    my $flush_enum_buffer = sub {
		if ($nick_enumeration ne '') {
		    $this->send_message(
			IRCMessage->new(
			    Prefix => $this->fullname,
			    Command => '353',
			    Params => [$local_nick,
				       $ch_property_char,
				       $ch_name,
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
		if (length($nick_enumeration) > 400) {
		    $flush_enum_buffer->();
		}
	    } values %{$ch->names};
	    $flush_enum_buffer->();
	    # 最後にRPL_ENDOFNAMES
	    $this->send_message(
		IRCMessage->new(
		    Prefix => $this->fullname,
		    Command => '366',
		    Params => [$local_nick,$ch_name,'End of NAMES list']));
	} values %{$network->channels};
    } values %{RunLoop->shared_loop->networks};
}

1;
