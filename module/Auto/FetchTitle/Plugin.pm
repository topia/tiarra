## ----------------------------------------------------------------------------
#  Auto::FetchTitle::Plugin.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::FetchTitle::Plugin;
use strict;
use warnings;

use Scalar::Util qw(weaken);

1;

# -----------------------------------------------------------------------------
# $pkg->new(\%config).
#
sub new
{
  my $pkg = shift;
  my $config = shift;
  my $this = bless {}, $pkg;
  $this->{config} = $config;
  $this->{hook}   = undef;
  $this;
}

# -----------------------------------------------------------------------------
# $obj->register($context).
#
sub register
{
  my $this = shift;
  my $context = shift;

  #$context->register_hook($this, {
  #  name  => 'filter-name',
  #  'plugin.initialize' => \&plugin_initialize,
  #  'plugin.finalize'   => \&plugin_finalize,
  #  'filter.prereq'   => \&filter_prereq,
  #  'filter.response' => \&filter_response,
  #});
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

