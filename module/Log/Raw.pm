# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Log::Raw;
use strict;
use warnings;
use IO::File;
use File::Spec;
use Tiarra::Encoding;
use base qw(Module);
use Module::Use qw(Tools::DateConvert Log::Writer);
use Tools::DateConvert;
use Log::Writer;
use ControlPort;
use Mask;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{matching_cache} = {}; # <servername,fname>
    $this->{writer_cache} = {}; # <server,Log::Writer>
    $this->{sync_command} = do {
	my $sync = $this->config->sync;
	if (defined $sync) {
	    uc $sync;
	}
	else {
	    undef;
	}
    };
    $this;
}

sub sync {
    my $this = shift;
    $this->flush_all_file_handles;
    RunLoop->shared->notify_msg("Raw logs synchronized.");
}

sub control_requested {
    my ($this,$request) = @_;
    if ($request->ID eq 'synchronize') {
	$this->sync;
	ControlPort::Reply->new(204,'No Content');
    }
    else {
	die ref($this)." received control request of unsupported ID ".$request->ID."\n";
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
    $message;
}

sub message_io_hook {
    my ($this,$message,$io,$type) = @_;

    # break with last
    while (1) {
	last unless $io->server_p;
	last unless Mask::match_deep([Mask::array_or_all(
	    $this->config->command('all'))], $message->command);
	my $msg = $message->clone;
	if ($this->config->resolve_numeric && $message->command =~ /^\d{3}$/) {
	    $msg->command(
		(NumericReply::fetch_name($message->command)||'undef').
		    '('.$message->command.')');
	}
	my $server = $io->network_name;
	my $dirname = $this->_server_match($server);
	if (defined $dirname) {
	    my $prefix  = sprintf '(%s/%s) ', $server, do {
		if ($type eq 'in') {
		    'recv';
		} elsif ($type eq 'out') {
		    'send';
		} else {
		    '----';
		}
	    };

	    my $charset = do {
		if ($io->can('out_encoding')) {
		    $io->out_encoding;
		} else {
		    $this->config->charset;
		}
	    };
	    if ($msg->have_raw_params) {
		$msg->encoding_params('binary');
		$charset = 'binary';
	    }
	    $this->_write($server, $dirname, $msg->time, $prefix .
			      $msg->serialize($this->config->charset));
	}
	last;
    }

    return $message;
}

sub _server_match {
    my ($this,$server) = @_;

    my $cached = $this->{matching_cache}->{$server};
    if (defined $cached) {
	if ($cached eq '') {
	    # cache of not found
	    return undef;
	}
	else {
	    return $cached;
	}
    }

    foreach my $line ($this->config->server('all')) {
	my ($name, $mask) = split /\s+/, $line, 2;
	if (Mask::match($mask,$server)) {
	    # マッチした。
	    my $fname_format = $this->config->filename || '%Y.%m.%d.txt';
	    my $fpath_format = $name."/$fname_format";

	    $this->{matching_cache}->{$server} = $fpath_format;
	    return $fpath_format;
	}
    }
    $this->{matching_cache}->{$server} = '';
    undef;
}

sub _write {
    # 指定されたログファイルにヘッダ付きで追記する。
    # ディレクトリ名の日付のマクロは置換される。
    my ($this,$channel,$abstract_fpath,$time,$line) = @_;
    my $concrete_fpath = do {
	my $basedir = $this->config->directory;
	if (defined $basedir) {
	    Tools::DateConvert::replace("$basedir/$abstract_fpath", $time);
	}
	else {
	    Tools::DateConvert::replace($abstract_fpath, $time);
	}
    };
    my $header = Tools::DateConvert::replace(
	$this->config->header || '%H:%M',
	$time,
       );
    my $always_flush = do {
	if ($this->config->keep_file_open) {
	    if ($this->config->always_flush) {
		1;
	    } else {
		0;
	    }
	} else {
	    1;
	}
    };
    # ファイルに追記
    my $make_writer = sub {
	Log::Writer->shared_writer->find_object(
	    $concrete_fpath,
	    always_flush => $always_flush,
	    file_mode_oct => $this->config->mode,
	    dir_mode_oct => $this->config->dir_mode,
	   );
    };
    my $writer = sub {
	# キャッシュは有効か？
	if ($this->config->keep_file_open) {
	    # このチャンネルはキャッシュされているか？
	    my $cached_elem = $this->{writer_cache}->{$channel};
	    if (defined $cached_elem) {
		# キャッシュされたファイルパスは今回のファイルと一致するか？
		if ($cached_elem->uri eq $concrete_fpath) {
		    # このファイルハンドルを再利用して良い。
		    #print "$concrete_fpath: RECYCLED\n";
		    return $cached_elem;
		}
		else {
		    # ファイル名が違う。日付が変わった等の場合。
		    # 古いファイルハンドルを閉じる。
		    #print "$concrete_fpath: recached\n";
		    eval {
			$cached_elem->flush;
			$cached_elem->unregister;
		    };
		    # 新たなファイルハンドルを生成。
		    $cached_elem = $make_writer->();
		    if (defined $cached_elem) {
			$cached_elem->register;
		    }
		    return $cached_elem;
		}
	    }
	    else {
		# キャッシュされていないので、ファイルハンドルを作ってキャッシュ。
		#print "$concrete_fpath: *cached*\n";
		my $cached_elem =
		    $this->{writer_cache}->{$channel} =
			$make_writer->();
		if (defined $cached_elem) {
		    $cached_elem->register;
		}
		return $cached_elem;
	    }
	}
	else {
	    # キャッシュ無効。
	    return $make_writer->();
	}
    }->();
    if (defined $writer) {
	$writer->reserve("$header $line\n");
    } else {
	# XXX: do warn with properly frequency
	#RunLoop->shared_loop->notify_warn("can't write to $concrete_fpath: ".
	#				      "$header $line");
    }
}

1;

=pod
info: サーバとの生の通信を保存する
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
directory: rawlog

# 各行のヘッダのフォーマット。省略されたら'%H:%M'。
header: %H:%M:%S

# ファイル名のフォーマット。省略されたら'%Y.%m.%d.txt'
filename: %Y-%m-%d.txt

# ログファイルのモード(8進数)。省略されたら600
mode: 600

# ログディレクトリのモード(8進数)。省略されたら700
dir-mode: 700

# 使っている文字コードがよくわからなかったときの文字コード。省略されたらutf8。
# たぶんこの指定が生きることはないと思いますが……。
charset: jis

# NumericReply の名前を解決して表示する(ちゃんとした dump では無くなります)
resolve-numeric: 1

# ログを取るコマンドを表すマスク。省略されたら記録出来るだけのコマンドを記録する。
command: *,-ping,-pong

# 各ログファイルを開きっぱなしにするかどうか。
# このオプションは多くの場合、ディスクアクセスを抑えて効率良くログを保存しますが
# ログを記録すべき全てのファイルを開いたままにするので、50や100のチャンネルを
# 別々のファイルにログを取るような場合には使うべきではありません。
# 万一 fd があふれた場合、クライアントから(またはサーバへ)接続できない・
# 新たなモジュールをロードできない・ログが全然できないなどの症状が起こる可能性が
# あります。limit の詳細については OS 等のドキュメントを参照してください。
-keep-file-open: 1

# keep-file-open 時に各行ごとに flush するかどうか。
# open/close の負荷は気になるが、ログは失いたくない人向け。
# keep-file-open が有効でないなら無視され(1になり)ます。
-always-flush: 0

# keep-file-openを有効にした場合、発言の度にログファイルに追記するのではなく
# 一定の分量が溜まってから書き込まれる。そのため、ファイルを開いても
# 最近の発言はまだ書き込まれていない可能性がある。
# syncを設定すると、即座にログをディスクに書き込むためのコマンドが追加される。
# 省略された場合はコマンドを追加しない。
sync: sync

# 各サーバの設定。サーバ名の部分はマスクである。
# 記述された順序で検索されるので、全てのサーバにマッチする"*"などは最後に書かなければならない。
# 指定されたディレクトリが存在しなかったら、勝手に作られる。
# フォーマットは次の通り。
# channel: <ディレクトリ名> <サーバ名マスク>
# 例:
# filename: %Y-%m-%d.txt
# server: ircnet ircnet
# server: others *
# この例では、ircnetのログはircnet/%Y.%m.%d.txtに、
# それ以外のログはothers/%Y.%m.%d.txtに保存される。
server: ircnet ircnet
server: others *
=cut
