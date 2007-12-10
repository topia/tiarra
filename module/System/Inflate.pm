# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package System::Inflate;
use strict;
use warnings;
use Carp;

use Tiarra::SharedMixin;
our $_shared_instance;

sub _new {
  my ($class) = @_;
  my $obj = 
    {
     datas => {}, # HASH<HASH*>; HASH key is [tag]
     # compressor: stream compressor
     # stream    : stream object
     # lasterr   : last error information
     # data      : compressor dependent datas
     compressor => {}, # HASH; compressor name => Process Classes
     const => 
     {
      COMP_OK => 0,
      COMP_STREAM_END => 1,
      COMP_DATA_ERR => -1,
      COMP_OTHER_ERR => -2
     }
    };
  bless $obj,$class;

  return $obj->_setup();
}

sub _setup {
  my ($this) = @_;

  foreach my $classname (map {'System::Inflate::' . $_} qw(Zlib Gzip)) {
    eval 'use ' . $classname;
    unless ($@) {
      eval $classname . '::setup(new ' . $classname . '(), $this)';
      if ($@) {
	print "------can't load $classname\n$@------\n";
      }
    } else {
      print "------can't load $classname\n$@------\n";
    }
  }

  return $this;
}

sub get_compclass {
  my ($this, $compressor) = @_;
  my ($compclass) = $this->shared->{compressor}->{$compressor};

  croak('compressor ' . $compressor . ' is not initialized!') unless defined $compclass;

  return $compclass
}

sub get_data_struct {
  my ($this, $tag) = @_;
  my ($datas) = $this->shared->{datas}->{$tag};

  croak('tag ' . $tag . ' is not initialized!') unless defined $datas;

  return $datas;
}

sub get_lasterr {
  my ($this, $tag) = @_;
  return $this->get_data_struct($tag)->{lasterr};
}

sub COMP_OK {
  return shift->{const}->{COMP_OK};
}

sub COMP_STREAM_END {
  return shift->{const}->{COMP_STREAM_END};
}

sub COMP_OTHER_ERR {
  return shift->{const}->{COMP_OTHER_ERR};
}

sub COMP_DATA_ERR {
  return shift->{const}->{COMP_DATA_ERR};
}

sub init {
  my ($this, $tag, $compressor, $data_chunk) = @_;
  my ($datas) = $this->shared->{datas}->{$tag} = 
    {
     stream => undef,
     compressor => $compressor,
     lasterr => undef,
     data => {}
    };

  return $this->get_compclass($compressor)->init($datas, $data_chunk);
}

sub inflate {
  my ($this, $tag, $data_chunk) = @_;
  my ($datas) = $this->get_data_struct($tag);

  return $this->get_compclass($datas->{compressor})->inflate($datas, $data_chunk);
}

sub check {
  my ($this, $tag) = @_;
  my ($datas) = $this->get_data_struct($tag);

  return $this->get_compclass($datas->{compressor})->check($datas);
}

sub final {
  my ($this, $tag) = @_;
  my ($datas) = $this->get_data_struct($tag);

  # ordinary void function
  my $ret = $this->shared->{compressor}->{$datas->{compressor}}->final($datas);
  return undef unless defined $ret; # return value is undef; maybe can't finalize....
  delete $this->shared->{datas}->{$tag};
  return $ret;
}

1;
