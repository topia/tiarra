# -*- cperl -*-
# $Clovery: tiarra/module/System/Inflate/Gzip.pm,v 1.1 2003/02/09 18:54:54 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package System::Inflate::Gzip;
use strict;
use warnings;
use Carp;
use base qw(System::Inflate::Zlib);

sub new {
  my ($obj) = $_[0]->SUPER::new(@_);

  $obj->{accept} = 'gzip';

  return $obj;
}

sub setup {
  my ($this, $parent) = @_;

  foreach my $compressor qw(gzip) {
    $parent->{compressor}->{$compressor} = $this;
    $this->{parent} = $parent;
  }

  return $parent;
}

sub init {
  my ($this, $datas, $data_chunk) = @_;
  my $ret = $this->SUPER::init($datas, $data_chunk);

  if ($ret == $this->parent->COMP_OK) {
    $datas->{data} = 
      {
       crc32 => undef,
       len => undef,
       data_len => 0,
       data_crc32 => undef,
      };
    $datas->{lasterr} = Compress::Zlib::_removeGzipHeader($data_chunk);
    return undef if $datas->{lasterr} != $this->{Z_OK};
    return $this->parent->COMP_OK if $datas->{lasterr} == $this->{Z_OK};
    return $this->parent->COMP_OTHER_ERR;
  } else {
    return $ret;
  }
}

sub inflate {
  my ($this, $datas, $data_chunk) = @_;
  my ($ret, $err);

  ($ret, $err) = $this->SUPER::inflate($datas, $data_chunk);

  $datas->{data}->{data_len} += length($ret);
  $datas->{data}->{data_crc32} = Compress::Zlib::crc32($ret, $datas->{data}->{data_crc32});
  if ($datas->{lasterr} == $this->{Z_STREAM_END}) {
    ($datas->{data}->{crc32}, $datas->{data}->{len}) = unpack ("VV", substr($$data_chunk, 0, 8));
    substr($$data_chunk, 0, 8) = '';
  }
  return ($ret, $err);
}

sub check {
  my ($this, $datas) = @_;
  my ($compdata) = $datas->{data};

  return undef unless defined($compdata->{len}) && defined($compdata->{crc32});
  return $this->parent->COMP_DATA_ERROR unless 
    ($compdata->{len} == $compdata->{data_len}) && ($compdata->{crc32} == $compdata->{data_crc32});
  return $this->parent->COMP_OK;
}
1;
