## ----------------------------------------------------------------------------
#  Tools::ID3Tag.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Tools::ID3Tag;
use strict;
use warnings;
use Unicode::Japanese;

our $VERSION = '0.01';

1;

# -----------------------------------------------------------------------------
# $info = $pkg->extract($content).
# $info->{version} = "2.x.x";
# $info->{title}   = $title  | undef;
# $info->{artist}  = $artist | undef;
# $info->{album}   = $album  | undef;
#
sub extract
{
  my $pkg     = shift;
  my $content = shift;

  if( $content !~ m{^ID3(.{7})}s )
  {
    return;
  }

  # ID3v2 tag.
  my ($major, $minor, $flags, $size) = unpack("CCCN", $1);
  my $ver = "2.$major.$minor";
  my $is_unsync       = $flags & (1 << 7);
  my $has_ex_header   = ($flags & (1 << 6)) && ($major >= 3);
  my $has_expermental = $flags & (1 << 5);
  my $has_footer      = $flags & (1 << 4);
  #$DEBUG and print "id3v2: version=$ver, flags=".(sprintf("%x",$flags)).", ex=".($has_ex_header?"yes":"no").", footer=".($has_footer?"yes":"no")."\n";

  if( $size < length($content) )
  {
    $content = substr($content, 0, $size);
  }

  my $offset = 10;
  my $info = {
    version => $ver,
    size    => $size,
    title   => undef,
    artist  => undef,
    album   => undef,
  };
  my $old_frameid = {
    TT2 => 'TIT2',
    TP1 => 'TPE1',
    TAL => 'TALB',
  };

  if( $has_ex_header )
  {
    my $ex_size = unpack("\@$offset N", $content);
    if( !$ex_size || $ex_size <= 6 || $offset + $ex_size > length($content) )
    {
      return;
    }
    #my $ex = substr($content, $offset, $size);
    $offset += $size;
  }

  # frames.
  for(;;)
  {
    my ($id, $size, $flags);
    my ($hsize, $hformat);
    if( $major == 2 )
    {
      # 2.2.x
      if( $offset + 6 > length($content) )
      {
        last;
      }
      ($id, $size) = unpack("\@$offset a3 a3", $content);
      $id    = $old_frameid->{$id} || $id;
      $size  = unpack("N", "\0".$size);
      $flags = 0;
      $offset += 6;
    }else
    {
      # 2.3.x-
      if( $offset + 10 > length($content) )
      {
        last;
      }
      ($id, $size, $flags) = unpack("\@$offset a4 N n", $content);
      $offset += 10;
    }
    if( $offset + $size > length($content) )
    {
      # over flow.
      last;
    }
    my $pack = substr($content, $offset, $size);
    $offset += $size;

    if( $id eq 'TIT2' )
    {
      $info->{title} = $pkg->_decode_text_normal($pack);
    }
    if( $id eq 'TPE1' )
    {
      $info->{artist} = $pkg->_decode_text_normal($pack);
    }
    if( $id eq 'TALB' )
    {
      $info->{album} = $pkg->_decode_text_normal($pack);
    }
  }
  $info;
}

sub _decode_text_normal
{
  my $pkg  = shift;
  my $pack = shift;

  defined($pack) && length($pack)>=1 or die "#_decode_text_normal, no input";

  my $type = unpack("C", substr($pack, 0, 1, ''));
  my $out;
  if( $type == 0 )
  {
    # local encoding.
    $out = Unicode::Japanese->new($pack, 'auto')->utf8;
  }elsif( $type == 1 )
  {
    # UTF-16 (with-BOM)
    $out = Unicode::Japanese->new($pack, 'auto')->utf8;
  }elsif( $type == 2 )
  {
    # UTF-16BE (without-BOM)
    $out = Unicode::Japanese->new($pack, 'utf16be')->utf8;
  }elsif( $type == 3 )
  {
    # UTF-8
    $out = $pack;
  }else
  {
    die "#_decode_text_normal, unsupported type: $type";
  }
  $out =~ s/\0+\z//;
  $out;
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

