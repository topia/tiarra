# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package System::Inflate::Zlib;
use strict;
use warnings;
use Carp;
use Compress::Zlib;

sub new {
  my ($class) = @_;
  my $obj = 
    {
     Z_OK => Compress::Zlib::Z_OK(),
     Z_STREAM_END => Compress::Zlib::Z_STREAM_END(),
     Z_DATA_ERROR => Compress::Zlib::Z_DATA_ERROR(),
     accept => 'inflate'
    };
  bless $obj,$class;
  return $obj;
}

sub setup {
  my ($this, $parent) = @_;

  foreach my $compressor qw(inflate) {
    $parent->{compressor}->{$compressor} = $this;
    $this->{parent} = $parent;
  }

  return $parent;
}

sub parent {
  return shift->{parent};
}

sub init {
  my ($this, $datas, $data_chunk) = @_;

  ($datas->{stream}, $datas->{lasterr}) = 
    Compress::Zlib::inflateInit(-WindowBits => - Compress::Zlib::MAX_WBITS());
  return undef if $datas->{lasterr} != $this->{Z_OK};
  return $this->parent->COMP_OK if $datas->{lasterr} == $this->{Z_OK};
  return $this->parent->COMP_OTHER_ERR;
}

sub inflate {
  my ($this, $datas, $data_chunk) = @_;
  my ($ret);

  carp('not initialized!') if !defined $datas->{stream};
  ($ret, $datas->{lasterr}) = $datas->{stream}->inflate($data_chunk);
  $datas->{stream} = undef if $datas->{lasterr} != $this->{Z_OK};
  return ($ret, $this->parent->COMP_OK) if $datas->{lasterr} == $this->{Z_OK};
  return ($ret, $this->parent->COMP_STREAM_END) if $datas->{lasterr} == $this->{Z_STREAM_END};
  return (undef, $this->parent->COMP_OTHER_ERR);
}

sub check {
  my ($this, $datas) = @_;

  return 1;
}

sub final {
  my ($this) = @_;

  return $this->parent->COMP_OK;
}

1;
