# -*- cperl -*-
# $Clovery: tiarra/module/Tools/LinedDB.pm,v 1.2 2003/03/17 07:18:25 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Tools::LinedDB;
use strict;
use warnings;
use IO::File;
use File::stat;
use Unicode::Japanese;
use Mask;
use Carp;

sub new {
  my ($class, %arg) = @_;

  foreach my $key qw(Parse Build Compare Update Hash) {
    croak($key . ' should be undef or code reference!')
      unless !defined($arg{$key}) || (ref($arg{$key}) eq 'CODE');
  }

  # Compare も Hash も既定を使う場合は、 Hash には _do_nothing を使う。
  $arg{'Hash'} = \&_do_nothing if !defined($arg{'Compare'}) && !defined($arg{'Hash'});

  my $this =
    {
     database => [],
     fpath => $arg{'FilePath'},
     charset => $arg{'Charset'} || 'utf8',
     parse_func => $arg{'Parse'} || \&_do_nothing,
     build_func => $arg{'Build'} || \&_do_nothing,
     compare_func => $arg{'Compare'} || \&_do_compare_default,
     update_callback => $arg{'Update'} || \&_do_nothing,
     hash_func => $arg{'Hash'},
     time => undef, # ファイルの最終読み込み時刻
    };

  # Build が指定されているのに Compare が既定のときは build してから compare する。
  if (defined($arg{'Build'}) && !defined($arg{'Compare'})) {
    $this->{compare_func} = sub {
      return _do_compare_default(map {
	$this->{build_func}->($_);
      } @_);
    };
  }

  bless $this, $class;

  return $this->_load;
}

sub _load {
  my ($this) = @_;
  if (defined $this->{fpath} && $this->{fpath} ne '') {
    $this->{database} = [];
    my $fh = IO::File->new($this->{fpath},'r');
    if (defined $fh) {
      my $unicode = Unicode::Japanese->new;
      foreach my $line (<$fh>) {
	chomp $line;
	map {
	  push @{$this->{database}}, $_;
	} $this->{parse_func}->($unicode->set($line,$this->{charset})->get);
      }
      $this->{time} = time();
    }
  }

  $this->{update_callback}->();
  return $this;
}

sub synchronize {
  my ($this) = @_;
  if (defined $this->{fpath} && $this->{fpath} ne '') {
    my $fh = IO::File->new($this->{fpath},'w');
    if (defined $fh) {
      my $unicode = Unicode::Japanese->new;
      foreach my $line (@{$this->{database}}) {
	map {
	  $fh->print($unicode->set($_ . "\n")->conv($this->{charset}));
	} $this->{build_func}->($line);
      }
      $this->{time} = time();
    }
  }

  $this->{update_callback}->();
  return $this;
}

sub checkupdate {
  my ($this) = @_;

  if (defined $this->{fpath} && $this->{fpath} ne '') {
    my $stat = stat($this->{fpath});

    if (defined($stat) && ($stat->mtime > $this->{time})) {
      $this->_load();
    }
  }
}

sub length {
  my ($this) = @_;

  $this->checkupdate();
  return scalar(@{$this->{database}});
}

sub index {
  my ($this, $index) = @_;

  return $this->indexes($index);
}

sub indexes {
  my ($this, @indexes) = @_;

  $this->checkupdate();
  if (wantarray) {
    return map {
      $this->{database}->[$_];
    } @indexes;
  } else {
    return undef unless @indexes;
    return $this->{database}->[$indexes[0]];
  }
}

sub get_value {
  my ($this) = @_;

  $this->checkupdate();
  if (@{$this->{database}} == 0) {
    return undef;
  } else {
    my $idx = int(rand() * hex('0xffffffff')) % @{$this->{database}};
    return $this->index($idx);
  }
}

sub get_array {
  my ($this) = @_;

  $this->checkupdate();
  return @{$this->{database}};
}

sub set_value {
  my ($this, $index, $value) = @_;

  $this->checkupdate();
  $this->{database}->[$index] = $value;
  $this->synchronize();
  return $this;
}

sub set_array {
  my ($this, @array) = @_;

  $this->checkupdate();
  @{$this->{database}} = @array;
  $this->synchronize();
  return 0;
}

sub find_index {
  my ($this, $value) = @_;

  return $this->find_indexes($value, 1);
}

sub find_indexes {
  my ($this, $value, $count) = @_;
  my (@indexes) = ();

  my ($return) = sub {
    if (wantarray) {
      return @indexes;
    } else {
      return $indexes[0] || undef;
    }
  };

  my $raw_value = $value;
  $this->checkupdate();
  for ( my $i = (@{$this->{database}} - 1) ; $i >= 0 ; --$i ) {
    if ($this->{compare_func}->($this->{database}->[$i], $raw_value) == 0) {
      push(@indexes, $i);
      if (defined($count) && @indexes >= $count) {
	return $return->();
      }
    }
  }

  return $return->();
}

sub find_value {
  my ($this, $value) = @_;

  return $this->find_values($value, 1);
}

sub find_values {
  my ($this, $value, $count) = @_;

  return $this->indexes($this->find_indexes($value, $count));
}

sub add_value {
  my ($this, $value) = @_;

  $this->checkupdate();
  push(@{$this->{database}}, $value);
  $this->synchronize();

  return 1;
}

sub add_value_unique {
  my ($this, $value) = @_;

  if (!defined($this->find_value($value))) {
    return $this->add_value($value);
  }

  return 0;
}

sub del_value {
  my ($this, $value, $count) = @_;

  my $raw_value = $value;
  $this->checkupdate();
  my ($deleted_count) = 0;
  for ( my $i = (@{$this->{database}} - 1) ; $i >= 0 ; --$i ) {
    if ($this->{compare_func}->($this->{database}->[$i], $raw_value) == 0) {
      # equal. delete.
      splice(@{$this->{database}}, $i, 1);
      ++$deleted_count;
      if (defined($count) && $deleted_count >= $count) {
	$this->synchronize();
	return $deleted_count;
      }
    }
  }

  $this->synchronize();
  return $deleted_count;
}

sub del_value_single {
  my ($this, $value) = @_;

  return $this->del_value($value, 1);
}

sub simplify {
  my ($this) = @_;

  $this->checkupdate();
  if (defined($this->{hash_func})) {
    # hash mode.
    my (%buf);
    @{$this->{database}} = grep {
      if (defined($buf{$this->{hash_func}->($_)})) {
	# not found past.
	$buf{$this->{hash_func}->($_)} = 1;
	1;
      } else {
	0;
      }
    } @{$this->{database}};
  } else {
    # compare mode.

    # hash_func が登録されてない場合、hash を使った整理は compare_func の定義に依るので不可。
    # 単純に比較することになるため、非常に重くなるであろう。

    # 未実装。
    croak('not specified hash function. this mode hasn\'t implemented yet.');
  }

  $this->synchronize();
  return $this;
}

sub _do_nothing {
  # なにもせずただ値を返す
  return wantarray ? @_ : $_[0];
}

sub _do_compare_default {
  # デフォルトの比較関数。
  my ($a, $b) = @_;

  return ($a cmp $b);
}

1;
