#!/usr/bin/perl
# $Id$
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# This perl script for testing System::Inflate module.
#   please run on Tiarra Root Directory.
#     ex. perl test/inflate-test.perl
#   dependency:
#     cat and gzip, and 'pipe'
# this module now test only 'gzip'...

use strict;
use warnings;
use lib qw(module);
use System::Inflate;

sub main {
  my $obj = System::Inflate->shared;
  my $data = `cat module/System/Inflate.pm | gzip -9c`;
  my @data;

  while (length $data != 0) {
    push (@data, substr($data, 0, 40));
    substr($data, 0, 40) = '';
  }

  my $data_chunk = shift(@data);
  my $temp = $obj->init('test', 'gzip', \$data_chunk);

  die "can't initialize gzip!" unless (defined $temp);
  my $chunk;
  do {
      $data_chunk = shift(@data) if (length($data_chunk) == 0);
      ($chunk, $temp) = $obj->inflate('test', \$data_chunk);
      #print $chunk;
      #print '-----COMP_OK' if $temp == $obj->COMP_OK;
      #print '-----COMP_STREAM_END' if $temp == $obj->COMP_STREAM_END;
      #print '-----COMP_OTHER_ERR' if $temp == $obj->COMP_OTHER_ERR;
      #print "\n";
  } while ($temp == $obj->COMP_OK);
  die "check error!" unless $obj->check('test') == $obj->COMP_OK;
  die "finalize error!" unless $obj->final('test') == $obj->COMP_OK;

  print("check ok.\n");
  return 0;
}

exit main();
