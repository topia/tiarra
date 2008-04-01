## ----------------------------------------------------------------------------
#  Tools::HTTPClient::SSL.
#  適当ごしらえのHTTPClient用SSLサポート.
#  LinedINETSocket の I/F を適当に実装.
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

1;

# -----------------------------------------------------------------------------
# $pkg->new().
#
sub new
{
  my $pkg  = shift;
  my $this = bless {}, $pkg;
  $this->{host} = undef;
  $this->{port} = undef;
  $this->{ssl} = undef;
  $this->{queue}   = [];
  $this->{recvbuf} = '';
  $this->{eof}     = undef;

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
    Blocking => 0,
  );

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
# $line = $obj->pop_queue().
#
sub pop_queue
{
  my $this = shift;
  my $queue = $this->{queue};

  if( !@$queue )
  {
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
# $obj->_recv().
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
      die "EOF";
      last;
    }
    #print "read: $r\n";
    $this->{recvbuf} .= $buf;
  }
  1;
}


# -----------------------------------------------------------------------------
# $obj->_fill_queue().
#
sub _fill_queue
{
  my $this  = shift;
  my $queue = $this->{queue};
  my $eol   = "\r\n";
  while( $this->{recvbuf} =~ /^(.*?)$eol/ )
  {
    my $line_len = length($1);
    push(@$queue, substr($this->{recvbuf}, 0, $line_len));
    substr($this->{recvbuf}, 0, $line_len+length($eol), '');
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

