# -*- cperl -*-
# $Id$
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# エイリアスのように、HashをレコードとしたDBを管理する。

# - 情報(注意) -
#  * キー名に半角スペースは含められません。 error が出ます。
#  * 値の先頭、最後にある空白文字(\s)は読み込み時に消失します。
#  * 機能不足です。
#  * コードが読みにくいです。

# technical information
#  - datafile format
#    | abc: def
#      -> key 'abc', value 'def'
#    | : abc : def
#      -> key ':abc:', value 'def'
#    LINE := KEY ANYSPACES [value] ANYSPACES が基本。
#    KEY := ANYSPACES [keyname] ANYSPACES ':' || ANYSPACES ':' [keyname] ':'
#    ANYSPACES := REGEXP:\s*
#    [keyname] にはコロンをスペースに変換したキー名が入る。
#      キー名の先頭または最後にスペースがある場合は、KEYの後者のフォーマットを使用する。
#    [value] はそのまま。つまり複数行になるデータは追加できない。エラーを出すべきか?

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
  # コンストラクタ

  # - 引数 -
  # $fpath	: 保存するファイルのパス。空ファイル or undef でファイルに関連付けられないDBが作成されます。
  # $primary_key
  # 		: 主キーを設定します。データベース的な利点はまったくありません(笑)が、適当に作って下さい。
  # 		  要望があれば将来、$split_primaryが指定されてない場合は、undefでも良いようにするかもしれません。
  # $charset	: ファイルの文字セットを指定します。省略すれば UTF-8 になります。
  # $split_primary
  # 		: true なら、データファイルからの読み込み時に、$primary_keyで区切ります。
  # 		  そうでなければデータの無い行が区切りになります。省略されれば false です。
  # $use_re	: 値の検索/一致判定に正規表現拡張を使うかどうか。省略されれば使いません。
  # $ignore_proc
  # 		: 無視する行を指定するクロージャ。行を引数に呼び出され、 true が返ればその行を無視します。
  # 		  ここで ignore された行は解析さえ行いませんので、
  # 		  $split_primary=0でも区切りと認識されたりはしません。
  # 		  一般的な注意として、この状態のデータベースが保存された場合は ignore された行は全て消滅します。

  my ($class,$fpath,$primary_key,$charset,$split_primary,$use_re,$ignore_proc) = @_;

  croak('primary_key name "'.$primary_key.'" include space!') if $primary_key =~ / /;

  my $obj = 
    {
     time => undef, # ファイルの最終読み込み時刻
     fpath => $fpath,
     primarykey => $primary_key,
     splitprimary => $split_primary || 0,
     charset => $charset || 'utf8', # ファイルの文字コード
     use_re => $use_re || 0,
     ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },

     database => undef, # ARRAY<HASH*>
     # <キー SCALAR,値の集合 ARRAY<SCALAR>>
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
	  # \s が先頭/最後にあった場合読み込みで消え去るのでそれを防止。
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
  # 見付からなければundefを返す。
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
  # データベースにグループを追加する。
  # 常に成功し 1(true) が返る。

  # key に space が含まれないかチェックすべきだが、とりあえずはしていない。
  my ($this, @groups) = @_;
  push @{$this->{database}}, @groups;

  $this->synchronize();

  return 1;
}

sub add_value {
  # グループに値を追加する。
  # 成功すれば 1(true) が返る。
  # 不正なキーのため失敗した場合は 0(false) が返る。

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

  # 追加。あるか？
  my $group = $this->find_group_with_primary($primary);

  if (defined $group) {
    # found.
    return $this->add_value($group, $key, $value);
  } else {
    # 無かった場合、primarykeyだけは追加が許される。
    if ($key eq $this->{primarykey}) {
      # primarykey の値と $value が一致するかチェック。
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

  # あった。
  my $values = $group->{$key};
  if (defined $values) {
    my ($count) = scalar @$values;
    if (defined $value) {
      @$values = grep {
	$_ ne $value;
      } @$values;
      $count -= scalar(@$values);
      # この項目が空になったら項目自体を削除
      if (@$values == 0) {
	delete $group->{$key};
      }
    } else {
      # $value が指定されていない場合は項目削除
      delete $group->{$key};
    }

    # これがprimarykeyで、かつ空になったらそのものを削除
    $this->clean_up if $key eq $this->{primarykey};

    $this->synchronize();

    return $count; # deleted
  }
  return 0; # not deleted
}

sub del_value_with_primary {
  my ($this, $primary, $key, $value) = @_;

  # 削除。あるか？
  my $group = $this->find_group_with_primary($primary);

  if (defined $group) {
    return $this->del_value($group, $key, $value);
  }
  return 0; # not deleted
}

sub clean_up {
  # primarykeyが一つもないエイリアスを削除する。
  my ($this) = @_;
  @{$this->{database}} = grep {
    my $primary = $_->{$this->{primarykey}};
    defined $primary && @$primary > 0;
  } @{$this->{database}};
}


# group misc functions
sub dup_group {
  # グループの複製を行います。

  my ($group) = @_;
  my ($new_group) = {};

  return undef unless defined($group);

  map {
    $new_group->{$_} = $group->{$_};
  } keys(%$group);

  return $new_group;
}

sub concat_string_to_key {
  # prefix や suffix を group の key に付加します。

  # - 引数 -
  # $group	: グループ。
  # $prefix	: prefix 文字列 ('to.' とか 'from.' とか)
  # $suffix	: suffix 文字列
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
  # マクロの置換を行なう。%optionalは置換に追加するキーと値の組みで、省略可。
  # $callbacksはgroup/optionalで置換できなかった際に呼び出されるコールバック関数のリファレンス。
  # optionalの値はSCALARでもARRAY<SCALAR>でも良い。
  my ($this,$primary,$str,$callbacks,%optional) = @_;
  my $main_table = $this->find_group_with_primary($primary) || {};
  return Tools::HashTools::replace_recursive($str,[$main_table,\%optional],$callbacks);
}


1;
