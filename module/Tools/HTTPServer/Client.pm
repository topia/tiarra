## ----------------------------------------------------------------------------
#  Tools::HTTPServer.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Tools::HTTPServer::Client;
use strict;
use warnings;
use Tiarra::Socket::Buffered;
use base 'Tiarra::Socket::Buffered';
use Tools::HTTPParser;
use Module::Use qw(Tools::HTTPParser);

use Scalar::Util qw(weaken);

our $HAS_HTTP_PARSER ||= do{
  eval {
    local($SIG{__DIE__}) = "DEFAULT";
    require HTTP::Parser;
    1;
  };
  $@ ? 0 : 1;
};
print __PACKAGE__."#INIT, has HTTP::Parser: ".($HAS_HTTP_PARSER?"yes":"no")."\n";

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

  $this->{callback_object} = undef;
  if( $HAS_HTTP_PARSER )
  {
    $this->{parser} = HTTP::Parser->new(request=>1);
  }else
  {
    $this->{parser} = Tools::HTTPParser->new(request=>1);
  }

  $this;
}

# -----------------------------------------------------------------------------
# $obj->start(%opts).
# $opts{Socket}         = $sock. # IO::Socket.
# $opts{CallbackObject} = $obj.  # Tools::HTTPServer.
#
# callbacks:
#  $cbo->_on_request($cli, $req);
#  $cbo->_on_close_client($cli);
#
# on_request() には HTTPClient と似た形式のHASHREF が渡される.
#
# {
#   Protocol => 'HTTP/1.x',
#   Path     => "/path/to/request",
#   Method   => 'GET' / 'POST',
#   Header   => {}.
#   Content  => $content,
# };
#
sub start
{
  my $this = shift;
  my $opts = {@_};

  $this->attach($opts->{Socket});
  $this->install();

  $this->{callback_object} = $opts->{CallbackObject};
  if( !$opts->{CallbackObjectNoWeaken} )
  {
    weaken($this->{callback_object});
  }

  $this;
}

# -----------------------------------------------------------------------------
# (impl:tiarra-socket)
#
sub read
{
  my $this = shift;
  my $par  = $this->{callback_object};
  if( !$par )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."->read(), no callback_object");
    $this->close();
    return;
  }
  $this->SUPER::read(@_);
  my $recv = $this->recvbuf;
  $this->recvbuf = '';
  my $status = eval{ $this->{parser}->add($recv) };
  if( $@ )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."->read(), $@");
    $this->close();
    return;
  }
  if( $status == 0 )
  {
    my $req = $this->{parser}->object();
print Dumper($req);use Data::Dumper;
    if( UNIVERSAL::isa($req, 'HTTP::Message') )
    {
      $req = Tools::HTTPParser->_from_lwp($req);
    }
    $par->_on_request($this, $req);
  }elsif( $status == -2 )
  {
    #print "need line data\n";
  }elsif( $status == -1 )
  {
    #print "need more data\n";
  }else
  {
    # $status > 0
    #print "need $status byte(s)\n";
  }
}

# -----------------------------------------------------------------------------
# (impl:tiarra-socket)
#
sub close
{
  my $this = shift;
  my $par  = $this->{callback_object};
  $this->SUPER::close(@_);
  if( !$par )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."->close(), no callback_object");
    return;
  }
  $par->_on_close_client($this);
}

# -----------------------------------------------------------------------------
# $obj->response($res).
#
sub response
{
  my $this = shift;
  my $res  = shift;

  $this->append( Tools::HTTPParser->to_string($res) );

  $this;
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

