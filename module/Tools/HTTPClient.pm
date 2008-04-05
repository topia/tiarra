# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# HTTP/1.1非対応。
# -----------------------------------------------------------------------------
package Tools::HTTPClient;
use strict;
use warnings;
use LinedINETSocket;
use Carp;
use RunLoop;
use Timer;
use Tools::HTTPClient::SSL;
use Module::Use qw(Tools::HTTPClient::SSL);

# 本当はHTTP::RequestとHTTP::Responseを使いたいが…

our $DEBUG = 0;

sub new {
    my ($class, %args) = @_;
    my $this = bless {} => $class;

    if (!$args{Method}) {
	croak "Argument `Method' is required";
    }
    if (!$args{Url}) {
	croak "Argument `Url' is required";
    }

    $this->{method} = $args{Method}; # GET | POST
    $this->{url} = $args{Url};
    $this->{content} = $args{Content}; # undef可
    $this->{header} = $args{Header} || {}; # {key => value} undef可
    $this->{timeout} = $args{Timeout}; # undef可

    $this->{callback} = undef;
    $this->{progress_callback} = undef;
    $this->{socket} = undef;
    $this->{hook} = undef;
    $this->{timeout_timer} = undef;

    $this->{expire_time} = undef; # タイムアウト時刻

    $this->{status_fetched} = undef;
    $this->{header_fetched} = undef;

    $this->{reply} = {Header => {}, Content => '', StreamState => 'ready' };

    $this;
}

sub start {
    # $callback: セッション終了後に呼ばれる関数。省略不可。
    # この関数には次のようなハッシュが渡される。
    # {
    #     Protocol => 'HTTP/1.0',
    #     Code     => 200,
    #     Message  => 'OK',
    #     Header   => {
    #         'Content-Length' => 6,
    #     },
    #     Content => 'foobar',
    # }
    # エラーが発生した場合はエラーメッセージ(文字列)が渡される。
    my ($this, $callback) = @_;
    my %opts;
    if( @_>=3 )
    {
      ($this, %opts) = @_;
      $callback = $opts{Callback};
    }
    if ($this->{callback}) {
	croak "This client is already started";
    }
    $this->{callback} = $callback;
    $this->{progress_callback} = $opts{ProgressCallback};

    if (!$callback or ref($callback) ne 'CODE') {
	croak "Callback function is required";
    }

    # URLを分解し、ホスト名とパスを得る。
    my ($host, $path);
    $this->{url} =~ s/#.+//;
    if ($this->{url} =~ m|^http(s?)://(.+)$|) {
	my $with_ssl = $1;
	my $hostpath = $2;
	if ($hostpath =~ m|^(.+?)(/.*)|) {
	    $host = $1;
	    $path = $2;
	}
	else {
	    $host = $1;
	    $path = '/';
	}
	$this->{with_ssl} = $with_ssl;
    }
    else {
	croak "Unsupported scheme: $this->{url}";
    }

    # ヘッダにHostが含まれていなければ追加。
    if (!$this->{header}{Host}) {
	$this->{header}{Host} = $host;
    }

    # ホスト名にポートが含まれていたら分解。
    my $port = $this->{with_ssl} ? 443 : 80;
    if ($host =~ s/:(\d+)$//) {
	$port = $1;
    }

    # 接続
    $this->{reply}{StreamState} = 'connect';
    my $socket_class = $this->{with_ssl} ? 'Tools::HTTPClient::SSL' : 'LinedINETSocket';
    $this->{socket} = $socket_class->new->connect($host, $port);
    if (!defined $this->{socket}) {
	# 接続不可能
	croak "Failed to connect: $host:$port";
    }
    if (!defined $this->{socket}->sock) {
	# 接続不可能
	croak "Failed to connect: $host:$port, $@";
    }
    $this->{reply}{StreamState} = 'fetch_status';

    # 必要ならタイムアウト用のタイマーをインストール
    if ($this->{timeout}) {
	$this->{expire_time} = time + $this->{timeout};
	$this->{timeout_timer} = Timer->new(
	    After => $this->{timeout},
	    Code => sub {
		$this->{timeout_timer} = undef;
		$this->_main;
	    })->install;
    }

    # リクエストを発行し、フックをかけて終了。
    my @request = (
	"$this->{method} $path HTTP/1.0",
	do {
	    map {
		"$_: ".$this->{header}{$_}
	    } keys %{$this->{header}}
	},
	'',
	do {
	    $this->{content} ? $this->{content} : ();
	},
       );
    foreach (@request) {
	$DEBUG and print "> $_\n";
	$this->{socket}->send_reserve($_);
    }

    $this->{hook} = RunLoop::Hook->new(
	sub {
	    $this->_main;
	})->install('before-select');

    $this;
}

sub _main {
    my $this = shift;

    # タイムアウト判定
    if ($this->{expire_time} and time >= $this->{expire_time}) {
	$this->_end("timeout");
	return;
    }

    my $progress;
    while (defined(my $line = $this->{socket}->pop_queue)) {
	$DEBUG and print "< $line\n";
	$progress = 1;
	
	if (!$this->{status_fetched}) {
	    # ステータス行
	    $line =~ tr/\n\r//d;
	    if ($line =~ m|^(HTTP/.+?) (\d+?) (.+)$|) {
		$this->{reply}{Protocol} = $1;
		$this->{reply}{Code} = $2;
		$this->{reply}{Message} = $3;
		$this->{status_fetched} = 1;
		$this->{reply}{StreamState} = 'fetch_header';
	    }
	    else {
		$this->_end("invalid status line: $line");
		return;
	    }
	}
	elsif (!$this->{header_fetched}) {
	    $line =~ tr/\n\r//d;
	    if (length $line == 0) {
		# ヘッダ終わり
		$this->{header_fetched} = 1;
		$this->{reply}{StreamState} = 'fetch_body';
	    }
	    else {
		if ($line =~ m|(.+?): ?(.+)$|) {
		    my ($key, $val) = ($1, $2);
		    $key =~ /^Content-Type\z/i and $key = 'Content-Type';
		    $this->{reply}{Header}{$key} = $val;
		}
		else {
		    $this->_end("invalid header line: $line");
		    return;
		}
	    }
	}
	else {
	    # 中身
	    $this->{reply}{Content} .= $line . "\x0d\x0a";
	}
    }

    if( $this->{header_fetched} && $this->{socket}->recvbuf )
    {
      #$DEBUG and print "<< (merge body)\n" . $this->{socket}->recvbuf."<< (end)\n";
      $progress = 1;
      $this->{reply}{Content} .= $this->{socket}->recvbuf;
      $this->{socket}->recvbuf = '';
    }

    # 切断されていたら、ここで終わり。
    if (!$this->{socket}->connected) {
        $DEBUG and print "<< (disconnected)\n";
	if (!$this->{status_fetched} or
	      !$this->{header_fetched}) {
	    $this->_end("unexpected disconnect by server");
	}
	else {
	    $this->{reply}{StreamState} = 'finished';
	    $this->_end;
	}
    }else
    {
      if( $progress && $this->{progress_callback} )
      {
        $this->{progress_callback}->($this->{reply});
      }
    }
}

sub _end {
    my ($this, $err) = @_;

    $this->stop;
    
    if ($err) {
	$this->{callback}->($err);
    }
    else {
	$this->{callback}->($this->{reply});
    }
}

sub alive_p {
    my $this = shift;
    defined $this->{socket};
}

sub stop {
    my $this = shift;

    $this->{socket}->disconnect if $this->{socket} && $this->{socket}->connected;
    $this->{hook}->uninstall if $this->{hook};
    $this->{timeout_timer}->uninstall if $this->{timeout_timer};

    $this->{socket} =
      $this->{hook} =
	$this->{timeout_timer} =
	  undef;
}

1;

=encoding euc-jp

=head1 NAME

Tools::HTTPClient - HTTP Client

=head1 SYNOPSIS

 use Tools::HTTPClient;

 my $http = Tools::HTTPClient->new(
   Url    => 'http://www.example.com',
   Method => 'GET',
 );
 $http->start(\&callback);

=head1 DESCRIPTION

HTTP Client for tiarra.

ブロックしないように処理は非推奨なので,
ブロックしないように調整されている HTTP 
クライアントモジュール.

=head1 METHODS

=head2 new

 my $http = Tools::HTTPClient->new(
   Url    => 'http://www.example.com',
   Method => 'GET',
 );

インスタンスの生成.
C<Url> 及び C<Method> 引数は必須.

その他の省略可能な引数として,
C<Content> (POST内容),
C<Header>  (HASH-ref),
C<Timeout> (秒単位)
が利用可能.

=head2 start

 $http->start(\&callback);
 $http->start(%opts);

 $opts{Callback}         = \&callback;
 $opts{ProgressCallback} = \&progress_callback;

C<\&callback> は処理完了時に呼ばれる関数.
C<\&progress_callback> は処理の進捗があったときに呼ばれる関数.

C<\&callback> は, HTTPが正常に完了すればHASH-refを,
タイムアウトやエラー時にはエラー内容を含んだ文字列を
引数として呼び出される.

  sub my_callback {
    my $response = shift;
    if( !ref($response) )
    {
      # error.
      return;
    }
    # success.
    my $protocol    = $response->{Protocol};
    my $status_code = $response->{Code};
    my $status_msg  = $response->{Message};
    my $headers     = $response->{Header}; # hash-ref.
    my $content     = $response->{Content};
  }

C<\&progress_callback> も同様, 
ただしこちらはエラーの報告には呼ばれない.

=head2 stop

 $http->stop();

リクエストの終了.
このときは L</start> で指定した C<\&callback> がよばれないので注意.

=head1 AUTHOR

phonohawk <phonohawk@ps.sakura.ne.jp>

=head1 SEE ALSO

tiarra
http://coderepos.org/share/wiki/Tiarra
(Japanese)

=cut
