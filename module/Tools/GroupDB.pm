# -*- cperl -*-
# $Id$
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# �����ꥢ���Τ褦�ˡ�Hash��쥳���ɤȤ���DB��������롣

# - ����(���) -
#  * ����̾��Ⱦ�ѥ��ڡ����ϴޤ���ޤ��� error ���Фޤ���
#  * �ͤ���Ƭ���Ǹ�ˤ������ʸ��(\s)���ɤ߹��߻��˾ü����ޤ���
#  * ��ǽ��­�Ǥ���
#  * �����ɤ��ɤߤˤ����Ǥ���

# technical information
#  - datafile format
#    | abc: def
#      -> key 'abc', value 'def'
#    | : abc : def
#      -> key ':abc:', value 'def'
#    LINE := KEY ANYSPACES [value] ANYSPACES �����ܡ�
#    KEY := ANYSPACES [keyname] ANYSPACES ':' || ANYSPACES ':' [keyname] ':'
#    ANYSPACES := REGEXP:\s*
#    [keyname] �ˤϥ����򥹥ڡ������Ѵ���������̾�����롣
#      ����̾����Ƭ�ޤ��ϺǸ�˥��ڡ�����������ϡ�KEY�θ�ԤΥե����ޥåȤ���Ѥ��롣
#    [value] �Ϥ��Τޤޡ��Ĥޤ�ʣ���Ԥˤʤ�ǡ������ɲäǤ��ʤ������顼��Ф��٤���?

package Tools::GroupDB;
use strict;
use warnings;
use IO::File;
use File::stat;
use Unicode::Japanese;
use Mask;
use Carp;
use Module::Use qw(Tools::HashTools);
use Tools::HashTools;

sub new {
  # ���󥹥ȥ饯��

  # - ���� -
  # $fpath	: ��¸����ե�����Υѥ������ե����� or undef �ǥե�����˴�Ϣ�դ����ʤ�DB����������ޤ���
  # $primary_key
  # 		: �祭�������ꤷ�ޤ����ǡ����١���Ū�������Ϥޤä�������ޤ���(��)����Ŭ���˺�äƲ�������
  # 		  ��˾������о��衢$split_primary�����ꤵ��Ƥʤ����ϡ�undef�Ǥ��ɤ��褦�ˤ��뤫�⤷��ޤ���
  # $charset	: �ե������ʸ�����åȤ���ꤷ�ޤ�����ά����� UTF-8 �ˤʤ�ޤ���
  # $split_primary
  # 		: true �ʤ顢�ǡ����ե����뤫����ɤ߹��߻��ˡ�$primary_key�Ƕ��ڤ�ޤ���
  # 		  �����Ǥʤ���Хǡ�����̵���Ԥ����ڤ�ˤʤ�ޤ�����ά������ false �Ǥ���
  # $use_re	: �ͤθ���/����Ƚ�������ɽ����ĥ��Ȥ����ɤ�������ά�����лȤ��ޤ���
  # $ignore_proc
  # 		: ̵�뤹��Ԥ���ꤹ�륯�����㡣�Ԥ�����˸ƤӽФ��졢 true ���֤�Ф��ιԤ�̵�뤷�ޤ���
  # 		  ������ ignore ���줿�Ԥϲ��Ϥ����Ԥ��ޤ���Τǡ�
  # 		  $split_primary=0�Ǥ���ڤ��ǧ�����줿��Ϥ��ޤ���
  # 		  ����Ū����դȤ��ơ����ξ��֤Υǡ����١�������¸���줿���� ignore ���줿�Ԥ����ƾ��Ǥ��ޤ���

  my ($class,$fpath,$primary_key,$charset,$split_primary,$use_re,$ignore_proc) = @_;

  croak('primary_key name "'.$primary_key.'" include space!') if $primary_key =~ / /;

  my $obj = 
    {
     time => undef, # �ե�����κǽ��ɤ߹��߻���
     fpath => $fpath,
     primarykey => $primary_key,
     splitprimary => $split_primary || 0,
     charset => $charset || 'utf8', # �ե������ʸ��������
     use_re => $use_re || 0,
     ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },

     database => undef, # ARRAY<HASH*>
     # <���� SCALAR,�ͤν��� ARRAY<SCALAR>>
    };

  bless $obj,$class;
  $obj->_load;
}

sub _load {
  my $this = shift;
  $this->{database} = [];

  if (defined $this->{fpath} && $this->{fpath} ne '') {
    my $fh = IO::File->new($this->{fpath},'r');
    if (defined $fh) {
      my $current = {};
      my $flush = sub {
	if (defined $current->{$this->{primarykey}}) {
	  push @{$this->{database}},$current;
	  $current = {};
	}
      };
      my $unicode = Unicode::Japanese->new;
      foreach (<$fh>) {
	my $line = $unicode->set($_, $this->{charset})->get;
	next if $this->{ignore_proc}->($line);
	my ($key,$value) = grep {defined($_)} ($line =~ /^\s*(?:([^:]+?)\s*|:([^:]+?)):\s*(.+?)\s*$/);
	if (!defined $key || $key eq '' ||
	    !defined $value || $value eq '') {
	  if (!$this->{splitprimary}) {
	    $flush->();
	  }
	}
	else {
	  $key =~ s/ /:/g; # can use colon(:) on key, but cannot use space( ).
	  if ($this->{splitprimary} && $key eq $this->{primarykey}) {
	    $flush->();
	  }
	  push(@{$current->{$key}}, $value);
	}
      }
      $flush->();
      $this->{time} = time();
    }
  }
  return $this;
}

sub checkupdate {
  my $this = shift;

  if (defined $this->{fpath} && $this->{fpath} ne '') {
    my $stat = stat($this->{fpath});

    if (defined $stat && $stat->mtime > $this->{time}) {
      $this->_load();
      return 1;
    }
  }
  return 0;
}

sub synchronize {
  my $this = shift;
  if (defined $this->{fpath} && $this->{fpath} ne '') {
    my $fh = IO::File->new($this->{fpath},'w');
    if (defined $fh) {
      my $unicode = Unicode::Japanese->new;
      foreach my $person (@{$this->{database}}) {
	while (my ($key,$values) = each %$person) {
	  $key =~ s/:/ /g; # can use colon(:) on key, but cannot use space( ).
	  # \s ����Ƭ/�Ǹ�ˤ��ä�����ɤ߹��ߤǾä����ΤǤ�����ɻߡ�
	  $key = ':' . $key if ($key =~ /^\s/ || $key =~ /\s$/);
	  map {
	    my $line = "$key: " . $_ . "\n";
	    $fh->print($unicode->set($line)->conv($this->{charset}));
	  } @$values
	}
	$fh->print("\n");
      }
      $this->{time} = time();
    }
  }
  return $this;
}

sub groups {
  my ($this) = @_;

  return @{$this->{database}};
}

sub find_group_with_primary {
  # ���դ���ʤ����undef���֤���
  my ($this, $value) = @_;

  return $this->find_group([$this->{primarykey}], \$value);
}

sub find_group {
  my ($this, $keys, $values) = @_;

  return $this->find_groups($keys, $values, 1);
}

sub find_groups_with_primary {
  my ($this, $value, $count) = @_;

  return $this->find_groups([$this->{primarykey}], \$value, $count);
}

sub find_groups {
  # on not found return 'undef'
  # $keys is ref[array or scalar]
  # $values is ref[array or scalar]
  # $count is num of max found group, optional.
  my ($this, $keys, $values, $count) = @_;
  my (@ret);

  if (ref($keys) eq 'SCALAR') {
    $keys = [$$keys];
  }
  if (ref($values) eq 'SCALAR') {
    $values = [$$values];
  }

  my ($return) = sub {
    if (wantarray) {
      return @ret;
    } else {
      return $ret[0] || undef;
    }
  };

  $this->checkupdate();
 group_loop:
  foreach my $group (@{$this->{database}}) {
    foreach my $key (@$keys) {
      foreach my $value (@$values) {
	if (Mask::match_array(\@{$group->{$key}}, $value, 1, $this->{use_re}, 0)) {
	  #match.
	  push(@ret, $group);
	  if (defined($count) && ($count <= scalar(@ret))) {
	    return $return->();
	  }
	  next group_loop; # next at $group loop.
	}
      }
    }
  }
  return $return->();
}

sub add_group {
  # �ǡ����١����˥��롼�פ��ɲä��롣
  # ��������� 1(true) ���֤롣

  # key �� space ���ޤޤ�ʤ��������å����٤��������Ȥꤢ�����Ϥ��Ƥ��ʤ���
  my ($this, @groups) = @_;
  push @{$this->{database}}, @groups;

  $this->synchronize();

  return 1;
}

sub add_value {
  # ���롼�פ��ͤ��ɲä��롣
  # ��������� 1(true) ���֤롣
  # �����ʥ����Τ��Ἲ�Ԥ������� 0(false) ���֤롣

  my ($this, $group, $key, $value) = @_;

  return 0 if $key =~ / /;

  my $values = $group->{$key};
  if (!defined $values) {
    $values = [];
    $group->{$key} = $values;
  }
  push @$values,$value;

  $this->synchronize();

  return 1;
}

sub add_value_with_primary {
  my ($this, $primary, $key, $value) = @_;

  # �ɲá����뤫��
  my $group = $this->find_group_with_primary($primary);

  if (defined $group) {
    # found.
    return $this->add_value($group, $key, $value);
  } else {
    # ̵���ä���硢primarykey�������ɲä�������롣
    if ($key eq $this->{primarykey}) {
      # primarykey ���ͤ� $value �����פ��뤫�����å���
      if (Mask::match_array([$value], $primary, 1, $this->{use_re}, 0)) {
	$this->add_group({
			  $key => [$value]
			 });
	return 1; # added
      }
    }
  }
  return 0; # not added
}

sub del_value {
  my ($this, $group, $key, $value) = @_;

  # ���ä���
  my $values = $group->{$key};
  if (defined $values) {
    my ($count) = scalar @$values;
    if (defined $value) {
      @$values = grep {
	$_ ne $value;
      } @$values;
      $count -= scalar(@$values);
      # ���ι��ܤ����ˤʤä�����ܼ��Τ���
      if (@$values == 0) {
	delete $group->{$key};
      }
    } else {
      # $value �����ꤵ��Ƥ��ʤ����Ϲ��ܺ��
      delete $group->{$key};
    }

    # ���줬primarykey�ǡ����Ķ��ˤʤä��餽�Τ�Τ���
    $this->clean_up if $key eq $this->{primarykey};

    $this->synchronize();

    return $count; # deleted
  }
  return 0; # not deleted
}

sub del_value_with_primary {
  my ($this, $primary, $key, $value) = @_;

  # ��������뤫��
  my $group = $this->find_group_with_primary($primary);

  if (defined $group) {
    return $this->del_value($group, $key, $value);
  }
  return 0; # not deleted
}

sub clean_up {
  # primarykey����Ĥ�ʤ������ꥢ���������롣
  my ($this) = @_;
  @{$this->{database}} = grep {
    my $primary = $_->{$this->{primarykey}};
    defined $primary && @$primary > 0;
  } @{$this->{database}};
}


# group misc functions
sub dup_group {
  # ���롼�פ�ʣ����Ԥ��ޤ���

  my ($group) = @_;
  my ($new_group) = {};

  return undef unless defined($group);

  map {
    $new_group->{$_} = $group->{$_};
  } keys(%$group);

  return $new_group;
}

sub concat_string_to_key {
  # prefix �� suffix �� group �� key ���ղä��ޤ���

  # - ���� -
  # $group	: ���롼�ס�
  # $prefix	: prefix ʸ���� ('to.' �Ȥ� 'from.' �Ȥ�)
  # $suffix	: suffix ʸ����
  my ($group, $prefix, $suffix) = @_;
  my ($new_group) = {};

  $prefix = '' unless defined($prefix);
  $suffix = '' unless defined($suffix);

  map {
    $new_group->{$prefix . $_ . $suffix} = $group->{$_};
  } keys(%$group);

  return $new_group;
}

sub get_value_random {
  my ($group, $key) = @_;

  return Tools::HashTools::get_value_random($group, $key);
}

sub get_value {
  my ($group, $key) = @_;

  return Tools::HashTools::get_value($group, $key);
}

sub get_array {
  my ($group, $key) = @_;

  return Tools::HashTools::get_array($group, $key);
}

# replace support functions
sub replace_with_callbacks {
  # �ޥ�����ִ���Ԥʤ���%optional���ִ����ɲä��륭�����ͤ��Ȥߤǡ���ά�ġ�
  # $callbacks��group/optional���ִ��Ǥ��ʤ��ä��ݤ˸ƤӽФ���륳����Хå��ؿ��Υ�ե���󥹡�
  # optional���ͤ�SCALAR�Ǥ�ARRAY<SCALAR>�Ǥ��ɤ���
  my ($this,$primary,$str,$callbacks,%optional) = @_;
  my $main_table = $this->find_group_with_primary($primary) || {};
  return Tools::HashTools::replace_recursive($str,[$main_table,\%optional],$callbacks);
}


1;
