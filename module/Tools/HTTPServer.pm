## ----------------------------------------------------------------------------
#  Tools::HTTPServer.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Tools::HTTPServer;
use strict;
use warnings;
use Tiarra::Socket;
use base 'Tiarra::Socket';

use Tools::HTTPServer::Client;
use Module::Use qw(Tools::HTTPServer::Client);

use Scalar::Util qw(weaken);

our $DEBUG = 0;

1;

# -----------------------------------------------------------------------------
# $pkg->new().
#
sub new
{
  my $pkg  = shift;
  my %opts = @_;
  $pkg->_increment_caller(__PACKAGE__, \%opts);
  my $this   = $pkg->SUPER::new(%opts);

  $this->{host}   = undef;
  $this->{port}   = undef;
  $this->{listen} = undef;
  $this->{path}   = undef;

  $this->{clients} = [];
  $this->{callback_object} = undef;

  $this;
}

# -----------------------------------------------------------------------------
# (destructor).
#
sub DESTROY
{
  my $this = shift;
  if( $this->sock )
  {
    $this->detach();
  }
}

# -----------------------------------------------------------------------------
# $obj->start(%opts).
# Host:   $host.
# Port:   $port.
# Listen: $backlog.
#
sub start
{
  my $this = shift;
  my $opts = {@_};

  $this->{host}   = $opts->{Host}   || '127.0.0.1';
  $this->{port}   = $opts->{Port}   || 8080;
  $this->{listen} = $opts->{Listen} || 5;

  # 処理するパス.
  # /path/to/process/ の最初も最後も / がついている形に正規化.
  my $path   = $opts->{Path} || '/';
  $path =~ m{^/} or $path = "/$path";
  $path =~ m{/$} or $path = "$path/";
  $this->{path} = $path;

  $this->{callback_object} = $opts->{CallbackObject};
  if( !$opts->{CallbackObjectNoWeaken} )
  {
    weaken($this->{callback_object});
  }

  my $sock = IO::Socket::INET->new(
    LocalHost => $this->{host},
    LocalPort => $this->{port},
    Listen    => $this->{listen},
    ReuseAddr => 1,
  );

  if( $sock )
  {
    $this->attach($sock);
    $this->install();

    my $pkg   = ref($this);
    my $name  = $this->name;
    my $where = $this->where;
    $name =~ s/^(?:\Q$pkg\E)?/$pkg ($where)/;
    $this->name($name);
  }

  $this;
}

# -----------------------------------------------------------------------------
# $loc = $obj->where().
# $loc = 'http://host:port/path/'.
#
sub where
{
  my $this = shift;
  if( $this->sock )
  {
    my $host = $this->{host};
    my $port = $this->{port};
    my $path = $this->{path};
    "http://$host:$port$path";
  }else
  {
    undef;
  }
}

# -----------------------------------------------------------------------------
# (impl:tiarra-socket)
#
sub want_to_write { 0 }
#sub write         {} # never used.
#sub exception     {} # never used.
sub read
{
  my $this = shift;

  my $sock = $this->sock->accept();
  if( !$sock )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__.", accept failed: $!/$@");
    return;
  }

  $this->_on_accept($sock);
}

sub close
{
  my $this = shift;
  $this->SUPER::close(@_);

  my $list = $this->{clients};
  foreach my $cli (@$list)
  {
    $cli and $cli->close();
  }
  @$list = ();
}

# -----------------------------------------------------------------------------
# $this->_on_accept($sock).
# (private).
#
sub _on_accept
{
  my $this = shift;
  my $sock  = shift;

  # 接続元制限とかいれたければこのあたりでいれてもいいのかも？

  $this->_start_client($sock);
}

# -----------------------------------------------------------------------------
# $this->_start_client($sock).
#
sub _start_client
{
  my $this = shift;
  my $sock = shift;

  my $peer = $sock->peerhost.':'.$sock->peerport;
  $DEBUG and $this->_debug("start client $peer");

  my $cli = Tools::HTTPServer::Client->new();
  push(@{$this->{clients}}, $cli);

  $cli->start(
    Socket         => $sock,
    CallbackObject => $this,
  );

  $this;
}

# -----------------------------------------------------------------------------
# (impl:callback-from-Tools::HTTPServer::Client).
#
sub _on_request
{
  my $this = shift;
  my $cli  = shift;
  my $req  = shift;

  # このオブジェクトからのコールバックを起動.
  my $par  = $this->{callback_object};
  if( !$par )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."->_on_request(), no callback_object");
    return;
  }
  $par->_on_request($cli, $req);
}

# -----------------------------------------------------------------------------
# (impl:callback-from-Tools::HTTPServer::Client).
#
sub _on_close_client
{
  my $this = shift;
  my $cli  = shift;

  # 保持しているクライアント一覧から除去.
  my $list = $this->{clients};
  @$list = grep { $_ && $_ ne $cli } @$list;

  # このオブジェクトからのコールバックを起動.
  my $par  = $this->{callback_object};
  if( !$par )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."->_on_close_client(), no callback_object");
    return;
  }
  my $sub = $par->can('_on_close_client');
  if( $sub )
  {
    $par->$sub($cli);
  }
}

# -----------------------------------------------------------------------------
# $this->_debug($msg).
#
sub _debug
{
  my $this = shift;
  my $msg = shift;
  RunLoop->shared_loop->notify_msg($msg);
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

