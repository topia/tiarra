# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Log::Channel;
use strict;
use warnings;
use IO::File;
use File::Spec;
use Unicode::Japanese;
use base qw(Module);
use Module::Use qw(Tools::DateConvert Log::Logger);
use Tools::DateConvert;
use Log::Logger;
use ControlPort;
use Mask;
use Multicast;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{channels} = []; # 要素は[ディレクトリ名,マスク]
    $this->{matching_cache} = {}; # <チャンネル名,ファイル名>
    $this->{filehandle_cache} = {}; # <チャンネル名,[ファイルパス,IO::File]>
    $this->{sync_command} = do {
	my $sync = $this->config->sync;
	if (defined $sync) {
	    uc $sync;
	}
	else {
	    undef;
	}
    };
    $this->{distinguish_myself} = do {
	my $conf_val = $this->config->distinguish_myself;
	if (defined $conf_val) {
	    $conf_val;
	}
	else {
	    1;
	}
    };
    $this->{logger} =
	Log::Logger->new(
	    sub {
		$this->_search_and_write(@_);
	    },
	    $this,
	    'S_PRIVMSG','C_PRIVMSG','S_NOTICE','C_NOTICE');

    $this->_init;
}

sub _init {
    my $this = shift;
    foreach ($this->config->channel('all')) {
	my ($dirname,$mask) = split /\s+/;
	if (!defined($dirname) || $dirname eq '' ||
	    !defined($mask) || $mask eq '') {
	    die 'Illegal definition in '.__PACKAGE__."/channel : $_\n";
	}
	push @{$this->{channels}},[$dirname,$mask];
    }

    $this;
}

sub sync {
    my $this = shift;
    $this->flush_all_file_handles;
    RunLoop->shared->notify_msg("Channel logs synchronized.");
}

sub control_requested {
    my ($this,$request) = @_;
    if ($request->ID eq 'synchronize') {
	$this->sync;
	ControlPort::Reply->new(204,'No Content');
    }
    else {
	die "Log::Channel received control request of unsupported ID ".$request->ID."\n";
    }
}

sub message_arrived {
    my ($this,$message,$sender) = @_;

    # syncは有効で、クライアントから受け取ったメッセージであり、かつ今回のコマンドがsyncに一致しているか？
    if (defined $this->{sync_command} &&
	$sender->isa('IrcIO::Client') &&
	$message->command eq $this->{sync_command}) {
	# 開いているファイルを全てflush。
	# 他のモジュールも同じコマンドでsyncするかも知れないので、
	# do-not-send-to-servers => 1は設定するが
	# メッセージ自体は破棄してしまわない。
	$this->sync;
	$message->remark('do-not-send-to-servers',1);
	return $message;
    }

    # __PACKAGE__/commandにマッチするか？
    if (Mask::match(lc($this->config->command || '*'),lc($message->command))) {
	$this->{logger}->log($message,$sender);
    }

    $message;
}

*S_PRIVMSG = \&PRIVMSG_or_NOTICE;
*S_NOTICE = \&PRIVMSG_or_NOTICE;
*C_PRIVMSG = \&PRIVMSG_or_NOTICE;
*C_NOTICE = \&PRIVMSG_or_NOTICE;
sub PRIVMSG_or_NOTICE {
    my ($this,$msg,$sender) = @_;
    my $target = Multicast::detatch($msg->param(0));
    my $is_priv = Multicast::nick_p($target);
    my $cmd = $msg->command;

    my $line = do {
	if ($is_priv) {
	    # privの時は自分と相手を必ず区別する。
	    if ($sender->isa('IrcIO::Client')) {
		sprintf(
		    $cmd eq 'PRIVMSG' ? '>%s< %s' : ')%s( %s',
		    $msg->param(0),
		    $msg->param(1));
	    }
	    else {
		sprintf(
		    $cmd eq 'PRIVMSG' ? '-%s- %s' : '=%s= %s',
		    $msg->nick || $sender->current_nick,
		    $msg->param(1));
	    }
	}
	else {
	    my $format = do {
		if ($this->{distinguish_myself} && $sender->isa('IrcIO::Client')) {
		    $cmd eq 'PRIVMSG' ? '>%s:%s< %s' : ')%s:%s( %s';
		}
		else {
		    $cmd eq 'PRIVMSG' ? '<%s:%s> %s' : '(%s:%s) %s';
		}
	    };
	    my $nick = do {
		if ($sender->isa('IrcIO::Client')) {
		    RunLoop->shared_loop->network(
		      (Multicast::detatch($msg->param(0)))[1])
			->current_nick;
		}
		else {
		    $msg->nick || $sender->current_nick;
		}
	    };
	    sprintf $format,$msg->param(0),$nick,$msg->param(1);
	}
    };

    [$is_priv ? 'priv' : $msg->param(0),$line];
}

sub _channel_match {
    # 指定されたチャンネル名にマッチするログ保存ファイルのパターンを定義から探す。
    # 一つもマッチしなければundefを返す。
    # このメソッドは検索結果を$this->{matching_cache}に保存して、後に再利用する。
    my ($this,$channel) = @_;

    my $cached = $this->{matching_cache}->{$channel};
    if (defined $cached) {
	if ($cached eq '') {
	    # マッチするエントリは存在しない、という結果がキャッシュされている。
	    return undef;
	}
	else {
	    return $cached;
	}
    }

    foreach my $ch (@{$this->{channels}}) {
	if (Mask::match($ch->[1],$channel)) {
	    # マッチした。
	    my $fname_format = $this->config->filename || '%Y.%m.%d.txt';
	    my $fpath_format = $ch->[0]."/$fname_format";

	    $this->{matching_cache}->{$channel} = $fpath_format;
	    return $fpath_format;
	}
    }
    $this->{matching_cache}->{$channel} = '';
    undef;
}

sub _search_and_write {
    my ($this,$channel,$line) = @_;
    my $dirname = $this->_channel_match($channel);
    if (defined $dirname) {
	$this->_write($channel,$dirname,$line);
    }
}

sub _write {
    # 指定されたログファイルにヘッダ付きで追記する。
    # ディレクトリ名の日付のマクロは置換される。
    my ($this,$channel,$abstract_fpath,$line) = @_;
    my $concrete_fpath = do {
	my $basedir = $this->config->directory;
	if (defined $basedir) {
	    Tools::DateConvert::replace("$basedir/$abstract_fpath");
	}
	else {
	    Tools::DateConvert::replace($abstract_fpath);
	}
    };
    my $header = Tools::DateConvert::replace(
	$this->config->header || '%H:%M'
    );
    my $mode = do {
	my $mode_conf = $this->config->mode;
	if (defined $mode_conf) {
	    oct('0'.$mode_conf);
	}
	else {
	    0600;
	}
    };
    # ディレクトリが無ければ作る。
    $this->mkdirs($concrete_fpath);
    # ファイルに追記
    my $make_path_fh_set = sub {
	[$concrete_fpath,
	 IO::File->new($concrete_fpath,O_CREAT | O_APPEND | O_WRONLY,$mode)];
    };
    my $fh = sub {
	# キャッシュは有効か？
	if ($this->config->keep_file_open) {
	    # このチャンネルはキャッシュされているか？
	    my $cached_elem = $this->{filehandle_cache}->{$channel};
	    if (defined $cached_elem) {
		# キャッシュされたファイルパスは今回のファイルと一致するか？
		if ($cached_elem->[0] eq $concrete_fpath) {
		    # このファイルハンドルを再利用して良い。
		    #print "$concrete_fpath: RECYCLED\n";
		    return $cached_elem->[1];
		}
		else {
		    # ファイル名が違う。日付が変わった等の場合。
		    # 古いファイルハンドルを閉じる。
		    #print "$concrete_fpath: recached\n";
		    eval {
			$cached_elem->[1]->flush;
			$cached_elem->[1]->close;
		    };
		    # 新たなファイルハンドルを生成。
		    @$cached_elem = @{$make_path_fh_set->()};
		    return $cached_elem->[1];
		}
	    }
	    else {
		# キャッシュされていないので、ファイルハンドルを作ってキャッシュ。
		#print "$concrete_fpath: *cached*\n";
		my $cached_elem =
		    $this->{filehandle_cache}->{$channel} =
			$make_path_fh_set->();
		return $cached_elem->[1];
	    }
	}
	else {
	    # キャッシュ無効。
	    return $make_path_fh_set->()->[1];
	}
    }->();
    if (defined $fh) {
	$fh->print(
	    Unicode::Japanese->new("$header $line\n",'utf8')->conv(
		$this->config->charset || 'jis'));
    }
}

sub mkdirs {
    my ($this,$file) = @_;
    my (undef,$directories,undef) = File::Spec->splitpath($file);
    my $dir_mode = undef;

    # 直接の親が存在するか
    if ($directories eq '' || -d $directories) {
	# これ以上辿れないか、存在するので終了。
	return;
    }
    else {
	# 存在しないので作成
	my @dirs = File::Spec->splitdir($directories);
	foreach (0 .. (scalar @dirs - 2)) {
	    my $dir = File::Spec->catdir(@dirs[0 .. $_]);
	    unless (-d $dir) {
		$dir_mode ||= do {
		    my $mode_conf = $this->config->dir_mode;
		    if (defined $mode_conf) {
			oct('0'.$mode_conf);
		    }
		    else {
			0700;
		    }
		};
		mkdir $dir, $dir_mode;
	    }
	}
    }
}

sub flush_all_file_handles {
    my $this = shift;
    foreach my $cached_elem (values %{$this->{filehandle_cache}}) {
	eval {
	    $cached_elem->[1]->flush;
	};
    }
}

sub destruct {
    my $this = shift;
    # 開いている全てのファイルハンドルを閉じて、キャッシュを空にする。
    foreach my $cached_elem (values %{$this->{filehandle_cache}}) {
	eval {
	    $cached_elem->[1]->flush;
	    $cached_elem->[1]->close;
	};
    }
    %{$this->{filehandle_cache}} = ();
}

1;

=pod
info: チャンネルやprivのログを取るモジュール。
default: off

# Log系のモジュールでは、以下のように日付や時刻の置換が行なわれる。
# %% : %
# %Y : 年(4桁)
# %m : 月(2桁)
# %d : 日(2桁)
# %H : 時間(2桁)
# %M : 分(2桁)
# %S : 秒(2桁)

# ログを保存するディレクトリ。Tiarraが起動した位置からの相対パス。~指定は使えない。
directory: log

# ログファイルの文字コード。省略されたらjis。
charset: sjis

# 各行のヘッダのフォーマット。省略されたら'%H:%M'。
header: %H:%M:%S

# ファイル名のフォーマット。省略されたら'%Y.%m.%d.txt'
filename: %Y.%m.%d.txt

# ログファイルのモード(8進数)。省略されたら600
mode: 600

# ログディレクトリのモード(8進数)。省略されたら700
dir-mode: 700

# ログを取るコマンドを表すマスク。省略されたら記録出来るだけのコマンドを記録する。
command: privmsg,join,part,kick,invite,mode,nick,quit,kill,topic,notice

# PRIVMSGとNOTICEを記録する際に、自分の発言と他人の発言でフォーマットを変えるかどうか。1/0。デフォルトで1。
distinguish-myself: 1

# 各ログファイルを開きっぱなしにするかどうか。
# このオプションは多くの場合、ディスクアクセスを抑えて効率良くログを保存しますが
# ログを記録すべき全てのファイルを開いたままにするので、50や100のチャンネルを
# 別々のファイルにログを取るような場合には使うべきではありません。
-keep-file-open: 1

# keep-file-openを有効にした場合、発言の度にログファイルに追記するのではなく
# 一定の分量が溜まってから書き込まれる。そのため、ファイルを開いても
# 最近の発言はまだ書き込まれていない可能性がある。
# syncを設定すると、即座にログをディスクに書き込むためのコマンドが追加される。
# 省略された場合はコマンドを追加しない。
sync: sync

# 各チャンネルの設定。チャンネル名の部分はマスクである。
# 個人宛てに送られたPRIVMSGやNOTICEはチャンネル名"priv"として検索される。
# 記述された順序で検索されるので、全てのチャンネルにマッチする"*"などは最後に書かなければならない。
# 指定されたディレクトリが存在しなかったら、Log::Channelはそれを勝手に作る。
# フォーマットは次の通り。
# channel: <ディレクトリ名> (<チャンネル名> / 'priv')
# 例:
# filename: %Y.%m.%d.txt
# channel: IRCDanwasitu #IRC談話室@ircnet
# channel: others *
# この例では、#IRC談話室@ircnetのログはIRCDanwasitu/%Y.%m.%d.txtに、
# それ以外(privも含む)のログはothers/%Y.%m.%d.txtに保存される。
channel: priv priv
channel: others *
=cut
