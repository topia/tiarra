# -----------------------------------------------------------------------------
# $Id: RunLoop.pm,v 1.47 2003/10/15 16:23:42 admin Exp $
# -----------------------------------------------------------------------------
# このクラスはTiarraのメインループを実装します。
# select()を実行し、サーバーやクライアントとのI/Oを行うのはこのクラスです。
# -----------------------------------------------------------------------------
# フック`before-select'及び`after-select'が使用可能です。
# これらのフックは、それぞれselect()実行直前と直後に呼ばれます。
# -----------------------------------------------------------------------------
package RunLoop;
use strict;
use warnings;
use UNIVERSAL;
use Carp;
use IO::Socket::INET;
use IO::Select;
use Configuration;
use IrcIO;
use IrcIO::Server;
use IrcIO::Client;
use Unicode::Japanese;
use ModuleManager;
use Multicast;
use Timer;
use ControlPort;
use Hook;
our @ISA = 'HookTarget';
our $_shared_instance;

BEGIN {
    # Time::HiResは使えるか？
    eval q{
        use Time::HiRes qw(time);
    }; if ($@) {
	# 使えない。
    }
}

*shared = \&shared_loop;
sub shared_loop {
    if (!defined $_shared_instance) {
	$_shared_instance = _new RunLoop;
    }
    $_shared_instance;
}

sub _new {
    my $class = shift;
    my $this = {
	# 受信用セレクタ。あらゆるソケットは常に受信の必要があるため、あらゆるソケットが登録されている。
	receive_selector => new IO::Select,

	# 送信用セレクタ。ソケットに対して送信すべきデータがある場合は限られていて、その場合にのみ登録されて終わり次第削除される。
	send_selector => new IO::Select,

	# Tiarraがリスニングしてクライアントを受け付けるためのソケット。IO::Socket。
	tiarra_server_socket => undef,

	# 現在のnick。全てのサーバーとクライアントの間で整合性を保ちつつnickを変更する手段を、RunLoopが用意する。
	current_nick => Configuration->shared_conf->general->nick,

	# 鯖から切断された時の動作。
	action_on_disconnected => do {
	    my $actions = {
		'part-and-join' => \&_action_part_and_join,
		'one-message' => \&_action_one_message,
		'message-for-each' => \&_action_message_for_each,
	    };
	    my $action_name = Configuration->shared_conf->networks->action_when_disconnected;
	    unless (defined $action_name) {
		$action_name = 'part-and-join';
	    }
	    my $act = $actions->{$action_name};
	    if (defined $act) {
		$act;
	    }
	    else {
		die "Unknown action specified as networks/action-when-disconnected: $action_name\n";
	    }
	},

	multi_server_mode => 1, # マルチサーバーモードに入っているか否か

	networks => {}, # ネットワーク名 → IrcIO::Server
	disconnected_networks => {}, # 切断されたネットワーク。
	clients => [], # 接続されている全てのクライアント IrcIO::Client

	timers => [], # インストールされている全てのTimer
	external_sockets => [], # インストールされている全てのExternalSocket
	#hooks_before_select => [], # インストールされている全てのbefore-selectフック
	#hooks_after_select => [], # インストールされている全てのafter-selectフック

	conf_reloaded_hook => undef, # この下でインストールするフック
    };
    bless $this, $class;

    $this->{conf_reloaded_hook} = Configuration::Hook->new(
	sub {
	    # マルチサーバーモードのOn/Offが変わったか？
	    my $old = $this->{multi_server_mode} ? 1 : 0;
	    my $new = Configuration->shared->networks->multi_server_mode ? 1 : 0;
	    if ($old != $new) {
		# 変わった
		$this->_multi_server_mode_changed;
	    }
	},
       )->install;

    $this;
}

sub DESTROY {
    my $this = shift;
    if (defined $this->{conf_reloaded_hook}) {
	$this->{conf_reloaded_hook}->uninstall;
    }
}

sub network {
    my ($this,$network_name) = @_;
    $this->{networks}->{$network_name};
}

sub networks {
    shift->{networks};
}

sub networks_list {
    values %{shift->{networks}};
}

sub clients {
    shift->{clients};
}

sub clients_list {
    @{shift->{clients}};
}

sub channel {
    # $ch_long: ネットワーク名修飾付きチャンネル名
    # 見付かったらChannelInfo、見付からなければundefを返す。
    my ($this,$ch_long) = @_;

    my ($ch_short,$net_name) = Multicast::detach($ch_long);
    my $network = $this->{networks}->{$net_name};
    if (!defined $network) {
	return undef;
    }

    $network->channel($ch_short);
}

sub current_nick {
    # クライアントから見た、現在のnick。
    # このnickは実際に使われているnickとは異なっている場合がある。
    # すなわち、希望のnickが既に使われていた場合である。
    shift->{current_nick};
}

sub set_current_nick {
    my ($this,$new_nick) = @_;
    $this->{current_nick} = $new_nick;
}

sub change_nick {
    my ($this,$new_nick) = @_;

    foreach my $io (values %{$this->{networks}}) {
	$io->send_message(
	    new IRCMessage(
		Command => 'NICK',
		Param => $new_nick));
    }
}

sub multi_server_mode_p {
    shift->{multi_server_mode};
}

sub find_io_with_socket {
    my ($this,$sock) = @_;
    # networksとclientsの中から指定されたソケットを持つIrcIOを探します。
    # 見付からなければundefを返します。
    foreach my $io (values %{$this->{networks}}) {
	return $io if $io->sock == $sock;
    }
    foreach my $io (@{$this->{clients}}) {
	return $io if $io->sock == $sock;
    }
    undef;
}

sub _multi_server_mode_changed {
    my $this = shift;
    # 一旦全てのチャンネルについてPARTを発行した後、
    # モードを変え接続中ネットワークを更新し、NICKとJOINを発行する。
    my $new = !$this->{multi_server_mode};

    foreach my $string (
	'Multi server mode *'.($new ? 'enabled' : 'disabled').'*',
	q{It looks as if you would part all channels, but it's just an illusion.}) {
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Command => 'NOTICE',
		Params => [$this->current_nick, $string]));
    }

    my $iterate = sub {
	my $func = shift;
	foreach my $network ($this->networks_list) {
	    foreach my $ch ($network->channels_list) {
		foreach my $client ($this->clients_list) {
		    $func->($network, $ch, $client);
		}
	    }
	}
    };

    $iterate->(
	sub {
	    my ($network, $ch, $client) = @_;
	    $client->send_message(
		IRCMessage->new(
		    Prefix => $client->fullname,
		    Command => 'PART',
		    Params => [
			do {
			    if ($new) {
				# これまではネットワーク名が付いていなかった。
				$ch->name;
			    }
			    else {
				scalar Multicast::attach(
				    $ch->name, $network->network_name);
			    }
			},
			'[Caused by Tiarra] Clients have to part all channels.',
		       ],
		   )
	       );
	}
       );
    $this->{multi_server_mode} = $new;
    $this->update_networks;
    my $global_nick = (($this->networks_list)[0])->current_nick;
    if ($global_nick ne $this->current_nick) {
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Command => 'NICK',
		Param => $global_nick,
		Remarks => {'fill-prefix-when-sending-to-client' => 1
			   }));

	$this->set_current_nick($global_nick);
    }
    foreach my $client ($this->clients_list) {
	$client->inform_joinning_channels;
    }
}

sub _update_send_selector {
    my $this = shift;
    # 送信する必要のあるIrcIOだけを抜き出し、そのソケットを送信セレクタに登録する。

    #my $add_or_remove = sub {
    #	my $io = shift;	
    #	my $action = ($io->need_to_send ? 'add' : 'remove');
    #	$this->{send_selector}->$action($io->sock);
    #};

    #foreach my $io (values %{$this->{networks}}) {
    #	$add_or_remove->($io);
    #}
    #foreach my $io (@{$this->{clients}}) {
    #	$add_or_remove->($io);
    #}

    # どうもこの動作が怪しい。無理に再利用しなくても良いような気がする。
    my $sel = $this->{send_selector} = IO::Select->new;
    foreach my $io (values %{$this->{networks}}) {
    	if ($io->need_to_send) {
	    $sel->add($io->sock);
	}
    }
    foreach my $io (@{$this->{clients}}) {
	if ($io->need_to_send) {
	    $sel->add($io->sock);
	}
    }
    foreach my $esock (@{$this->{external_sockets}}) {
	if ($esock->want_to_write) {
	    $sel->add($esock->sock);
	}
    }
}

sub _cleanup_closed_link {
    # networksとclientsの中から切断されたリンクを探し、
    # そのソケットをセレクタから外す。
    # networksならクライアントに然るべき通知をし、再接続するタイマーをインストールする。
    my $this = shift;

    my %networks_closed = ();
    while (my ($network_name,$io) = each %{$this->{networks}}) {
	$networks_closed{$network_name} = $io unless $io->connected;
    }
    my $do_update_networks = 0;
    while (my ($network_name,$io) = each %networks_closed) {
	# セレクタから外す。
	$this->{receive_selector}->remove($io->sock);
	$this->{send_selector}->remove($io->sock);
	# networksからは削除して、代わりにdisconnected_networksに入れる。
	delete $this->{networks}->{$network_name};
	$this->{disconnected_networks}->{$network_name} = $io;
	$do_update_networks = 1;
    }
    if ($do_update_networks) {
	Timer->new(
	    After => 3,
	    Code => sub {
		$this->update_networks;
	    },
	)->install($this);
    }

    for (my $i = 0; $i < @{$this->{clients}}; $i++) {
	my $io = $this->{clients}->[$i];
	unless ($io->connected) {
	    ::printmsg("Connection with ".$io->fullname." has been closed.");
	    $this->{receive_selector}->remove($io->sock);
	    splice @{$this->{clients}},$i,1;
	    $i--;
	}
    }
}

sub _action_part_and_join {
    # $event: 'connected' 若しくは 'disconnected'
    # 今のところ、このメソッドはconfからの削除による切断時にも流用されている。
    my ($this,$network,$event) = @_;
    my $network_name = $network->network_name;
    if ($event eq 'connected') {
	$this->_rejoin_all_channels($network);
    }
    elsif ($event eq 'disconnected') {
	foreach my $client (@{$this->clients}) {
	    foreach my $ch (values %{$network->channels}) {
		$client->send_message(
		    IRCMessage->new(
			Prefix => $client->fullname,
			Command => 'PART',
			Params => [Multicast::attach($ch->name,$network_name),
				   $network->host." closed the connection."]));
	    }
	}
    }
}
sub _action_one_message {
    my ($this,$network,$event) = @_;
    my $network_name = $network->network_name;
    if ($event eq 'connected') {
	$this->_rejoin_all_channels($network);
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Command => 'NOTICE',
		Params => [$this->current_nick,
			   '*** The connection has been revived between '.$network->network_name.'.']));
    }
    elsif ($event eq 'disconnected') {
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Command => 'NOTICE',
		Params => [$this->current_nick,
			   '*** The connection has been broken between '.$network->network_name.'.']));
    }
}
sub _action_message_for_each {
    my ($this,$network,$event) = @_;
    my $network_name = $network->network_name;
    if ($event eq 'connected') {
	$this->_rejoin_all_channels($network);

	my $msg = IRCMessage->new(
	    Prefix => 'Tiarra',
	    Command => 'NOTICE',
	    Params => ['', # チャンネル名は後で設定。
		       '*** The connection has been revived between '.$network->network_name.'.']);
	foreach my $ch (values %{$network->channels}) {
	    $msg->param(0,Multicast::attach($ch->name,$network_name));
	    $this->broadcast_to_clients($msg);
	}
    }
    elsif ($event eq 'disconnected') {
	my $msg = IRCMessage->new(
	    Prefix => 'Tiarra',
	    Command => 'NOTICE',
	    Params => ['', # チャンネル名は後で設定。
		       '*** The connection has been broken between '.$network->network_name.'.']);
	foreach my $ch (values %{$network->channels}) {
	    $msg->param(0,Multicast::attach($ch->name,$network_name));
	    $this->broadcast_to_clients($msg);
	}
    }
}
sub _rejoin_all_channels {
    my ($this,$network) = @_;
    # networkが記憶している全てのチャンネルにJOINする。
    # そもそもJOINしていないチャンネルは通常IrcIO::Serverは記憶していないが、
    # サーバーから切断された時だけは例外である。
    # 尚、註釈kicked-outが付けられているチャンネルにはJOINしない。
    my @ch_with_key; # パスワードを持ったチャンネルの配列。要素は["チャンネル名","パスワード"]
    my @ch_without_key; # パスワードを持たないチャンネルの配列。要素は"チャンネル名"
    foreach my $ch (values %{$network->channels}) {
	next if $ch->remarks('kicked-out');

	my $password = $ch->parameters('k');
	if (defined $password && $password ne '') {
	    push @ch_with_key,[$ch->name,$password];
	}
	else {
	    push @ch_without_key,$ch->name;
	}
    }
    # JOIN実行
    my ($buf_ch,$buf_key) = ('','');
    my $buf_flush = sub {
	return if ($buf_ch eq '');
	my $params = do {
	    if ($buf_key eq '') {
		[$buf_ch];
	    }
	    else {
		[$buf_ch,$buf_key];
	    }
	};
	$network->send_message(
	    IRCMessage->new(
		Command => 'JOIN',
		Params => $params));
	$buf_ch = $buf_key = '';
    };
    my $buf_put = sub {
	my ($ch,$key) = @_;
	$buf_ch .= ($buf_ch eq '' ? $ch : ",$ch");
	$buf_key .= ($buf_key eq '' ? $key : ",$key") if defined $key;
	if (length($buf_ch) + length($buf_key) > 400) {
	    # 400バイトを越えたら自動でフラッシュする。
	    $buf_flush->();
	}
    };
    # パスワード付きのチャンネルにJOIN
    foreach (@ch_with_key) {
	$buf_put->($_->[0],$_->[1]);
    }
    $buf_flush->();
    # パスワード無しのチャンネルにJOIN
    foreach (@ch_without_key) {
	$buf_put->($_);
    }
    $buf_flush->();
}

sub update_networks {
    my $this = shift;
    # networks/nameを読み、その中にまだ接続していないネットワークがあればそれを接続し、
    # 接続中のネットワークで既にnetworks/nameに列挙されていないものがあればそれを切断する。
    my $general_conf = Configuration::shared_conf->get('general');
    my @net_names = Configuration::shared_conf->get('networks')->name('all');
    my $do_update_networks_after = 0; # 秒数
    my $do_cleanup_closed_links_after = 0;
    my $host_tried = {}; # {接続を試みたホスト名 => 1}

    # マルチサーバーモードでなければ、@net_namesの要素は一つに限られるべき。
    # そうでなければ警告を出し、先頭のものだけを残して後は捨てる。
    if (!$this->{multi_server_mode} && @net_names > 1) {
	$this->notify_warn("In single server mode, Tiarra will connect to just a one network; `".
			     $net_names[0]."'");
	@net_names = $net_names[0];
    }

    foreach my $net_name (@net_names) {
	my $net_conf = Configuration::shared_conf->get($net_name);

	if (defined($_ = $this->{networks}->{$net_name})) {
	    # 既に接続されている。
	    # このサーバーについての設定が変わっていたら、一旦接続を切る。
	    if (!$net_conf->equals($_->config)) {
		$_->disconnect;
		$do_cleanup_closed_links_after = 1;
	    }
	    next;
	}

	# 切断されたネットワークかも知れない。
	my $network = $this->{disconnected_networks}->{$net_name};
	eval {
	    if (defined $network) {
		# 再接続
		$network->reload_config;
		$network->connect;
		# disconnected_networksからnetworksへ移す。
		$this->{networks}->{$net_name} = $network;
		delete $this->{disconnected_networks}->{$net_name};
	    }
	    else {
		if ($host_tried->{$net_conf->host}) {
		    $do_update_networks_after = 15;
		    $network = undef;
		}
		else {
		    $host_tried->{$net_conf->host} = 1;

		    $network = IrcIO::Server->new($net_name);
		    $this->{networks}->{$net_name} = $network; # networksに登録
		}
	    }
	    if (defined $network) {
		$this->{receive_selector}->add($network->sock); # 受信セレクタに登録
	    }
	}; if ($@) {
	    print $@;
	    # タイマー作り直し。
	    $do_update_networks_after = 3;
	}
    }

    if ($do_update_networks_after) {
	Timer->new(
	    After => $do_update_networks_after,
	    Code => sub {
		$this->update_networks;
	    },
	)->install($this);
    }

    if ($do_cleanup_closed_links_after) {
	$this->_cleanup_closed_link;
    }

    my @nets_to_disconnect;
    my @nets_to_forget;
    my $is_there_in_net_names = sub {
	my $network_name = shift;
	# このネットワークは@net_names内に列挙されているか？
	foreach my $enumerated_net (@net_names) {
	    return 1 if $network_name eq $enumerated_net;
	}
	return 0;
    };
    # networksから不要なネットワークを削除
    while (my ($net_name,$server) = each %{$this->{networks}}) {
	# 入っていなかったらselectorから外して切断する。
	unless ($is_there_in_net_names->($net_name)) {
	    push @nets_to_disconnect,$net_name;
	}
    }
    foreach my $net_name (@nets_to_disconnect) {
	my $server = $this->{networks}->{$net_name};
	$this->disconnect_server($server);
	# 手動で全チャンネルへのPARTを送信
	$this->_action_part_and_join($server, 'disconnected');
    }
    # disconnected_networksから不要なネットワークを削除
    while (my ($net_name,$server) = each %{$this->{disconnected_networks}}) {
	# 入っていなかったら忘れる。
	unless ($is_there_in_net_names->($net_name)) {
	    push @nets_to_forget,$net_name;
	}
    }
    foreach (@nets_to_forget) {
	delete $this->{disconnected_networks}->{$_};
    }
}

sub disconnect_server {
    # 指定されたサーバーとの接続を切る。
    # fdの監視をやめてしまうので、この後IrcIO::Serverのreceiveはもう呼ばれない事に注意。
    # $server: IrcIO::Server
    my ($this,$server) = @_;
    $this->{receive_selector}->remove($server->sock);
    $this->{send_selector}->remove($server->sock);
    $server->disconnect;
    delete $this->{networks}->{$server->network_name};
}

sub reconnected_server {
    my ($this,$network) = @_;
    # 再接続だった場合の処理
    $this->{action_on_disconnected}->($this,$network,'connected');
}

sub disconnected_server {
    my ($this,$network) = @_;
    $this->{action_on_disconnected}->($this,$network,'disconnected');
}

sub install_socket {
    my ($this,$esock) = @_;
    if (!defined $esock) {
	croak "RunLoop->install_socket, Arg[1] was undef.\n";
    }

    push @{$this->{external_sockets}},$esock;
    $this->{receive_selector}->add($esock->sock); # 受信セレクタに登録
    undef;
}

sub uninstall_socket {
    my ($this,$esock) = @_;
    if (!defined $esock) {
	croak "RunLoop->uninstall_socket, Arg[1] was undef.\n";
    }

    for (my $i = 0; $i < @{$this->{external_sockets}}; $i++) {
	if ($this->{external_sockets}->[$i] == $esock) {
	    splice @{$this->{external_sockets}},$i,1;
	    $this->{receive_selector}->remove($esock->sock); # 受信セレクタから登録解除
	    $i--;
	}
    }
    $this;
}

sub find_esock_with_socket {
    my ($this,$sock) = @_;
    foreach my $esock (@{$this->{external_sockets}}) {
	if ($esock->sock == $sock) {
	    return $esock;
	}
    }
    undef;
}

=pod
sub install_hook {
    my ($this,$hook_name,$hook) = @_;
    my $array = do {
	if ($hook_name eq 'before-select') {
	    $this->{hooks_before_select};
	}
	elsif ($hook_name eq 'after-select') {
	    $this->{hooks_after_select};
	}
	else {
	    croak "RunLoop->install_hook, hook name '$hook_name' is invalid.\n";
	}
    };
    push @$array,$hook;
    $this;
}

sub uninstall_hook {
    my ($this,$hook_name,$hook) = @_;
    my $array = do {
	if ($hook_name eq 'before-select') {
	    $this->{hooks_before_select};
	}
	elsif ($hook_name eq 'after-select') {
	    $this->{hooks_after_select};
	}
	else {
	    croak "RunLoop->uninstall_hook, hook name '$hook_name' is invalid.\n";
	}
    };
    @$array = grep {
	$_ != $hook;
    } @$array;
    $this;
}

sub call_hooks {
    my ($this,$hook_name) = @_;
    my $array = do {
	if ($hook_name eq 'before-select') {
	    $this->{hooks_before_select};
	}
	elsif ($hook_name eq 'after-select') {
	    $this->{hooks_after_select};
	}
	else {
	    croak "RunLoop->call_hooks, hook name '$hook_name' is invalid.\n";
	}
    };
    foreach my $hook (@$array) {
	eval {
	    $hook->call;
	}; if ($@) {
	    die "RunLoop: Exception in calling hook.\n$@\n";
	}
    }
}

=cut

sub install_timer {
    my ($this,$timer) = @_;
    push @{$this->{timers}},$timer;
    $this;
}

sub uninstall_timer {
    my ($this,$timer) = @_;
    for (my $i = 0; $i < scalar(@{$this->{timers}}); $i++) {
	if ($this->{timers}->[$i] == $timer) {
	    splice @{$this->{timers}},$i,1;
	    $i--;
	}
    }
    $this;
}

sub get_earliest_timer {
    # 登録されている中で最も起動時間の早いタイマーを返す。
    # タイマーが一つも無ければundefを返す。
    my $this = shift;
    return undef if (scalar(@{$this->{timers}}) == 0);

    my $eariest = $this->{timers}->[0];
    foreach my $timer (@{$this->{timers}}) {
	if ($timer->time_to_fire < $eariest->time_to_fire) {
	    $eariest = $timer;
	}
    }
    return $eariest;
}

sub _execute_all_timers_to_fire {
    my $this = shift;

    # executeすべきタイマーを集める
    my @timers_to_execute = ();
    foreach my $timer (@{$this->{timers}}) {
	push @timers_to_execute,$timer if $timer->time_to_fire <= time;
    }

    # 実行
    foreach my $timer (@timers_to_execute) {
	$timer->execute;
    }
}

sub run {
    my $this = shift;
    my $conf_general = Configuration::shared_conf->get('general');

    # マルチサーバーモード
    $this->{multi_server_mode} =
      Configuration::shared->networks->multi_server_mode;

    # まずはtiarra-portをlistenするソケットを作る。
    # 省略されていたらlistenしない。
    # この値が数値でなかったらdie。
    my $tiarra_port = $conf_general->tiarra_port;
    if (defined $tiarra_port) {
	if ($tiarra_port !~ /^\d+/) {
	    die "general/tiarra-port must be integer. '$tiarra_port' is invalid.\n";
	}

	# v4とv6の何れを使うか？
	my @serversocket_args = (
	    LocalPort => $tiarra_port,
	    Proto => 'tcp',
	    Reuse => 1,
	    Listen => 0);
	my $ip_version = $conf_general->tiarra_ip_version || 'v4';
	my $tiarra_server_socket = do {
	    if ($ip_version eq 'v4') {
		my $bind_addr = $conf_general->tiarra_ipv4_bind_addr;
		my @args = do {
		    if (defined $bind_addr) {
			@serversocket_args,LocalAddr => $bind_addr;
		    }
		    else {
			@serversocket_args;
		    }
		};
		IO::Socket::INET->new(@args);
	    }
	    elsif ($ip_version eq 'v6') {
		if (!&::ipv6_enabled) {
		    ::printmsg("*** IPv6 support is not enabled ***");
		    ::printmsg("Set general/tiarra-ip-version to 'v4' or install Socket6.pm if possible.\n");
		    die;
		}
		my $bind_addr = $conf_general->tiarra_ipv6_bind_addr;
		my @args = do {
		    if (defined $bind_addr) {
			@serversocket_args,LocalAddr => $bind_addr;
		    }
		    else {
			@serversocket_args;
		    }
		};
		IO::Socket::INET6->new(@args);
	    }
	    else {
		die "Unknown ip-version '$ip_version' specified as general/tiarra-ip-version.\n";
	    }
	};
	if (defined $tiarra_server_socket) {
	    $tiarra_server_socket->autoflush(1);
	    $this->{tiarra_server_socket} = $tiarra_server_socket;
	    $this->{receive_selector}->add($tiarra_server_socket); # セレクタに登録。
	    main::printmsg("Tiarra started listening ${tiarra_port}/tcp. (IP$ip_version)");
	}
	else {
	    # ソケット作れなかった。
	    die "Couldn't make server socket to listen ${tiarra_port}/tcp. (IP$ip_version)\n";
	}
    }

    # 鯖に接続
    $this->update_networks;

    # 3分毎に全ての鯖にPINGを送るタイマーをインストール。
    # これはtcp接続の切断に気付かない事があるため。
    # 応答のPONGは捨てる。このためにPONG破棄カウンタをインクリメントする。
    # PONG破棄カウンタはIrcIO::Serverのremarkで、キーは'pong-drop-counter'
    Timer->new(
	Interval => 3 * 60,
	Code => sub {
	    foreach my $network (values %{$this->{networks}}) {
		$network->send_message(
		    IRCMessage->new(
			Command => 'PING',
			Param => $network->host));

		my $cntr = $network->remark('pong-drop-counter');
		if (defined $cntr) {
		    $cntr++;
		}
		else {
		    $cntr = 1;
		}
		$network->remark('pong-drop-counter',$cntr);
	    }
	},
	Repeat => 1,
    )->install;

    # control-socket-nameが指定されていたら、ControlPortを開く。
    if ($conf_general->control_socket_name) {
	eval {
	    ControlPort->new($conf_general->control_socket_name);
	}; if ($@) {
	    ::printmsg($@);
	}
    }

    my $zerotime = {
	limit => 100,
	minimum_to_reset => 2,
	interval => 10,
	
	count => 0,
	last_warned => 0,
    };
    my $zerotime_warn = sub {
	my $elapsed = shift;
	
	if ($elapsed == 0) {
	    $zerotime->{count}++;
	    if ($zerotime->{count} >= $zerotime->{limit}) {
		$zerotime->{count} = 0;

		if ($zerotime->{last_warned} + $zerotime->{interval} < CORE::time) {
		    $zerotime->{last_warned} = CORE::time;

		    $this->notify_warn("Tiarra seems to be slowing down your system!");
		}
	    }
	}
	elsif ($elapsed < $zerotime->{minimum_to_reset}) {
	    $zerotime->{count} = 0;
	}
    };
    
    while (1) {
	# 処理の流れ
	#
	# 書きこみ可能なソケットを集めて、必要があれば書き込む。
	# 次に読み込み可能なソケットを集めて、(読む必要は常にあるので)読む。
	# 読んだ場合は通常IRCMessageの配列が返ってくるので、
	# 必要な全てのプラグインに順番に通す。(プラグインはフィルターとして考える。)
	# それがサーバーから読んだメッセージだったなら、プラグインを通した後、接続されている全てのクライアントにそれを転送する。
	# クライアントが一つも接続されていなければ、そのIRCMessage群は捨てる。
	# クライアントから読んだメッセージだったなら、プラグインを通した後、渡すべきサーバーに転送する。
	#
	# selectにおけるタイムアウトは次のようにする。
	# (普段は何かしら登録されていると思うが)タイマーが一つも登録されていなければ、タイムアウトはundefである。すなわちタイムアウトしない。
	# タイマーが一つでも登録されていた場合は、全てのタイマーの中で最も発動時間が早いものを調べ、
	# それが発動するまでの時間をselectのタイムアウト時間とする。
	my $timeout = undef;
	my $eariest_timer = $this->get_earliest_timer;
	if (defined $eariest_timer) {
	    $timeout = $eariest_timer->time_to_fire - time;
	}
	if ($timeout < 0) {
	    $timeout = 0;
	}

	$this->_update_send_selector; # 書き込むべきデータがあるソケットだけをsend_selectorに登録する。そうでないソケットは除外。
	# select前フックを呼ぶ
	$this->call_hooks('before-select');
	# select実行
	my $time_before_select = CORE::time;
	my ($readable_socks,$writable_socks) =
	    IO::Select->select($this->{receive_selector},$this->{send_selector},undef,$timeout);
	$zerotime_warn->(CORE::time - $time_before_select);
	# select後フックを呼ぶ
	$this->call_hooks('after-select');

	foreach my $sock ($this->{receive_selector}->can_read(0)) {
	    if (defined $this->{tiarra_server_socket} &&
		$sock == $this->{tiarra_server_socket}) {

		# クライアントからの新規の接続
		my $new_sock = $sock->accept;
		if (defined $new_sock) {
		    eval {
			my $client = new IrcIO::Client($new_sock);
			push @{$this->{clients}},$client;
			$this->{receive_selector}->add($new_sock);
		    }; if ($@) {
			print "$@\n";
		    }
		}
	    }
	    elsif (my $io = $this->find_io_with_socket($sock)) {
		eval {
		    $io->receive;

		    while (1) {
			my $msg = eval {
			    $io->pop_queue;
			}; if ($@) {
			    if (ref($@) && UNIVERSAL::isa($@,'QueueIsEmptyException')) {
				last;
			    }
			    else {
				::printmsg($@);
				last;
			    }
			}
			
			if (!defined $msg) {
			    next;
			}
			
			if ($io->isa("IrcIO::Server")) {
			    # このメッセージがPONGであればpong-drop-counterを見る。
			    if ($msg->command eq 'PONG') {
				my $cntr = $io->remark('pong-drop-counter');
				if (defined $cntr && $cntr > 0) {
				    # このPONGは捨てる。
				    $cntr--;
				    $io->remark('pong-drop-counter',$cntr);
				    next;
				}
			    }

			    # メッセージをMulticastのフィルタに通す。
			    my @received_messages =
				Multicast::from_server_to_client($msg,$io);
			    # モジュールを通す。
			    my $filtered_messages = $this->_apply_filters(\@received_messages,$io);
			    # シングルサーバーモードなら、ネットワーク名を取り外す。
			    if (!$this->{multi_server_mode}) {
				@$filtered_messages = map {
				    Multicast::detach_network_name($_, $io);
				} @$filtered_messages;
			    }
			    # 註釈do-not-send-to-clients => 1が付いていないメッセージを各クライアントに送る。
			    $this->broadcast_to_clients(
				grep {
				    !($_->remark('do-not-send-to-clients'));
				} @$filtered_messages);
			}
			else {
			    # モジュールを通す。
			    my $filtered_messages = $this->_apply_filters([$msg],$io);		    
			    # 対象となる鯖に送る。
			    # NOTICE及びPRIVMSGは返答が返ってこないので、同時にこれ以外のクライアントに転送する。
			    # 註釈do-not-send-to-servers => 1が付いているメッセージはここで破棄する。
			    foreach my $msg (@$filtered_messages) {
				if ($msg->remark('do-not-send-to-servers')) {
				    next;
				}
				
				my $cmd = $msg->command;
				if ($cmd eq 'PRIVMSG' || $cmd eq 'NOTICE') {
				    my $new_msg = undef; # 本当に必要になったら作る。
				    foreach my $client (@{$this->{clients}}) {
					if ($client != $io) {
					    unless (defined $new_msg) {
						# まだ作ってなかった
						$new_msg = $msg->clone;
						$new_msg->prefix($io->fullname);
					    }
					    $client->send_message($new_msg);
					}
				    }
				}
				
				Multicast::from_client_to_server($msg,$io);
			    }
			}
		    }
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	    elsif (my $esock = $this->find_esock_with_socket($sock)) {
		eval {
		    $esock->read;
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	}
	
	foreach my $sock ($this->{send_selector}->can_write(0)) {
	    if (my $io = $this->find_io_with_socket($sock)) {
		next unless $io->need_to_send;

		eval {
		    $io->send;
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	    elsif (my $esock = $this->find_esock_with_socket($sock)) {
		next unless $esock->want_to_write;

		eval {
		    $esock->write;
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	}

	# 切断されたソケットを探して、然るべき処理を行なう。
	$this->_cleanup_closed_link;
	
	# 発動すべき全てのタイマーを発動させる
	$this->_execute_all_timers_to_fire;
    }
}

sub broadcast_to_clients {
    # IRCMessageをログイン中でない全てのクライアントに送信する。
    # fill-prefix-when-sending-to-clientという註釈が付いていたら、
    # Prefixをそのクライアントのfullnameに設定する。
    my ($this,@messages) = @_;
    foreach my $client (@{$this->{clients}}) {
	next if $client->logging_in;
	
	foreach my $msg (@messages) {
	    if ($msg->remark('fill-prefix-when-sending-to-client')) {
		$msg = $msg->clone;
		$msg->prefix($client->fullname);
	    }
	    $client->send_message($msg);
	}
    }
}

sub broadcast_to_servers {
    # IRCメッセージを全てのサーバーに送信する。
    my ($this,@messages) = @_;
    foreach my $network (values %{$this->{networks}}) {
	foreach my $msg (@messages) {
	    $network->send_message($msg);
	}
    }
}

sub notify_modules {
    my ($this,$method,@args) = @_;
    my $mods = ModuleManager->shared->get_modules;
    foreach my $mod (@$mods) {
	eval {
	    $mod->$method(@args);
	}; if ($@) {
	    $this->notify_error("Exception in ".ref($mod).".\n".
				"when calling $method.\n".
				"   $@");
	}
    }
}

sub _apply_filters {
    # src_messagesは変更しない。
    my ($this,$src_messages,$sender) = @_;
    my $mods = ModuleManager->shared_manager->get_modules;

    my $source = $src_messages;
    my $filtered = [];
    foreach my $mod (@$mods) {
	# sourceが空だったらここで終わり。
	if (scalar(@$source) == 0) {
	    return $source;
	}
	
	foreach my $src (@$source) {
	    my @reply = ();
	    # 実行
	    eval {
		@reply = $mod->message_arrived($src,$sender);
		
	    }; if ($@) {
		$this->notify_error("Exception in ".ref($mod).".\n".
				    "The message was '".$src->serialize."'.\n".
				    "   $@");
	    }
	    
	    if (defined $reply[0]) {
		# 値が一つ以上返ってきた。
		# 全てIRCMessageのオブジェクトなら良いが、そうでなければエラー。
		foreach my $msg_reply (@reply) {
		    unless (UNIVERSAL::isa($msg_reply,'IRCMessage')) {
			$this->notify_error("Reply of ".ref($mod)."::message_arived contains illegal value.\n".
					    "It is ".ref($msg_reply).".");
			return $source;
		    }
		}
		
		# これをfilteredに追加。
		push @$filtered,@reply;
	    }	    
	}

	# 次のsourceはfilteredに。filteredは空の配列に。
	$source = $filtered;
	$filtered = [];
    }
    return $source;
}

sub notify_error {
    my ($this,$str) = @_;
    $this->notify_msg("===== ERROR =====\n$str");
}
sub notify_warn {
    my ($this,$str) = @_;
    $this->notify_msg(":: WARNING :: $str");
}
sub notify_msg {
    # 渡された文字列をSTDOUTに出力すると同時に全クライアントにNOTICEする。
    # 改行コードLFで行を分割する。
    # 文字コードはUTF-8でなければならない。
    my ($this,$str) = @_;
    $str =~ s/\n+$//s; # 末尾のLFは消去

    # STDOUTへ
    ::printmsg($str);

    # クライアントへ
    my $needed_sending = Configuration->shared_conf->general->notice_error_messages;
    if ($needed_sending) {
	my $client_charset = Configuration->shared_conf->general->client_out_encoding;
	if (@{$this->clients} > 0) {
	    $this->broadcast_to_clients(
		map {
		    IRCMessage->new(
			Command => 'NOTICE',
			Params => [$this->current_nick,
				   "*** $_"]);
		} split /\n/,$str
	    );
	}
    }
}

# -----------------------------------------------------------------------------
# RunLoopが一回実行される度に呼ばれるフック。
#
# my $hook = RunLoop::Hook->new(sub {
#     my $hook_itself = shift;
#     # 何らかの処理を行なう。
# })->install('after-select'); # select実行直後にこのフックを呼ぶ。
# -----------------------------------------------------------------------------
package RunLoop::Hook;
#use strict;
#use warnings;
#use Carp;
use FunctionalVariable;
use base 'Hook';

our $HOOK_TARGET_NAME = 'RunLoop';
our @HOOK_NAME_CANDIDATES = qw/before-select after-select/;
our $HOOK_NAME_DEFAULT = 'after-select';
our $HOOK_TARGET_DEFAULT;
FunctionalVariable::tie(
    \$HOOK_TARGET_DEFAULT,
    FETCH => sub {
	RunLoop->shared;
    },
   );

=pod
sub new {
    my ($class,$code) = @_;
    my $this = {
	runloop => undef,
	hook_name => undef,

	code => $code,
    };

    if (!defined $code) {
	croak "RunLoop::Hook->new, Arg[0] was undef.\n";
    }
    elsif (ref($code) ne 'CODE') {
	croak "RunLoop::Hook->new, Arg[0] was bad type.\n";
    }

    bless $this,$class;
}

sub install {
    # $hook_name: 'before-select' または 'after-select'。
    #             それぞれselect直前か直後に呼ばれる。省略されたりundefが渡された場合はafter-selectになる。
    # $runloop:   インストールするRunLoop。省略された場合はRunLoop->shared。
    my ($this,$hook_name,$runloop) = @_;
    $hook_name = 'after-select' if !defined $hook_name;
    $runloop = RunLoop->shared if !defined $runloop;

    if (defined $this->{runloop}) {
	croak "RunLoop::Hook->install, this hook is already installed.\n";
    }

    $this->{runloop} = $runloop;
    $this->{hook_name} = $hook_name;
    $runloop->install_hook($hook_name,$this);

    $this;
}

sub uninstall {
    my $this = shift;

    $this->{runloop}->uninstall_hook($this->{hook_name},$this);
    $this->{runloop} = undef;
    $this->{hook_name} = undef;

    $this;
}

sub call {
    my $this = shift;

    my ($caller_pkg) = caller;
    if ($caller_pkg->isa('RunLoop')) {
	$this->{code}->($this);
    }
    else {
	croak "Only RunLoop can call RunLoop::Hook->call\n";
    }
}

=cut

1;
