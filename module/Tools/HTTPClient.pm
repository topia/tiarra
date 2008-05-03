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
use Tools::HTTPParser;
use Module::Use qw(Tools::HTTPParser);

our $HAS_IPV6 = Tiarra::OptionalModules->ipv6;

# 本当はHTTP::RequestとHTTP::Responseを使いたいが…

our $DEBUG = 0;

# -----------------------------------------------------------------------------
# $pkg->new(%opts).
#
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
    $this->{debug}   = $args{Debug};

    $this->{host} = undef;
    $this->{port} = undef;
    $this->{addr} = undef;
    $this->{path} = undef;

    $this->{callback} = undef;
    $this->{progress_callback} = undef;
    $this->{socket} = undef;
    $this->{hook} = undef;
    $this->{timeout_timer} = undef;
    $this->{shutdown_wr_after_writing} = undef;
    $this->{stopped} = undef;

    $this->{expire_time} = undef; # タイムアウト時刻

    $this->{parser} = Tools::HTTPParser->new( response => 1 );

    $DEBUG and print __PACKAGE__."#new, $this, $this->{url}\n";
    $this;
}

# -----------------------------------------------------------------------------
# $obj->DESTROY().
#
sub DESTROY
{
  my $this = shift;
  $DEBUG and print __PACKAGE__."#DESTROY($this), $this->{url}.\n";
  $this->stop();
  $DEBUG and print __PACKAGE__."#DESTROY($this), $this->{url}, done.\n";
}

# -----------------------------------------------------------------------------
# $obj->start(%opts).
#
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

    local($DEBUG) = $DEBUG || $this->{debug};

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

    #googleさん関係でいまいち動かない？
    #if (!$this->{header}{Connection}) {
    #  # HTTP/1.1 だと Keep-Alive がデフォルトだけど,
    #  # ひとまず気にしない….
    #  $this->{header}{Connection} = 'close';
    #}

    # ホスト名にポートが含まれていたら分解。
    my $port = $this->{with_ssl} ? 443 : 80;
    if ($host =~ s/:(\d+)$//) {
	$port = $1;
    }

    $this->{host} = $host;
    $this->{port} = $port;
    $this->{path} = $path;

    # Content-Length をもっていたらチェック.
    if( my $clen = $this->{header}{'Content-Length'} )
    {
      if( !defined($this->{content}) )
      {
        $this->_delay(sub{ $this->_end("Content-Length: $clen, but no content."); });
        return $this;
      }
      my $alen = length($this->{content});
      if( $clen != $alen )
      {
        $this->_delay(sub{ $this->_end_delay("Content-Length: $clen, but actual length is $alen"); });
        return $this;
      }
    }

    # 必要ならタイムアウト用のタイマーをインストール
    if ($this->{timeout}) {
        $this->{expire_time} = time + $this->{timeout};
        $this->{timeout_timer} = Timer->new(
          After => $this->{timeout},
          Code => sub {
              $this->{timeout_timer} = undef;
              if( $this->{socket} )
              {
                $this->_main;
              }elsif( !$this->{addr} )
              {
                $this->_end("dns timeout");
              }else
              {
                $this->_end("timeout");
              }
        })->install;
    }

    if( $this->is_valid_address($host) )
    {
      $this->_delay( sub { $this->_resolved($host, 'literal'); } );
    }elsif( my $addr = $this->_resolve_locally($host) )
    {
      $this->_delay( sub { $this->_resolved($addr, 'local-resolve'); } );
    }else
    {
      my $dns_reply = \&_dns_reply;
      Tiarra::Resolver->resolve(addr => $host, sub{ $this->$dns_reply(@_) });
    }
    $this;
}

sub is_valid_address
{
  my $this = shift;
  my $addr = shift;

  # ipv4.
  my @ipv4 = $addr =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)\z/;
  if( @ipv4 && !grep{ $_>255 || /^0./ }@ipv4 )
  {
    return $addr;
  }

  # ipv6 is not supported..

  undef;
}

sub _resolve_locally
{
  my $this = shift;
  my $host = shift;

  my $addr;
  my $timedout;
  local($SIG{ALRM}) = sub{ die $timedout="ALRM" };
  eval{
    alarm(1); # can interrupt inet_[ap]ton?
    if( $HAS_IPV6 )
    {
      my $dns_reply = \&_dns_reply;
      my $addr_bin = Socket6::inet_pton(Socket6::AF_INET6(), $host);
      $addr = $addr_bin && Socket6::inet_ntop(Socket6::AF_INET6(), $addr_bin);
    }
    if( !$addr )
    {
      my $addr_bin = Socket::inet_aton($host);
      $addr = $addr_bin && Socket::inet_ntoa($addr_bin);
    }
    alarm(0);
  };
  $@ && !$timedout and die;
    
  return $addr;
}

sub _dns_reply
{
    my $this = shift;
    if( !$this->can('new') )
    {
      # this module is unloaded.
      return;
    }
    my $resolved = shift;
    my $addr_list = $resolved->answer_data;
    my $addr = $addr_list->[0];
    if( !$addr )
    {
      $this->_end("no address for ".$resolved->query_data);
      return;
    }
    $this->_resolved($addr, 'dns');
}

sub _resolved
{
    my $this = shift;
    my $addr = shift;
    my $resolver = shift;

    $DEBUG and print __PACKAGE__."#_resolved, $resolver / $this->{host} => $addr\n";

    $this->{addr} = $addr;
    my $port = $this->{port};

    if( !$this->is_valid_address($addr) )
    {
      $this->_end("invalid address: $addr");
      return;
    }

    if( $this->{progress_callback} )
    {
      # 進展があったのでコールバック.
      $this->{progress_callback}->($this->{parser}->object);
      if( $this->{stopped} )
      {
        return;
      }
    }

    # 接続
    if( $this->{with_ssl} )
    {
      $this->{socket} = Tools::HTTPClient::SSL->new()->connect($addr, $port);
    }else
    {
      $this->{socket} = LinedINETSocket->new()->connect($addr, $port);
    }
    if (!defined $this->{socket}) {
	# 接続不可能
	$this->_end("Failure on connection: $this->{host}:$port ($addr)");
	return;
    }
    if (!defined $this->{socket}->sock) {
	# 接続不可能
	$this->_end("Failure on connection (*): $this->{host}:$port ($addr)");
	return;
    }

    # リクエストを発行し、フックをかけて終了。
    # 行単位処理はしないので,
    # eol を送信時は '' で, 受信時はランダムでつぶして送信.
    my $req = {
      Type     => 'request',
      Method   => $this->{method},
      Path     => $this->{path},
      Protocol => 'HTTP/1.0',
      Header   => $this->{header},
      ($this->{content} ? (Content  => $this->{content}) : ()),
    };
    $this->{socket}->eol("");
    $this->{socket}->send_reserve( Tools::HTTPParser->to_string($req) );
    #$DEBUG and print Dumper($req);use Data::Dumper;
    #$DEBUG and print "<<sendbuf>>\n".$this->{socket}->sendbuf."<</sendbuf>>\n";;
    $this->{socket}->eol( pack("C*", map{rand(256)}1..32) );

    #googleさん関係でいまいち動かない？
    #$this->{shutdown_wr_after_writing} = !$this->{header}{Connection} || $this->{header}{Connection} =~ /close/i || $this->{header}{Connection} !~ /Keep-Alive/i;
    #if( $this->{host} =~ /google|gmail/ )
    #{
    #  $this->{shutdown_wr_after_writing} = undef;
    #}

    $this->{hook} = RunLoop::Hook->new(
	sub {
	    $this->_main;
	})->install('before-select');

    $this;
}

# -----------------------------------------------------------------------------
# $obj->_main().
# (private)
#
sub _main 
{
  my $this = shift;

  #$DEBUG and print ">> ".__PACKAGE__."#_main($this) $this->{url} ...\n";
  #$DEBUG and print "<<sendbuf>>\n".$this->{socket}->sendbuf."<</sendbuf>>\n";;

  if( $this->{shutdown_wr_after_writing} && $this->{socket}->sendbuf eq '' )
  {
    $this->{shutdown_wr_after_writing} = undef;
    my $SHUT_WR = 1;
    $DEBUG and print __PACKAGE__."#_main, shutdown SHUT_WR.\n";
    $this->{socket}->shutdown($SHUT_WR);
  }

  my $progress = '';
  while( defined(my $line = $this->{socket}->pop_queue) )
  {
    # そうそうこないと思うけれど運悪くマッチしたとき.
    $progress .= $line . $this->{socket}->eol;
    $DEBUG and $this->_runloop->notify_msg(__PACKAGE__."#_main, matches with ".unpack("H*",$this->{socket}->eol));
  }
  $progress .= $this->{socket}->recvbuf;
  $this->{socket}->recvbuf = '';

  if( $progress ne '' )
  {
    my $status = eval { $this->{parser}->add($progress); };
    if( $@ )
    {
      # プロトコルエラー.
      $this->_end($@);
      return;
    }
    if( $status == 0 )
    {
      # 正常終了.
      $this->_end();
      return;
    }
    if( $this->{progress_callback} )
    {
      # 進展があったのでコールバック.
      $this->{progress_callback}->($this->{parser}->object);
      if( $this->{stopped} )
      {
        $DEBUG and print "<< (stopped) by progress_callback\n";
        return;
      }
    }
  }

  # 切断されていたら、ここで終わり。
  if( $this->{socket} && !$this->{socket}->connected )
  {
    $DEBUG and print "<< (disconnected)\n";
    my $success;
    if( $this->{parser}->isa('Tools::HTTPParser') )
    {
      my $st = $this->{parser}->object->{StreamState};
      $success = $st =~ /^(body|parsed)\z/ && $this->{parser}{rest} eq '';
    }else
    {
      $this->{parser}->object->content( $this->{parser}->data );
      $success = $this->{parser}->extra == 0;
    }
    if( $success )
    {
      $this->_end();
    }else
    {
      $this->_end("unexpected disconnect by server");
    }
    return;
  }

  # タイムアウト判定
  if( $this->{expire_time} and time >= $this->{expire_time} )
  {
    $this->_end("timeout");
    return;
  }
  #$DEBUG and print ">> ".__PACKAGE__."#_main leave.\n";
}

# -----------------------------------------------------------------------------
# $obj->_end().
# $obj->_end($errmsg).
# (private)
#
sub _end {
    my ($this, $err) = @_;

    $this->stop;
    
    if ($err) {
      $this->{callback}->($err);
    }
    else {
      my $res = $this->{parser}->object;
      if( UNIVERSAL::isa($res, 'HTTP::Message') )
      {
        $DEBUG and print __PACKAGE__."#_end($this) .. convert from lwp\n";
        $res = Tools::HTTPParser->_from_lwp($res);
      }
      $DEBUG and print __PACKAGE__."#_end($this) .. callback with success\n";
      $this->{callback}->($res);
    }
}

sub _delay
{
  my $this = shift;
  my $sub  = shift;

  Timer->new(
    After => -1,
    Code  => $sub,
  )->install();
}

# -----------------------------------------------------------------------------
# $obj->alive_p().
#
sub alive_p {
    my $this = shift;
    defined $this->{socket};
}

# -----------------------------------------------------------------------------
# $obj->stop().
#
sub stop {
    my $this = shift;
    $DEBUG and print __PACKAGE__."#stop($this).\n";

    $this->{socket}->disconnect if $this->{socket} && $this->{socket}->connected;
    #$DEBUG and print __PACKAGE__."#stop($this) .. disconnect ok\n";
    $this->{hook}->uninstall if $this->{hook};
    #$DEBUG and print __PACKAGE__."#stop($this) .. hook.uninstall ok\n";
    $this->{timeout_timer}->uninstall if $this->{timeout_timer};
    #$DEBUG and print __PACKAGE__."#stop($this) .. timer.uninstall ok\n";

    $this->{stopped} = 1;

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
