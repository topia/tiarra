# -----------------------------------------------------------------------------
# $Id: ControlPort.pm,v 1.4 2004/04/18 06:01:16 admin Exp $
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
use LinedINETSocket;
use ExternalSocket;
use Unicode::Japanese;
use RunLoop;

use SelfLoader;
1;
__DATA__

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
	server_sock => undef, # LinedINETSocket
	clients => [], # ControlPort::Session
	session_handle_hook => undef, # RunLoop::Hook
    };
    bless $this,$class;
    $this->open;

    $this;
}

sub open {
    my $this = shift;
    my $sockname = $this->{sockname};

    # ディレクトリ/tmp/tiarra-controlが無ければ作る。
    if (!-d '/tmp/tiarra-control') {
	mkdir '/tmp/tiarra-control' or die "Couldn't make directory /tmp/tiarra-control\n";
    }

    # リスニング用ソケットを開く。
    my $sock = IO::Socket::UNIX->new(
	Type => &SOCK_STREAM,
	Local => "/tmp/tiarra-control/$sockname",
	Listen => 1);
    if (!defined $sock) {
	die "Couldn't make socket /tmp/tiarra-control/$sockname\n";
    }
    # パーミッションを700に。
    chmod 0700,"/tmp/tiarra-control/$sockname";
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
	RunLoop::Hook->new(sub {
	    # セッション処理
	    foreach my $client (@{$this->{clients}}) {
		$client->main;
	    }
	    # 終了したセッションを削除
	    @{$this->{clients}} = grep {
		$_->is_alive;
	    } @{$this->{clients}};
	})->install;

    $this;
}

sub DESTROY {
    my $this = shift;
    
    # 切断
    if (defined $this->{server_sock}) {
	eval {
	    $this->{server_sock}->disconnect;
	};
    }

    # このソケットファイルを削除
    unlink "/tmp/tiarra-control/$this->{sockname}";

    # /tmp/tiarra-controlディレクトリにソケットが一つも無くなったら、このディレクトリも消す。
    my $dh = IO::Dir->new('/tmp/tiarra-control');
    my $sock_exists;
    while (defined $dh && defined ($_ = $dh->read)) {
	if (-S "/tmp/tiarra-control/$_") {
	    $sock_exists = 1;
	    last;
	}
    }
    if (!$sock_exists) {
	rmdir '/tmp/tiarra-control';
    }

    $this;
}

package ControlPort::Session;
use strict;
use warnings;

sub new {
    # $sock: IO::Socket
    my ($class,$sock) = @_;
    my $this = {
	sock => LinedINETSocket->new->attach($sock),
	method => undef, # GETまたはNOTIFY
	module => undef, # Log::Channelなど。'::'はメインプログラムを表す。
	header => undef, # {key => value}
	input_is_frost => 0, # これ以上の入力を無視するか？
    };
    bless $this,$class;
}

sub main {
    my $this = shift;

    while (defined($_ = $this->{sock}->pop_queue)) {
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

    $this->{sock}->send_reserve("TIARRACONTROL/1.0 $code $str");
    $this->{sock}->send_reserve('Sender: Tiarra #'.&::version);
    my $unijp = Unicode::Japanese->new;
    if (defined $header) {
	while (my ($key,$value) = each %$header) {
	    $this->{sock}->send_reserve($unijp->set("$key: $value")->conv($this->charset));
	}
    }
    $this->{sock}->send_reserve('Charset: '.$this->long_charset);
    $this->{sock}->send_reserve('');
    $this->{sock}->disconnect_after_writing;
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
    shift->{sock}->connected;
}

sub respond {
    my $this = shift;

    my $req = ControlPort::Request->new($this->{method},$this->{module});
    my $charset = $this->charset;
    my $unijp = Unicode::Japanese->new;
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

sub new {
    my $class = shift;
    my $this = {
	table => {}, # {key => value}
    };
    bless $this,$class;
}

sub table {
    shift->{table};
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

sub new {
    my ($class,$method,$module) = @_;
    my $this = $class->SUPER::new;
    $this->{method} = $method;
    $this->{module} = $module;
    $this;
}

sub method {
    shift->{method};
}

sub module {
    shift->{module};
}

package ControlPort::Reply;
use strict;
use warnings;
use base qw(ControlPort::Packet);

sub new {
    # $code: 204など
    # $status: No Contentなど
    my ($class,$code,$status) = @_;
    my $this = $class->SUPER::new;
    $this->{code} = $code;
    $this->{status} = $status;
    $this;
}

sub code {
    shift->{code};
}

sub status {
    shift->{status};
}

1;
