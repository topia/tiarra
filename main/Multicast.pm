# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# サーバーからクライアントにメッセージが流れるとき、このクラスはフィルタとして
# ネットワーク名を付加します。
# クライアントからサーバーに流れるとき、このクラスはネットワーク名をパースして
# 送るべき各サーバーに送ります。
# ローカル←→グローバルnickの変換もここで行います。
# -----------------------------------------------------------------------------
package Multicast;
use strict;
use warnings;
use Configuration;
use Carp;
use NumericReply;
use base qw(Tiarra::IRC::NewMessageMixin);
my $runloop = undef; # デフォルトのRunLoopのキャッシュ。
my $separator = ''; # セパレータ記号のキャッシュ。これらはcast_messageが呼ばれる度に更新される。

sub _ISON_from_client {
    # nickをネットワーク毎に分類する。
    my ($message, $sender) = @_;
    my $networks = classify($message->params);

    while (my ($network_name,$params) = each %$networks) {
	my $network = $runloop->networks->{$network_name};
	my $msg = $message->clone;
	@{$msg->params} = map { local_to_global($_,$network) } @$params;
	$msg->remark('real-generator',  __PACKAGE__);
	forward_to_server($msg, $network_name);
    }
}

sub _INVITE_from_server {
    my ($message,$sender) = @_;
    # nickはそのまま。チャンネルにはネットワーク名を付ける。
    $message->nick(global_to_local($message->nick,$sender));
    $message->params->[0] = global_to_local($message->params->[0],$sender);
    $message->params->[1] = attach($message->params->[1],$sender->network_name);
    return $message;
}
sub _INVITE_from_client {
    my ($message,$sender) = @_;
    # nickはパースするだけで捨てる。チャンネルのパース結果を見る。
    my $to = '';
    ($message->params->[0]) = detach($message->params->[0]);
    ($message->params->[1],$to) = detach($message->params->[1]);
    $message->params->[0] = local_to_global($message->params->[0],$to); # 自分をINVITEする事など無いので必要は無いが…
    forward_to_server($message,$to);
}

sub _JOIN_from_server {
    my ($message,$sender) = @_;
    # カンマで区切られ複数のチャンネルが指定されていたとしても
    # それらの全てにネットワーク名を付加する。(まさか無いだろうが。)
    $message->nick(global_to_local($message->nick,$sender));

    my @channels = split(/,/,$message->params->[0]);
    my $n_channels = @channels;
    for (my $i = 0; $i < $n_channels; $i++) {
	$channels[$i] = attach($channels[$i],$sender->network_name);
    }
    $message->params->[0] = join(',',@channels);
    return $message;
}
sub _JOIN_from_client {
    my ($message,$sender) = @_;
    # パスワードの部分は弄らず、ネットワーク名をパースして取り除く。
    # 各チャンネルをネットワーク毎に分類する。
    if ($message->params->[0] eq '0') {
	# 0は特殊。
	# 全てのサーバーにJOIN 0を送る。
	distribute_to_servers($message->clone);
    }
    else {
	my @targets = split(/,/,$message->params->[0]);
	my $networks = classify(\@targets);
	while (my ($network_name,$channels) = each %$networks) {
	    $message->params->[0] = join(',',@$channels);
	    forward_to_server($message,$network_name);
	}
    }
}

sub _KICK_from_server {
    my ($message,$sender) = @_;
    # チャンネル名にだけ、ネットワーク名を付加する。
    $message->nick(global_to_local($message->nick,$sender));
    $message->params->[0] = attach($message->params->[0],$sender->network_name);
    $message->params->[1] = global_to_local($message->params->[1],$sender);
    return $message;
}
sub _KICK_from_client {
    my ($message,$sender) = @_;
    my @channels = split(/,/,$message->params->[0]);
    my @nicks = split(/,/,$message->params->[1]);
    if (scalar(@channels) == scalar(@nicks)) {
	# チャンネルとnickが一対一で対応する。
	# チャンネルのネットワーク名を使用し、nickのネットワーク名は捨てる。
	for (my $i = 0; $i < @channels; $i++) {
	    my ($raw_channel,$to) = detach($channels[$i]);
	    my ($raw_nick) = detach($nicks[$i]);

	    $message->params->[0] = $raw_channel;
	    $message->params->[1] = local_to_global($raw_nick,$runloop->networks->{$to});
	    forward_to_server($message,$to);
	}
    }
    elsif (@channels == 1) {
	# 一つのチャンネルから複数のnickを蹴り出す。
	# チャンネルのネットワーク名を使用し、nickのネットワーク名は捨てる。
	my ($raw_channel,$to) = detach($channels[0]);
	my $network = $runloop->networks->{$to};
	$message->params->[0] = $raw_channel;

	foreach my $nick (@nicks) {
	    my ($raw_nick) = detach($nick);
	    $message->params->[1] = local_to_global($raw_nick,$network);

	    forward_to_server($message,$to);
	}
    }
}

sub _LIST_from_client {
    my ($message,$sender) = @_;
    # チャンネルのネットワーク名で分類。
    if (defined $message->params->[0]) {
	my @targets = split(/,/,$message->params->[0]);
	my $networks = classify(\@targets);

	while (my ($network_name,$channels) = each %$networks) {
	    $message->params->[0] = join(',',@$channels);
	    forward_to_server($message,$network_name);
	}
    }
    else {
	forward_to_server($message, $runloop->default_network);
    }
}

sub _MODE_from_server {
    my ($message,$sender) = @_;
    $message->nick(global_to_local($message->nick,$sender));
    @{$message->params} = map( global_to_local($_,$sender) ,@{$message->params});

    my $target = $message->params->[0];
    if (channel_p($target)) {
	# nick(つまり自分)の場合はそのままクライアントに配布。
	# この場合はチャンネルなので、ネットワーク名を付加。
	$message->params->[0] = attach($target,$sender->network_name);
    }
    return $message;
}

sub _MODE_from_client {
    my ($message,$sender) = @_;
    my $to;
    ($message->params->[0],$to) = detach($message->params->[0]);

    my $network = $runloop->networks->{$to};
    @{$message->params} = map( local_to_global($_,$network) ,@{$message->params});

    forward_to_server($message,$to);
}

sub _TOPIC_from_server {
    my ($message,$sender) = @_;
    $message->nick(global_to_local($message->nick,$sender));

    my $target = $message->params->[0];
    if (channel_p($target)) {
	# nick(つまり自分)の場合はそのままクライアントに配布。
	# この場合はチャンネルなので、ネットワーク名を付加。
	$message->params->[0] = attach($target,$sender->network_name);
    }
    return $message;
}

sub _TOPIC_from_client {
    my ($message,$sender) = @_;
    my $to;
    ($message->params->[0],$to) = detach($message->params->[0]);

    forward_to_server($message,$to);
}

sub _NICK_from_client {
    # ネットワーク名が指定されていたら、その鯖にのみNICKを送信。
    # そうでなければ全ての鯖に送る。
    my ($message,$sender) = @_;
    my $to;
    my $specified;
    ($message->params->[0],$to,$specified) = detach($message->params->[0]);

    if ($specified) {
	forward_to_server($message,$to);
    }
    else {
	distribute_to_servers($message);
    }
}

sub _NJOIN_from_server {
    my ($message,$sender) = @_;
    $message->param(0,attach($message->param(0),$sender->network_name));
    $message->param(1,
		    join(',',
			 map{ s/^([\@+]*)(.+)$/$1.global_to_local($2,$sender)/e; $_; } split(/,/,$message->param(1))));
    $message;
}

sub _NOTICE_from_server {
    my ($message,$sender) = @_;
    $message->nick(global_to_local($message->nick,$sender));

    my $target = $message->params->[0];
    if (channel_p($target)) {
	# この場合はチャンネルなので、ネットワーク名を付加。
	$message->params->[0] = attach($target,$sender->network_name);
    } else {
	# nick(つまり自分)の場合は global_to_local を行う。
	$message->param(0, global_to_local($message->param(0),$sender));
    }
    return $message;
}

sub _WHOIS_from_client {
    my ($message,$sender) = @_;
    my $to;
    ($message->params->[0],$to) = detach($message->params->[0]);

    my $network = $runloop->networks->{$to};
    $message->params->[0] = local_to_global($message->params->[0],$runloop->networks->{$to});

    # ローカルnickと送信先のグローバルnickが異なっていたら、その旨をクライアントに報告する。
    # ただしWHOISの対象が自分だった場合のみ。
    my $local_nick = $runloop->current_nick;
    my $global_nick = $network->current_nick;
    if (($message->command eq 'WHOIS' || $message->command eq 'WHO') &&
	$message->param(0) eq $global_nick &&
	$local_nick ne $global_nick) {
	$sender->send_message(
	    __PACKAGE__->construct_irc_message(
		Prefix => $runloop->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [$local_nick,
			   "*** Your global nick in $to is currently '$global_nick'."]));
    }

    forward_to_server($message,$to);
}

sub _RPL_USERHOST {
    my ($message,$sender) = @_;
    $message->params->[1] =~ s/^([^*=]+)(.+)$/global_to_local($1,$sender).$2/e;
    $message;
}

sub _RPL_ISON {
    my ($message,$sender) = @_;
    $message->params->[1] =
	join(' ',
	     map {
		 global_to_local($_,$sender);
	     } split / /,$message->params->[1]);
    $message;
}

sub _RPL_INVITING {
    my ($message,$sender) = @_;
    $message->param(1,attach($message->param(1),$sender->network_name));
    $message->param(2,global_to_local($message->param(2),$sender));
    $message;
}

sub _RPL_WHOREPLY {
    my ($message, $sender) = @_;
    $message->param(1,attach($message->param(1),$sender->network_name));
    $message->param(5,global_to_local($message->param(5),$sender));
    $message;
}

sub _RPL_NAMREPLY {
    my ($message,$sender) = @_;
    $message->param(2,attach($message->param(2),$sender->network_name));
    $message->params->[3] =
	join(' ',
	     map {
		 s/^([\@+]*)(.+)$/$1.global_to_local($2,$sender)/e; $_;
	     } split / /,$message->params->[3]);
    $message;
}

sub _attach_RPL_WHOISCHANNELS {
    my ($message,$sender) = @_;
    $message->param(1,global_to_local($message->param(1),$sender));
    $message->params->[2] =
	join(' ',
	     map {
		 s/^([\@+]*)(.+)$/$1.attach($2, $sender->network_name)/e; $_;
	     } split / /,$message->params->[2]);
    $message;
}

sub _detach_RPL_WHOISCHANNELS {
    my ($message,$sender) = @_;
    $message->params->[2] =
	join(' ',
	     map {
		 s/^([\@+]*)(.+)$/$1.detach($2)/e; $_;
	     } split / /,$message->params->[2]);
    $message;
}

my $g2l_cache = {};
sub _gen_g2l_translator {
    my $index = shift;

    unless (exists $g2l_cache->{$index}) {
	$g2l_cache->{$index} = sub {
	    my ($message,$sender) = @_;
	    $message->params->[$index] = global_to_local($message->params->[$index],$sender);
	    $message;
	};
    }
    $g2l_cache->{$index};
}

my $attach_cache = {};
sub _gen_attach_translator {
    my $index = shift;

    unless (exists $attach_cache->{$index}) {
	$attach_cache->{$index} = sub {
	    my ($message,$sender) = @_;
	    $message->param($index,attach($message->param($index),$sender->network_name));
	    $message;
	};
    }
    $attach_cache->{$index};
}

my $detach_cache = {};
sub _gen_detach_translator {
    my $index = shift;

    if (!exists $detach_cache->{$index}) {
	$detach_cache->{$index} = sub {
	    my ($message, $sender) = @_;
	    $message->param(
		$index,
		detach($message->param($index)));
	    forward_to_server($message, $sender);
	};
    }
    $detach_cache->{$index};
}

my $server_sent = {
    'INVITE' => \&_INVITE_from_server,
    'JOIN' => \&_JOIN_from_server,
    'KICK' => \&_KICK_from_server,
    'MODE' => \&_MODE_from_server,
    'NICK' => undef, # 本体は鯖からのNICKを弄らない。これを見て情報を更新するのはIrcIO::Serverである。
    'NOTICE' => \&_NOTICE_from_server, # Prefixを弄るとすれば、それはモジュールの役目。
    'PART' => \&_JOIN_from_server, # JOINと同じ処理で良い。
    'PING' => undef,
    'PRIVMSG' => \&_NOTICE_from_server, # NOTICEと同じ処理で良い。
    'QUIT' => undef, # QUITしたのが自分だったら捨てる、といった処理はIrcIO::Serverが行なう。
    'SQUERY' => \&_MODE_from_server, # 多分これは鯖からも来るだろうが、良く分からない。
    'TOPIC' => \&_TOPIC_from_server,
    'NJOIN' => \&_NJOIN_from_server,
    (RPL_UNIQOPIS) => \&_RPL_INVITING, # UNIQOPIS (INVITINGと同じ処理)
    # TRACE系のリプライはTiarraは関知しない。少なくとも今のところは。
    do {
	my $sub = _gen_g2l_translator(1);
	map {
	    (NumericReply::fetch_number($_), $sub)
	} (map {"RPL_$_"}
	       ((map {"WHOIS$_"} qw(USER SERVER OPERATOR IDLE)),
		(map {"ENDOF$_"} qw(WHOIS WHOWAS)),
		qw(WHOWASUSER AWAY)))},
    do {
	my $sub = _gen_attach_translator(1);
	map {
	    (NumericReply::fetch_number($_), $sub);
	} ((map {"RPL_$_"}
		((map { ("$_", "ENDOF$_"); } map {$_.'LIST'}
		      qw(INVITE EXCEPT BAN REOP)),
		 (map {"ENDOF$_"} qw(WHO NAMES)),
		 qw(LIST CHANNELMODEIS NOTOPIC TOPIC TOPICWHOTIME),
		 qw(CREATIONTIME))),
	   ((map {"ERR_$_"}
		 (qw(TOOMANYCHANNELS NOTONCHANNEL NOSUCHCHANNEL UNAVAILRESOURCE)))))},
    do {
	no strict 'refs';
	map {
	    my $funcname = "_$_";
	    (NumericReply::fetch_number($_), \&$funcname)
	} (map {"RPL_$_"}
	       qw(USERHOST ISON INVITING WHOREPLY NAMREPLY))},
    do {
	no strict 'refs';
	map {
	    my $funcname = "_attach_$_";
	    (NumericReply::fetch_number($_), \&$funcname)
	} (map {"RPL_$_"}
	       qw(WHOISCHANNELS))},
};

my $client_sent = {
    'ISON' => \&_ISON_from_client,
    'INVITE' => \&_INVITE_from_client,
    'JOIN' => \&_JOIN_from_client,
    'KICK' => \&_KICK_from_client,
    'LIST' => \&_LIST_from_client,
    'MODE' => \&_MODE_from_client,
    'NAMES' => \&_LIST_from_client, # LISTと同じ処理で良い。
    'NICK' => \&_NICK_from_client,
    'NOTICE' => \&_LIST_from_client, # LISTと同じ処理で良い。
    #'MODE' => \&_MODE_from_client, # MODEと同じ処理で良い。
    #↑意図不明。
    'PART' => \&_LIST_from_client, # LISTと同じ処理で良い。
    'PASS' => \&_MODE_from_client, # これを真面目に処理しないとSERVICE出来ない。MODEと同じで良い。
    'PONG' => undef,
    'PRIVMSG' => \&_LIST_from_client, # NOTICEと同じ処理で良い。
    'QUIT' => undef, # QUITをトラップするのはIrcIO::Client。つまりここには決してQUITは流れて来ない。
    'SERVICE' => \&_MODE_from_client, # 良く分からないが、とりあえずMODEと同じにする。
    'SERVLIST' => \&_MODE_from_client, # これも良く分からない。MODEと同じに。
    'SERVSET' => \&_MODE_from_client, # これも。
    'SQUERY' => \&_MODE_from_client, # これも
    'STATS' => \&_MODE_from_client, # サーバ名はうしろにつくのでこれはよくないかも
    'SUMMON' => \&_MODE_from_client,
    'TIME' => \&_MODE_from_client,
    'TOPIC' => \&_TOPIC_from_client,
    'TRACE' => \&_MODE_from_client,
    'UMODE' => \&_MODE_from_client,
    'USER' => undef,
    'USERHOST' => \&_ISON_from_client,
    'USERS' => \&_MODE_from_client,
    'VERSION' => \&_MODE_from_client,
    'ADMIN' => \&_MODE_from_client,
    'WHO' => \&_WHOIS_from_client,
    'WHOIS' => \&_WHOIS_from_client,
    'WHOWAS' => \&_WHOIS_from_client,
    'CLOSE' => \&_MODE_from_client,
    'CONNECT' => \&_MODE_from_client, # 無理があるが…
    'DIE' => \&_MODE_from_client,
    'KILL' => \&_MODE_from_client,
    'REHASH' => \&_MODE_from_client,
    'RESTART' => \&_MODE_from_client,
    'SQUIT' => \&_MODE_from_client,
    'ERROR' => undef,
    'NJOIN' => undef, # クライアントからNJOINを発行するのは勿論無意味。
    'RECONNECT' => undef,
    'SERVER' => undef,
    'WALLOPS' => \&_MODE_from_client, # クライアントからWALLOPSを発行出来るのかどうかは知らないが…
    # 以下リプライ。これはdetach_network_nameの為だけにある。
    (RPL_NAMREPLY) => _gen_detach_translator(2),
    do {
	my $sub = _gen_detach_translator(1);
	map {
	    (NumericReply::fetch_number($_), $sub)
	} ((map {"RPL_$_"}
		((map { ("$_", "ENDOF$_"); } qw(INVITELIST EXCEPTLIST BANLIST)),
		 (map {"ENDOF$_"} qw(WHO NAMES)),
		 qw(LIST CHANNELMODEIS NOTOPIC TOPIC TOPICWHOTIME),
		 qw(CREATIONTIME INVITING UNIQOPIS WHOREPLY))),
	   (map {"ERR_$_"}
		 (qw(TOOMANYCHANNELS NOTONCHANNEL NOSUCHCHANNEL UNAVAILRESOURCE))))},
    do {
	no strict 'refs';
	map {
	    my $funcname = "_detach_$_";
	    (NumericReply::fetch_number($_), \&$funcname)
	} (map {"RPL_$_"}
	       qw(WHOISCHANNELS))},
};


sub _update_cache {
    $separator = Configuration->shared_conf->
	networks->channel_network_separator;
    $runloop = RunLoop->shared_loop;
}

sub from_server_to_client {
    no warnings;
    my ($message, $sender) = @_;
    &_update_cache;
    # server -> clientの流れでは、一つのメッセージが複数に分割される事は無い。
    # この関数は一つのTiarra::IRC::Messageを返す。

    if ($message->command =~ /^\d+$/) {
	# ニューメリックリプライの0番目のパラメタは全てnick。
	$message->params->[0] = global_to_local($message->params->[0],$sender);
    }

    eval {
	# フィルタが無かったり、フィルタの実行中に例外が起こったりした場合はそのまま返す。
	$message = $server_sent->{$message->command}->($message, $sender);
    }; if ($@) {
	$message->nick(global_to_local($message->nick,$sender));
    }
    return $message;
}

sub from_client_to_server {
    no warnings;
    my ($message, $sender) = @_;
    &_update_cache;
    # client -> serverの流れでは、一つのメッセージが複数に分割される事がある。
    # この関数はメッセージを鯖に直接送り、戻り値は返さない。
    eval {
	$client_sent->{$message->command}->($message, $sender);
    }; if ($@) {
	forward_to_server($message,$runloop->default_network);
    }
}

sub detach_network_name {
    no strict;
    no warnings;
    my ($message, $sender) = @_;
    &_update_cache;
    my $result;
    local $hijack_forward_to_server = sub {
	my ($msg, $network_name) = @_;
	$result = $msg;
    };
    local $hijack_local_to_global = 1;
    eval {
	$client_sent->{$message->command}->($message, $sender);
    }; if ( !defined $result ) {
	$hijack_forward_to_server->($message, $runloop->default_network);
    }
    $result;
}

*detatch = \&detach; # 勘違いしていた。detachが正しい。
sub detach {
    # 戻り値: (セパレータ前の文字列,ネットワーク名,ネットワーク名が明示されたかどうか)
    # ただしスカラーコンテクストではセパレータ前の文字列のみを返す。
    my $str = shift;

    if (!defined $str) {
	croak "Arg[0] was undef.\n";
    }
    elsif (ref($str) ne '') {
	croak "Arg[0] was ref.\n";
    }

    my ($pkg_caller) = caller;
    _update_cache() unless $pkg_caller->isa('Multicast');

    my @result;
    if ((my $sep_index = index($str,$separator)) != -1) {
	my $before_sep = substr($str,0,$sep_index);
	my $after_sep = substr($str,$sep_index+length($separator));
	if ((my $colon_pos = index($after_sep,':')) != -1) {
	    # #さいたま@taiyou:*.jp  →  #さいたま:*.jp + taiyou
	    @result = ($before_sep.substr($after_sep,$colon_pos),
		       substr($after_sep,0,$colon_pos),
		       1);
	}
	else {
	    # #さいたま@taiyou  →  #さいたま + taiyou
	    @result = ($before_sep,$after_sep,1);
	}
    }
    else {
	@result = ($str,$runloop->default_network,undef);
    }
    return wantarray ? @result : $result[0];
}

sub detach_for_client {
    my ($str) = @_;

    if (!$runloop->multi_server_mode_p) {
	detach($str);
    } else {
	$str;
    }
}

sub attach {
    # $strはChannelInfoのオブジェクトでも良い。
    # $network_nameは省略可能。IrcIO::Serverのオブジェクトでも良い。
    my ($str,$network_name) = @_;
    if (ref($str) eq 'ChannelInfo') {
	$str = $str->name;
    }
    if (ref($network_name) eq 'IrcIO::Server') {
	$network_name = $network_name->network_name;
    }

    if (!defined $str) {
	croak "Arg[0] was undef.\n";
    }
    elsif (ref($str) ne '') {
	croak "Arg[0] was ref.\n";
    }

    my ($pkg_caller) = caller;
    _update_cache() unless $pkg_caller->isa('Multicast');

    $network_name = $runloop->default_network if $network_name eq '';
    if ((my $pos_colon = index($str,':')) != -1) {
	# #さいたま:*.jp  →  #さいたま@taiyou:*.jp
	$str =~ s/:/$separator.$network_name.':'/e;
    }
    else {
	# #さいたま  →  #さいたま@taiyou
	$str .= $separator.$network_name;
    }
    $str;
}

sub attach_for_client {
    my ($str, $network_name) = @_;

    if ($runloop->multi_server_mode_p) {
	attach($str, $network_name);
    } else {
	$str;
    }
}

sub classify {
    # array: 配列への参照
    # 戻り値: ネットワーク名→パース後の文字列を並べた配列への参照
    my $array = shift;
    my $networks = {};
    foreach my $target (@$array) {
	my ($str,$network_name) = detach($target);
	if (defined $networks->{$network_name}) {
	    push @{$networks->{$network_name}},$str;
	}
	else {
	    # 初めて現われたネットワークである。
	    $networks->{$network_name} = [$str];
	}
    }
    return $networks;
}

sub forward_to_server {
    # この関数は、動的スコープに置かれた変数
    # $hijack_forward_to_serverが定義されていたら、
    # それを関数リファと見做してサーバーに送る代わりに呼ぶ。
    no strict;
    my ($msg, $network_name) = @_;

    if (defined $hijack_forward_to_server) {
	#::printmsg("forward_to_server HIJACKED");
	$hijack_forward_to_server->($msg, $network_name);
    }
    else {
	my $io = $runloop->network($network_name);
	if (defined $io && $io->logged_in) {
	    $io->send_message($msg);
	}
    }
}

sub distribute_to_servers {
    no strict;
    my $msg = shift;
    foreach my $server ($runloop->networks_list) {
	if (defined $hijack_forward_to_server) {
	    #::printmsg("forward_to_server HIJACKED");
	    $hijack_forward_to_server->($msg, $server->network_name);
	}
	else {
	    $server->send_message($msg);
	}
    }
}

sub nick_p {
    # 文字列がnickとして許される形式であるかどうかを真偽値で返す。
    # これはクライアントで送るのを許されているか返すだけであって、
    # サーバから送られてくる nick の判定に使ってはいけない。
    my $str = detach(shift);
    my $nicklen = shift;
    return undef unless length($str) &&
	(!defined $nicklen || (length($str) <= $nicklen));

    # and irc2.11 permits specially '0'.
    my $first_char = '[a-zA-Z_\[\]\\\`\^\{\}\|]';
    my $remaining_char = '[0-9a-zA-Z_\-\[\]\\\`\^\{\}\|]';
    return ($str =~ /^${first_char}${remaining_char}*$/ || $str eq '0');
}

sub channel_p {
    # 文字列がchannelとして許される形式であるかどうかを真偽値で返す。
    my $str = detach(shift);
    return undef unless length($str);
    my $chantypes = shift || '#&+!';

    my $first_char = "[\Q$chantypes\E]";
    my $suffix_spec = '(?::[a-z*.]+)?';
    return $str =~ /^${first_char}.*${suffix_spec}$/
}

sub local_to_global {
    # この関数は、動的スコープに置かれた変数
    # $hijack_local_to_globalが定義されていたら、
    # 何も変更せずに返す。
    no strict;
    my ($str, $server) = @_;
    if (defined $hijack_local_to_global) {
	$str;
    }
    else {
	if (defined($str) && $str eq $runloop->current_nick) {
	    $server->current_nick;
	}
	else {
	    $str;
	}
    }
}

sub global_to_local {
    my ($str,$server) = @_;
    if (defined($str) && $str eq $server->current_nick) {
	return $runloop->current_nick;
    }
    else {
	return $str;
    }
}

sub lc {
    # IRC方式で、大文字を小文字に変換する。
    my $str = shift;
    # {}|は[]\の小文字である。気違いじみている!
    $str =~ tr/A-Z[]\\/a-z{}|/;
    $str;
}

sub uc {
    # IRC方式で、小文字を大文字に変換する。
    my $str = shift;
    $str =~ tr/a-z{}|/A-Z[]\\/;
    $str;
}

1;
