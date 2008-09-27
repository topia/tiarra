## ----------------------------------------------------------------------------
#  Auto::FetchTitle::Plugin::TouhouReplay.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::FetchTitle::Plugin::TouhouReplay;
use strict;
use warnings;
use base 'Auto::FetchTitle::Plugin';

# 弾幕形STG, 東方シリーズのリプレイファイルの表示.
# my $replay = Touhou::ReplayFile->parse($response->{Content});
# my $reply = $replay->shortdesc();
# ##==> "東方風神録 HIO. 215,663,790 [Easy/魔理沙(貫通)/Clear]";

our $HAS_TOUHOU_REPLAYFILE = do{
  eval{ local($SIG{__DIE__}) = 'DEFAULT'; require Touhou::ReplayFile };
  @$ or Module::Use->import(qw(Touhou::ReplayFile));
  !$@;
};

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
    name => 'touhou-replay',
    'filter.prereq'   => \&filter_prereq,
    'filter.response' => \&filter_response,
  });
}

# -----------------------------------------------------------------------------
# $this->filter_prereq($ctx, $arg);
# (impl:fetchtitle-filter)
# touhou-replay/prereq.
#
sub filter_prereq
{
  my $this  = shift;
  my $ctx   = shift;
  my $arg   = shift;

  my $req =$arg->{req};

  if( !$HAS_TOUHOU_REPLAYFILE )
  {
    $DEBUG and $ctx->_debug($req, "debug: - - no Touhou::ReplayFile (private module)");
    return;
  }

  $ctx->_apply_recv_limit($req, 500*1024);

  $this;
}

# -----------------------------------------------------------------------------
# $this->filter_response($ctx, $arg).
# (impl:fetchtitle-filter)
# touhou-replay/response.
#
sub filter_response
{
  my $this  = shift;
  my $ctx   = shift;
  my $arg   = shift;

  my $req = $arg->{req};

  $HAS_TOUHOU_REPLAYFILE or return;

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

  my @opts;

  my $len = $req->{result}{content_length};
  if( defined($len) )
  {
    $len =~ s/(?<=\d)(?=(\d\d\d)+(?!\d))/,/g;
    $len = "$len bytes";
    push(@opts, $len);
  }

  my $replay = Touhou::ReplayFile->parse($response->{Content});
  my $reply = $replay->shortdesc();
  if( @opts )
  {
    $reply .= " (".join("; ",@opts).")";
  }
  $req->{result}{result} = $reply;
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

