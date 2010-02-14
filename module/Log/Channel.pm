# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Log::Channel;
use strict;
use warnings;
use IO::File;
use File::Spec;
use Tiarra::Encoding;
use base qw(Module);
use Module::Use qw(Tools::DateConvert Log::Logger Log::Writer);
use Tools::DateConvert;
use Log::Logger;
use Log::Writer;
use Module::Use qw(Tools::HashTools);
use Tools::HashTools;
use ControlPort;
use Mask;
use Multicast;

our $DEFAULT_FILENAME_ENCODING = $^O eq 'MSWin32' ? 'sjis' : 'utf8';
our $DEFAULT_NEWLINE = $^O eq 'MSWin32' ? "\r\n" : "\n";

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{channels} = []; # 要素は[ディレクトリ名,マスク]
    $this->{matching_cache} = {}; # <チャンネル名,ファイル名>
    $this->{writer_cache} = {}; # <チャンネル名,Log::Writer>
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

{
    no warnings qw(once);
    *S_PRIVMSG = \&PRIVMSG_or_NOTICE;
    *S_NOTICE = \&PRIVMSG_or_NOTICE;
    *C_PRIVMSG = \&PRIVMSG_or_NOTICE;
    *C_NOTICE = \&PRIVMSG_or_NOTICE;
}

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
	    # あまり好ましくなさそうな文字はあらかじめエスケープ.
	    my $chan_filename = $channel;
	    $chan_filename =~ s/![0-9A-Z]{5}/!/;
	    $chan_filename =~ s{([^-\w@#%!+&.\x80-\xff])}{
	      sprintf('=%02x', unpack("C", $1));
	    }ge;
	    my $chan_dir = Tools::HashTools::replace_recursive(
		$ch->[0], [{channel => $chan_filename, lc_channel => lc $chan_filename}]);
	    my $fpath_format = "$chan_dir/$fname_format";

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
    my $filename_encoding = $this->config->filename_encoding || $DEFAULT_FILENAME_ENCODING;
    if( $filename_encoding ne 'ascii' )
    {
      $concrete_fpath = Tiarra::Encoding->new($concrete_fpath)->conv($filename_encoding);
    }else
    {
      $concrete_fpath =~ s/([^ -~])/sprintf('=%02x', unpack("C", $1))/ge;
    }
    my $header = Tools::DateConvert::replace(
	$this->config->header || '%H:%M'
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
        my $newline;
        if (defined $this->config->crlf) {
            $newline = $this->config->crlf ? "\r\n" : "\n";
        }
        else {
            $newline = $DEFAULT_NEWLINE;
        }
	$writer->reserve(
	    Tiarra::Encoding->new("$header $line$newline",'utf8')->conv(
		$this->config->charset || 'jis'));
    } else {
	# XXX: do warn with properly frequency
	#RunLoop->shared_loop->notify_warn("can't write to $concrete_fpath: ".
	#				      "$header $line");
    }
}

sub flush_all_file_handles {
    my $this = shift;
    foreach my $cached_elem (values %{$this->{writer_cache}}) {
	eval {
	    $cached_elem->flush;
	};
    }
}

sub destruct {
    my $this = shift;
    # 開いている全てのLog::Writerを閉じて、キャッシュを空にする。
    foreach my $cached_elem (values %{$this->{writer_cache}}) {
	eval {
	    $cached_elem->flush;
	    $cached_elem->unregister;
	};
    }
    %{$this->{writer_cache}} = ();
}

1;

=pod
info: チャンネルやprivのログを取るモジュール。
default: off
section: important

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
charset: utf8

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
# #(channel) はチャンネル名に展開される。
# (古いバージョンだと展開されずにそのままディレクトリ名になってしまいます。)
# IRCのチャンネル名は大文字小文字が区別されず、サーバからは各送信者が指定した通りの
# チャンネル名が送られてきます。そのため、大文字小文字が区別されるファイルシステムでは
# 同じチャンネルが別々のディレクトリに作られることになります。
# この問題を回避するため、チャンネル名を小文字に統一した #(lc_channel) が利用できます。
channel: priv priv
channel: #(lc_channel) *
-channel: others *

# ファイル名のエンコーディング.
# 指定可能な値は, utf8, sjis, euc, jis, ascii.
# ascii は実際には utf8 と同等で8bit部分が全てquoted-printableされる.
# デフォルトはWindowsではsjis, それ以外では utf8.
-filename-encoding: utf8

# ログの改行コード出力をCRLFにするかどうか.
# デフォルトはWindowsでは1(CRLF), それ以外では0(LF).
# Windowsでログを扱うことが多い場合、1にするとちょっと幸せになれるかもしれない.
-crlf: 0

=cut
