# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
=pod
    << NOTIFY Log::Channel TIARRACONTROL/1.0
    << Sender: LogManager
    << ID: synchronize

    >> TIARRACONTROL/1.0 204 No Content
    ----------------------------------------
    << GET :: TIARRACONTROL/1.0
    << Sender: Foo
    << ID: get-realname
    << Reference0: ircnet
    << Charset: UTF-8

    >> TIARRACONTROL/1.0 200 OK
    >> Value: (ネットワークircnetでの本名)
    >> Charset: UTF-8
=cut
# -----------------------------------------------------------------------------
package ControlPort;
use strict;
use warnings;
use Carp;
use IO::Dir;
use ExternalSocket;
use Tiarra::Encoding;
use RunLoop;
use Tiarra::TerminateManager;

# 複数のパッケージを混在させてるとSelfLoaderが使えない…？
#use SelfLoader;
#1;
#__DATA__

sub TIARRA_CONTROL_ROOT () { '/tmp/tiarra-control'; }

sub new {
    my ($class,$sockname) = @_;

    # IO::Socket::UNIXをuseする。失敗したらdie。
    eval q{
        use IO::Socket::UNIX;
    }; if ($@) {
	# 使えない。
	die "Tiarra control socket is not available for this environment.\n";
    }

    my $this = {
	sockname => $sockname,
	filename => TIARRA_CONTROL_ROOT.'/'.$sockname,
	server_sock => undef, # ExternalSocket
	clients => [], # ControlPort::Session
	session_handle_hook => undef, # RunLoop::Hook
    };
    bless $this,$class;
    $this->open;

    $this;
}

sub open {
    my $this = shift;
    my $filename = $this->{filename};

    # ディレクトリ/tmp/tiarra-controlが無ければ作る。
    if (!-d TIARRA_CONTROL_ROOT) {
	mkdir TIARRA_CONTROL_ROOT or die 'Couldn\'t make directory '.TIARRA_CONTROL_ROOT;
	# 他のユーザーも作れるようにする。
	# 最初に作成したユーザーが全ファイルを消すことが出来るが、対処法なし。
	chmod 01777, TIARRA_CONTROL_ROOT;
    }

    # ソケットが既に存在した場合は接続してみる。
    if (-e $filename) {
	my $sock = IO::Socket::UNIX->new(
	    Peer => $filename,
	   );
	if (!defined $sock) {
	    # もう使われていない?
	    unlink $filename;
	    undef $sock;
	}
    }

    # リスニング用ソケットを開く。
    my $sock = IO::Socket::UNIX->new(
	Type => &SOCK_STREAM,
	Local => $filename,
	Listen => 1);
    if (!defined $sock) {
	die "Couldn't make socket $filename: $!";
    }
    # パーミッションを700に。
    chmod 0700, $filename;
    $this->{server_sock} =
	ExternalSocket->new(
	    Socket => $sock,
	    Read => sub {
		my $server = shift->sock;
		my $client = $server->accept;
		if (defined $client) {
		    push @{$this->{clients}},ControlPort::Session->new($client);
		}
	    },
	    Write => sub{},
	    WantToWrite => sub{undef})->install;

    # セッションハンドル用のフックをかける。
    $this->{session_handle_hook} =
	RunLoop::Hook->new(
	    'ControlPort Session Handler',
	    sub {
		# セッション処理
		foreach my $client (@{$this->{clients}}) {
		    $client->main;
		}
		# 終了したセッションを削除
		@{$this->{clients}} = grep {
		    $_->is_alive;
		} @{$this->{clients}};
	    })->install;

    $this->{destructor} = Tiarra::TerminateManager::Hook->new(
	sub {
	    $this->destruct;
	})->install;

    $this;
}

sub destruct {
    my $this = shift;

    # 切断
    if (defined $this->{server_sock}) {
	eval {
	    $this->{server_sock}->disconnect;
	};
    }

    # このソケットファイルを削除
    unlink $this->{filename};

    # ディレクトリにソケットが一つも無くなったら、このディレクトリも消える。
    rmdir TIARRA_CONTROL_ROOT;

    $this;
}

package ControlPort::Session;
use strict;
use warnings;
use Tiarra::Socket::Lined;
use base qw(Tiarra::Socket::Lined);

sub new {
    # $sock: IO::Socket
    my ($class,$sock) = @_;
    my $this = $class->SUPER::new(name => 'ControlPort::Session');
    $this->{method} = undef; # GETまたはNOTIFY
    $this->{module} = undef; # Log::Channelなど。'::'はメインプログラムを表す。
    $this->{header} = undef; # {key => value}
    $this->{input_is_frost} = 0; # これ以上の入力を無視するか？
    bless $this,$class;
    $this->attach($sock);
    $this->install;
}

sub main {
    my $this = shift;

    while (defined($_ = $this->pop_queue)) {
	s/^\s*|\s*$//g;
	my $line = $_;

	if ($this->{input_is_frost}) {
	    last;
	}

	if (defined $this->{header}) {
	    # $this->{header}が存在するということは、最初のリクエスト行はもう受け取った。
	    if ($line eq '') {
		# 空の行だ。リクエスト終わり。
		$this->respond;
	    }
	    else {
		if ($line =~ m/^(.+?)\s*:\s*(.+)$/) {
		    $this->{header}{$1} = $2;
		}
		else {
		    $this->reply(401,'Bad Request');
		}
	    }
	}
	else {
	    if ($line =~ m|^(.+?)\s+(.+?)\s+TIARRACONTROL/(\d+)\.(\d+)$|) {
		$this->{method} = $1;
		$this->{module} = $2;
		if (!{GET => 1,NOTIFY => 1}->{$this->{method}}) {
		    $this->reply(501,'Method Not Implemented');
		}
		my $version = "$3.$4";
		if ($version > 1.0) {
		    $this->reply(401,'Bad Request');
		}
		$this->{header} = {};
	    }
	    else {
		$this->reply(401,'Bad Request');
	    }
	}
    }
}

sub reply {
    # $code: 204など
    # $str: No Contentなど
    # $header: {key => value} 省略可。文字コードはUTF-8。SenderとCharsetは不要。
    my ($this,$code,$str,$header) = @_;

    $this->append_line("TIARRACONTROL/1.0 $code $str");
    $this->append_line('Sender: Tiarra #'.&::version);
    my $unijp = Tiarra::Encoding->new;
    if (defined $header) {
	while (my ($key,$value) = each %$header) {
	    $this->append_line($unijp->set("$key: $value")->conv($this->charset));
	}
    }
    $this->append_line('Charset: '.$this->long_charset);
    $this->append_line('');
    $this->disconnect_after_writing;
}

sub charset {
    # リクエストで受け取ったCharsetから、Unicode::Japaneseエンコーディング名を返す。
    my $this = shift;

    if (!defined $this->{header}) {
	return 'utf8';
    }

    my $charset = $this->{header}->{Charset};
    if (!defined $charset) {
	return 'utf8';
    }

    my $charset_table = {
	'Shift_JIS' => 'sjis',
	'EUC-JP' => 'euc',
	'ISO-2022-JP' => 'jis',
	'UTF-8' => 'utf8',
    };
    $charset_table->{$charset} || 'utf8';
}

sub long_charset {
    my $this = shift;

    my $table = {
	'sjis' => 'Shift_JIS',
	'euc' => 'EUC-JP',
	'jis' => 'ISO-2022-JP',
	'utf8' => 'UTF-8',
    };
    $table->{$this->charset} || 'UTF-8';
}

sub is_alive {
    shift->connected;
}

sub respond {
    my $this = shift;

    my $req = ControlPort::Request->new($this->{method},$this->{module});
    my $charset = $this->charset;
    my $unijp = Tiarra::Encoding->new;
    while (my ($key,$value) = each %{$this->{header}}) {
	next if $key eq 'Charset';
	$req->$key($unijp->set($value,$charset)->utf8);
    }

    my $rep = eval {
	if ($req->module eq '::') {
	    # モジュール"::"はメインプログラムを表す。
	    # 後で。
	    die qq{Controlling '::' is not supported yet.\n};
	}
	else {
	    # このようなモジュールは存在するか？
	    my $mod = ModuleManager->shared->get($req->module);
	    if (defined $mod) {
		my $reply = $mod->control_requested($req);
		if (!defined $reply) {
		    die $this->{module}."->control_requested returned undef.\n";
		}
		elsif (!$reply->isa('ControlPort::Reply')) {
		    die $this->{module}."->control_requested returned bad ref: ".ref($reply)."\n";
		}
		else {
		    $reply;
		}
	    }
	    else {
		die qq{Module $this->{module} doesn't exist.\n};
	    }
	}
    };
    if ($@) {
	(my $detail = $@) =~ s/\n//g;
	$this->reply(500,'Internal Server Error',{Detail => $detail});
    }
    else {
	$this->reply($rep->code,$rep->status,$rep->table);
    }
}

package ControlPort::Packet;
use strict;
use warnings;
our $AUTOLOAD;
use Tiarra::Utils ();
Tiarra::Utils->define_attr_getter(0, qw(table));

sub new {
    my $class = shift;
    my $this = {
	table => {}, # {key => value}
    };
    bless $this,$class;
}

sub AUTOLOAD {
    my ($this,$value) = @_;
    if ($AUTOLOAD =~ /::DESTROY$/) {
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    if (defined $value) {
	$this->{table}{$key} = $value;
    }
    $this->{table}{$key};
}

package ControlPort::Request;
use strict;
use warnings;
use base qw(ControlPort::Packet);
use Tiarra::Utils ();
Tiarra::Utils->define_attr_getter(0, qw(method module));

sub new {
    my ($class,$method,$module) = @_;
    my $this = $class->SUPER::new;
    $this->{method} = $method;
    $this->{module} = $module;
    $this;
}

package ControlPort::Reply;
use strict;
use warnings;
use base qw(ControlPort::Packet);
use Tiarra::Utils ();
Tiarra::Utils->define_attr_getter(0, qw(code status));

sub new {
    # $code: 204など
    # $status: No Contentなど
    my ($class,$code,$status) = @_;
    my $this = $class->SUPER::new;
    $this->{code} = $code;
    $this->{status} = $status;
    $this;
}

1;
