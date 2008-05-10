# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# エイリアスのように、HashをレコードとしたDBを管理する。
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.


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
use Tiarra::Encoding;
use Mask;
use Carp;
use Module::Use qw(Tools::Hash Tools::HashTools);
use Tools::Hash;
use Tools::HashTools;
use Tiarra::Utils;
use Tiarra::ModifiedFlagMixin;
use Tiarra::SessionMixin;
use base qw(Tiarra::SessionMixin);
use base qw(Tiarra::Utils);

sub new {
    # コンストラクタ

    # - 引数 -
    # $fpath	: 保存するファイルのパス。空ファイル or undef でファイルに関連付けられないDBが作成されます。
    # $primary_key
    # 		: 主キーを設定します。データベース的な利点はまったくありません(笑)が、適当に作って下さい。
    # 		  $split_primaryが指定されていない場合は undef を渡すことが出来ます。
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

    if (defined $primary_key) {
	if ($primary_key =~ / /) {
	    croak('primary_key name "'.$primary_key.'" include space!')
	}
    } else {
	croak('primary_key not defined, but split_primary is true!') if $split_primary;
    }

    my $this = {
	time => undef, # ファイルの最終読み込み時刻
	fpath => $fpath,
	primary_key => $primary_key,
	split_primary => $split_primary || 0,
	charset => $charset || 'utf8', # ファイルの文字コード
	use_re => $use_re || 0,
	ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },
	cleanup_queued => undef,

	caller_name => $class->simple_caller_formatter('GroupDB registered'),
	database => undef, # ARRAY<HASH*>
	# <キー SCALAR,値の集合 ARRAY<SCALAR>>
    };

    bless $this,$class;
    $this->clear_modified;
    $this->_session_init;
    $this->_load;
}

__PACKAGE__->define_attr_accessor(0,
				  qw(time fpath charset),
				  qw(primary_key split_primary),
				  qw(cleanup_queued));
__PACKAGE__->define_session_wrap(0,
				 qw(checkupdate synchronize cleanup));

sub name {
    my $this = shift;
    join('/', $this->{caller_name},
	 (defined $this->fpath ? $this->fpath : ()));
}

sub _load {
    my $this = shift;
    my $database = [];

    if (defined $this->fpath && $this->fpath ne '') {
	my $fh = IO::File->new($this->fpath,'r');
	if (defined $fh) {
	    my $current = {};
	    my $flush = sub {
		if ((!$this->split_primary && scalar(%$current)) ||
			(defined $this->primary_key &&
			     defined $current->{$this->primary_key})) {
		    push @{$database}, Tools::Hash->new($this, $current);
		    $current = {};
		}
	    };
	    my $unicode = Tiarra::Encoding->new;
	    foreach (<$fh>) {
		my $line = $unicode->set($_, $this->charset)->get;
		next if $this->{ignore_proc}->($line);
		my ($key,$value) = grep {defined($_)}
		    ($line =~ /^\s*(?:([^:]+?)\s*|:([^:]+?)):\s*(.+?)\s*$/);
		if (!defined $key || $key eq '' ||
			!defined $value || $value eq '') {
		    if (!$this->split_primary) {
			$flush->();
		    }
		} else {
		    # can use colon(:) on key, but cannot use space( ).
		    $key =~ s/ /:/g;
		    if ($this->split_primary &&
			    $key eq $this->primary_key) {
			$flush->();
		    }
		    push(@{$current->{$key}}, $value);
		}
	    }
	    $flush->();
	    $this->{database} = $database;
	    $this->set_time;
	    $this->clear_modified;
	    $this->dequeue_cleanup;
	}
    }
    return $this;
}

sub _match {
    my ($this, $value, $str) = @_;

    Mask::match_array($value, $str, 1, $this->{use_re}, 0);
}

sub _check_primary_key {
    my $this = shift;

    croak "primary_key not defined; can't use this method."
	unless defined $this->primary_key;
}

sub _check_no_primary_key {
    my $this = shift;

    croak "primary_key defined; can't use this method."
	if defined $this->primary_key;
}

sub _check_primary_key_dups {
    my ($this, @values) = @_;

    $this->_check_primary_key;
    defined $this->find_group_with_primary([@values]);
}

sub _checkupdate {
    my $this = shift;

    if (defined $this->fpath && $this->fpath ne '') {
	my $stat = stat($this->fpath);

	if (defined $stat && defined $this->time &&
		$stat->mtime > $this->time) {
	    $this->_load;
	    return 1;
	}
    }
    return 0;
}

sub queue_cleanup  { shift->cleanup_queued(1); }
sub dequeue_cleanup{ shift->cleanup_queued(0); }
sub set_time       { shift->time(CORE::time); }

sub _synchronize {
    my $this = shift;
    my $force = shift || 0;

    if (defined $this->fpath && $this->fpath ne '' &&
	    ($this->modified || $force)) {
	my $fh = IO::File->new($this->fpath,'w');
	if (defined $fh) {
	    my $unicode = Tiarra::Encoding->new;
	    foreach my $person (@{$this->{database}}) {
		my @keys = keys %{$person->data};
		if (defined $this->primary_key) {
		    @keys = grep { $_ ne $this->primary_key } @keys;
		    unshift(@keys, $this->primary_key);
		}
		my ($key, $values);
		foreach $key (@keys) {
		    $values = $person->data->{$key};
		    # can use colon(:) on key, but cannot use space( ).
		    $key =~ s/:/ /g;
		    # \s が先頭/最後にあった場合読み込みで消え去るのでそれを防止。
		    $key = ':' . $key if ($key =~ /^\s/ || $key =~ /\s$/);
		    map {
			my $line = "$key: " . $_ . "\n";
			$fh->print($unicode->set($line)->conv($this->{charset}));
		    } @$values
		}
		$fh->print("\n");
	    }
	    $this->set_time;
	    $this->clear_modified;
	    $this->dequeue_cleanup;
	}
    }
    return $this;
}

sub groups {
    my ($this) = @_;

    return @{$this->with_session(sub{ $this->{database}; })};
}

sub find_group_with_primary {
    # 見付からなければundefを返す。
    my ($this, $value) = @_;

    $this->_check_primary_key;
    return $this->find_group($this->primary_key, $value);
}

sub find_group {
    my ($this, $keys, $values) = @_;

    return $this->find_groups($keys, $values, 1);
}

sub find_groups_with_primary {
    my ($this, $value, $count) = @_;

    $this->_check_primary_key;
    return $this->find_groups([$this->primary_key], [$value], $count);
}

sub find_groups {
    # on not found return 'undef'
    # $keys is ref[array or scalar]
    # $values is ref[array or scalar]
    # $count is num of max found group, optional.
    my ($this, $keys, $values, $count) = @_;
    my (@ret);

    ($keys, $values) = map {
	if (!ref($_) || ref($_) ne 'ARRAY') {
	    [$_];
	} else {
	    $_;
	}
    } ($keys, $values);

    my ($return) = sub {
	if (wantarray) {
	    return @ret;
	} else {
	    return $ret[0] || undef;
	}
    };

    $this->with_session(
	sub {
	group_loop:
	    foreach my $group (@{$this->{database}}) {
		foreach my $key (@$keys) {
		    foreach my $value (@$values) {
			if ($this->_match($group->get_array($key), $value)) {
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
	});
}

sub find_group_with_hash {
    my ($this, $hash) = @_;

    return $this->find_groups_with_hash($hash, 1);
}

sub find_groups_with_hash {
    # on not found return 'undef'
    # $keys is hashref(key => scalar, key => [scalar, scalar, ...]).
    # $count is num of max found group, optional.
    my ($this, $hash, $count) = @_;
    my (@ret);

    my ($return) = sub {
	if (wantarray) {
	    return @ret;
	} else {
	    return $ret[0] || undef;
	}
    };

    $this->with_session(
	sub {
	group_loop:
	    foreach my $group (@{$this->{database}}) {
		foreach my $key (keys %$hash) {
		    my $values = $hash->{$key};
		    $values = [$values]
			unless defined ref($values) && ref($values) eq 'ARRAY';
		    foreach my $value (@$values) {
			next group_loop
			    unless $this->_match($group->get_array($key),
						 $value);
		    }
		}
		# ok all match!
		push(@ret, $group);
		if (defined($count) && ($count <= scalar(@ret))) {
		    return $return->();
		}
	    }
	    return $return->();
	});
}

sub new_group {
    my $this = shift;
    my (@primary_key_values) = @_;

    if (!@primary_key_values && defined $this->primary_key) {
	croak 'primary_key_values not defined! please pass value';
	if ($this->_check_primary_key_dups(@primary_key_values)) {
	    return undef;
	}
    } elsif (@primary_key_values && !defined $this->primary_key) {
	carp 'primary_key_values defined! ignore value...';
	@primary_key_values = ();
    }
    $this->with_session(
	sub {
	    my $group;
	    if (@primary_key_values) {
		$group = Tools::Hash->new($this, {
		    $this->primary_key => [@primary_key_values],
		});
	    } else {
		$group = Tools::Hash->new($this);
		$this->queue_cleanup;
	    }
	    push @{$this->{database}}, $group;
	    $this->set_modified;
	    $group;
	});
}

sub add_group {
    # データベースにグループを追加する。
    # 常に成功し 1(true) が返る。
    # sanity check が足りないので new_group を使うことを推奨します。

    # key に space が含まれないかチェックすべきだが、とりあえずはしていない。
    my ($this, @groups) = @_;
    $this->with_session(
	sub {
	    push @{$this->{database}}, map {
		if (ref($_) eq 'HASH') {
		    Tools::Hash->new($this, $_);
		} else {
		    $_;
		}
	    } @groups;
	    $this->set_modified;
	});

    return 1;
}

sub del_group {
    # データベースからグループを削除する。
    # グループを空にしてクリーンアップにまかせます。

    my ($this, @groups) = @_;
    $this->with_session(
	sub {
	    foreach my $group (@groups) {
		foreach ($group->keys) {
		    $group->del_key($_);
		}
	    }
	});

    return 1;
}

sub add_array_with_primary {
    my ($this, $primary, $key, @values) = @_;

    $this->_check_primary_key;
    $this->with_session(
	sub {
	    # 追加。あるか？
	    my $group = $this->find_group_with_primary($primary);

	    # primary_key の値に重複ができないかチェック。
	    if ($key eq $this->primary_key &&
		    $this->_check_primary_key_dups(@values)) {
		return 0;
	    }

	    if (defined $group) {
		# found.
		return $group->add_array($key, @values);
	    } else {
		# 1. 無かった場合、primary_keyだけは追加が許される。
		# 2. primary_key の値と @values が一致するかチェック。
		if ($key eq $this->primary_key &&
			$this->_match([@values], $primary)) {
		    $this->new_group(@values);
		    $this->set_modified;
		    # added
		    return 1;
		}
	    }
	    # not added
	    return 0;
	});
}

sub del_array_with_primary {
    my ($this, $primary, $key, @values) = @_;

    $this->_check_primary_key;
    $this->with_session(
	sub {
	    # 削除。あるか？
	    my $group = $this->find_group_with_primary($primary);

	    if (defined $group) {
		return $group->del_array($key, @values);
	    }
	    # not deleted
	    return 0;
	});
}

*add_value_with_primary = \&add_array_with_primary;
*del_value_with_primary = \&del_array_with_primary;

sub _cleanup {
    my $this = shift;
    my $force = shift || 0;

    if ($this->cleanup_queued || $force) {
	my $count = scalar @{$this->{database}};
	if (defined $this->primary_key) {
	    # primary_keyが一つもないエイリアスを削除する。
	    @{$this->{database}} = grep {
		my $primary = $_->{$this->primary_key};
		defined $primary && @$primary > 0;
	    } @{$this->{database}};
	} else {
	    # 中身が空のエイリアスを削除する。
	    @{$this->{database}} = grep {
		$_->keys;
	    } @{$this->{database}};
	}
	if ($count != (scalar @{$this->{database}})) {
	    $this->set_modified;
	}
	$this->dequeue_cleanup;
    }
}

sub _after_session_start {
    my $this = shift;
    $this->_checkupdate;
}

sub _before_session_finish {
    my $this = shift;
    $this->_cleanup;
    $this->_synchronize;
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

# deprecated interfaces
sub add_array {
    my ($this, $group, $key, @values) = @_;

    $group->add_array($key, @values);
}

sub del_array {
    my ($this, $group, $key, @values) = @_;

    $group->del_array($key, @values);
}

*add_value = \&add_array;
*del_value = \&del_array;

sub dup_group {
    # グループの複製を行います。

    my ($group) = @_;
    return undef unless defined($group);

    return $group->clone;
}

# group misc functions
sub concat_string_to_key {
    # prefix や suffix を group の key に付加します。

    # - 引数 -
    # $group	: グループ。
    # $prefix	: prefix 文字列 ('to.' とか 'from.' とか)
    # $suffix	: suffix 文字列
    my ($group, $prefix, $suffix) = @_;
    return dup_group($group)->manipulate_keyname(
	prefix => $prefix,
	suffix => $suffix,
       );
}

sub get_value_random {
    my ($group, $key) = @_;

    return $group->get_value_random($key);
}

sub get_value {
    my ($group, $key) = @_;

    return $group->get_value($key);
}

sub get_array {
    my ($group, $key) = @_;

    return $group->get_array($key);
}

1;
