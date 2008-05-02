## ----------------------------------------------------------------------------
#  Tools::HTTPClient::SSL.
#  適当ごしらえのHTTPClient用SSLサポート.
#  before-select Hook で pop_queue() が呼ばれる動作のみを想定.
#
#  LinedINETSocket の I/F を適当に実装.
#  但し基底クラスはなにもなし(IO::Socketでもない).
#  Tiarra::Socket系で対処した方がいいのだろうけれど….
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Tools::HTTPClient::SSL;
use strict;
use warnings;

our $HAS_SSL;
our $DEFAULT_EOL = "\r\n";

1;

# -----------------------------------------------------------------------------
# $pkg->new().
#
sub new
{
  my $pkg  = shift;
  my $eol  = shift || $DEFAULT_EOL;

  my $this = bless {}, $pkg;
  $this->{eol}  = $eol;
  $this->{host} = undef;
  $this->{port} = undef;
  $this->{ssl}  = undef;
  $this->{queue}   = [];
  $this->{recvbuf} = '';
  $this->{eof}     = undef;
  $this->{timer}   = undef;

  defined($HAS_SSL) or $this->_load_ssl();

  $this;
}

sub _load_ssl
{
  eval
  {
    local($SIG{__DIE__}) = 'DEFAULT';
    require IO::Socket::SSL;
    1;
  };
  $HAS_SSL = $@ ? 0 : 1;
  $HAS_SSL;
}


# -----------------------------------------------------------------------------
# $obj->DESTROY().
#
sub DESTROY
{
  my $this = shift;
  if( my $timer = $this->{timer} )
  {
    $timer->uninstall;
    $this->{timer} = undef;
  }
}

# -----------------------------------------------------------------------------
# $obj->connect($host, $port).
#
sub connect
{
  my $this  = shift;
  my $host  = shift;
  my $port  = shift;

  $this->{host} = $host;
  $this->{port} = $port;
  $this->{ssl}  = IO::Socket::SSL->new(
    PeerHost => $host,
    PeerPort => $port,
    ($^O eq 'MSWin32' ? () : (Blocking => 0)),
  );
  if( !$this->{ssl} )
  {
    $@ = IO::Socket::SSL::errstr();
  }

  # select() を抜けるためだけのtimer.
  # HTTPClient が before-select Hook で動作を起こすので,
  # そのトリガ用.
  $this->{timer} = Timer->new(
    Interval => 1,
    Code     => sub{},
    Repeat   => 1
  )->install;

  $this;
}

# -----------------------------------------------------------------------------
# $obj->sock().
#
sub sock
{
  my $this = shift;
  $this->{ssl};
}

# -----------------------------------------------------------------------------
# $obj->connected().
#
sub connected
{
  my $this = shift;
  $this->{ssl} && !$this->{eof};
}

# -----------------------------------------------------------------------------
# $obj->disconnect().
#
sub disconnect
{
  my $this = shift;
  $this->{ssl} = undef;
}

# -----------------------------------------------------------------------------
# $obj->send_reserve($line).
#
sub send_reserve
{
  my $this = shift;
  my $line = shift;
  print {$this->{ssl}} $line."\r\n";
}

# -----------------------------------------------------------------------------
# $obj->sendbuf().
#
sub sendbuf
{
  my $this = shift;
  return "";
}

# -----------------------------------------------------------------------------
# $obj->shutdown($SHUT_WR).
#
sub shutdown
{
  my $this = shift;
  return;
}

# -----------------------------------------------------------------------------
# $line = $obj->pop_queue().
#
sub pop_queue
{
  my $this = shift;
  my $queue = $this->{queue};

  if( !@$queue )
  {
    # 通常なら自分で tiarra-socket/read() コールバックで
    # 読み込んでおくけれど, 手抜き実装につきここでread.
    $this->_recv();
    $this->_fill_queue();
  }
  shift @$queue;
}

# -----------------------------------------------------------------------------
# $obj->recvbuf().
#
sub recvbuf:lvalue
{
  my $this = shift;
  $this->{recvbuf};
}

# -----------------------------------------------------------------------------
# $obj->eol().
# $obj->eol($eol).
#
sub eol
{
  my $this = shift;
  @_ and $this->{eol} = shift;
  $this->{eol};
}

# -----------------------------------------------------------------------------
# $obj->_recv().
# recvbuf にデータを読み込み.
# Tiarra::Socket::Buffered の read() に相当.
#
sub _recv
{
  my $this = shift;
  my $ssl  = $this->{ssl};

  $this->{eof} and return;

  for(;;)
  {
    my $r = $ssl->read(my $buf, 1024);
    if( !defined($r) )
    {
      my $e = $ssl->errstr;
      #print "read: $e\n";
      if( $e =~ /SSL wants a read first!/ )
      {
        last;
      }
      if( $e eq 'SSL read errorerror:00000000:lib(0):func(0):reason(0)' )
      {
        $this->{eof} = 1;
        last;
      }
      die __PACKAGE__."#_recv, ".$e;
    }
    if( !$r )
    {
      $this->{eof} = 1;
      last;
    }
    #print "read: $r\n";
    $this->{recvbuf} .= $buf;
  }
  1;
}


# -----------------------------------------------------------------------------
# $obj->_fill_queue().
# recvbuf にたまっているデータを行分割して queue に投入.
# Tiarra::Socket::Lined の read() に相当.
#
sub _fill_queue
{
  my $this  = shift;
  my $queue = $this->{queue};
  my $eol   = $this->{eol} || $DEFAULT_EOL;
  my $eol_len = length($eol);
  while( $this->{recvbuf} =~ /^(.*?)\Q$eol/ )
  {
    my $line_len = length($1);
    push(@$queue, substr($this->{recvbuf}, 0, $line_len));
    substr($this->{recvbuf}, 0, $line_len+$eol_len, '');
  }
}

# -----------------------------------------------------------------------------
# End of Module.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# End of File.
# -----------------------------------------------------------------------------
__END__

=encoding utf8

=for stopwords
	YAMASHINA
	Hio
	ACKNOWLEDGEMENTS
	AnnoCPAN
	CPAN
	RT

