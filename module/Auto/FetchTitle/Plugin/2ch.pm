## ----------------------------------------------------------------------------
#  Auto::FetchTitle::Plugin::2ch.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::FetchTitle::Plugin::2ch;
use strict;
use warnings;
use base 'Auto::FetchTitle::Plugin';

our $DEBUG;
*DEBUG = \$Auto::FetchTitle::DEBUG;

1;

# -----------------------------------------------------------------------------
# $pkg->new(\%config).
#
sub new
{
  my $pkg   = shift;
  my $this = $pkg->SUPER::new(@_);
  $this;
}

# -----------------------------------------------------------------------------
# $obj->register($context).
#
sub register
{
  my $this = shift;
  my $context = shift;

  $context->register_hook($this, {
    name => '2ch',
    'filter.prereq'   => \&filter_prereq,
    'filter.response' => \&filter_response,
  });
}

# -----------------------------------------------------------------------------
# $this->filter_prereq($ctx, $arg);
# (impl:fetchtitle-filter)
# 2ch/prereq.
#
sub filter_prereq
{
  my $this  = shift;
  my $ctx   = shift;
  my $arg   = shift;

  my $req =$arg->{req};

  if( $req->{url} =~ m{^http://(\w+)\.2ch\.net/test/read\.(?:html|cgi)/(\w+)/(\d+)/} )
  {
    $req->{redirect} = "http://$1.2ch.net/$2/dat/$3.dat";
  }

  $this;
}

# -----------------------------------------------------------------------------
# $this->filter_response($ctx, $arg).
# (impl:fetchtitle-filter)
# 2ch/response.
#
sub filter_response
{
  my $this  = shift;
  my $ctx   = shift;
  my $arg   = shift;

  my $req = $arg->{req};

  my $response = $req->{response};
  if( !ref($response) )
  {
    $DEBUG and $ctx->_debug($req, "debug: - - skip/not ref");
    return;
  }
  if( $req->{result}{status_code}!=200 )
  {
    $DEBUG and $ctx->_debug($req, "debug: - - skip/not success:$req->{result}{status_code}");
    return;
  }

  if( $req->{url} !~ m{^http://\w+\.2ch\.net/\w+/dat/\d+\.dat\z} )
  {
    $DEBUG and $ctx->_debug($req, "debug: - - skip/not 2ch.dat");
    return;
  }

  my ($line) = $req->{result}{decoded_content} =~ /(.*)/ ? $1 : '';
  my ($name, $email, $date_id, $text, $title) = split(/<>/, $line);
  my ($date, $id) = $date_id && $date_id =~ /(.*) (.*)/ ? ($1, $2) : ($date_id, '');
  $title or return;

  $req->{result}{result} = $title;
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

