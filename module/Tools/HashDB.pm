# -*- cperl -*-
# $Clovery: tiarra/module/Tools/HashDB.pm,v 1.2 2003/07/24 03:05:47 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# GroupDB の1レコード分のデータを保持する。

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

package Tools::HashDB;
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
    # $charset	: ファイルの文字セットを指定します。省略すれば UTF-8 になります。
    # $use_re	: 値の検索/一致判定に正規表現拡張を使うかどうか。省略されれば使いません。
    # $ignore_proc
    # 		: 無視する行を指定するクロージャ。行を引数に呼び出され、 true が返ればその行を無視します。
    # 		  ここで ignore された行は解析さえ行いませんので、
    # 		  $split_primary=0でも区切りと認識されたりはしません。
    # 		  一般的な注意として、この状態のデータベースが保存された場合は ignore された行は全て消滅します。

    my ($class,$fpath,$charset,$use_re,$ignore_proc) = @_;

    my $obj = {
	time => undef,			# ファイルの最終読み込み時刻
	fpath => $fpath,
	charset => $charset || 'utf8',	# ファイルの文字コード
	use_re => $use_re || 0,
	ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },

	database => undef,		# HASH
    };

    bless $obj,$class;
    $obj->_load;
}

sub _load {
    my $this = shift;
    $this->{database} = {};

    if (defined $this->{fpath} && $this->{fpath} ne '') {
	my $fh = IO::File->new($this->{fpath},'r');
	if (defined $fh) {
	    my $unicode = Unicode::Japanese->new;
	    foreach (<$fh>) {
		my $line = $unicode->set($_, $this->{charset})->get;
		next if $this->{ignore_proc}->($line);
		my ($key,$value) = grep {defined($_)} ($line =~ /^\s*(?:([^:]+?)\s*|:([^:]+?)):\s*(.+?)\s*$/);
		if (!defined $key || $key eq '' ||
			!defined $value || $value eq '') {
		    # ignore
		} else {
		    $key =~ s/ /:/g; # can use colon(:) on key, but cannot use space( ).
		    push(@{$this->{database}->{$key}}, $value);
		}
	    }
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
	    while (my ($key,$values) = each %{$this->{database}}) {
		$key =~ s/:/ /g; # can use colon(:) on key, but cannot use space( ).
		# \s が先頭/最後にあった場合読み込みで消え去るのでそれを防止。
		$key = ':' . $key if ($key =~ /^\s/ || $key =~ /\s$/);
		map {
		    my $line = "$key: " . $_ . "\n";
		    $fh->print($unicode->set($line)->conv($this->{charset}));
		} @$values
	    }
	    $this->{time} = time();
	}
    }
    return $this;
}

sub to_hashref {
    my $this = shift;

    $this->checkupdate();

    return $this->{database};
}

sub keys {
    my $this = shift;

    $this->checkupdate();

    return CORE::keys(%{$this->to_hashref});
}

sub values {
    my $this = shift;

    $this->checkupdate();

    return CORE::values(%{$this->to_hashref});
}

sub add_value {
    # 値を追加する。
    # 成功すれば 1(true) が返る。
    # 不正なキーのため失敗した場合は 0(false) が返る。

    my ($this, $key, $value) = @_;

    return 0 if $key =~ / /;

    $this->checkupdate();

    my $values = $this->{database}->{$key};
    if (!defined $values) {
	$values = [];
	$this->{database}->{$key} = $values;
    }
    push @$values,$value;

    $this->synchronize();

    return 1;
}

sub del_value {
    my ($this, $key, $value) = @_;

    $this->checkupdate();

    my $values = $this->{database}->{$key};
    if (defined $values) {
	# あった。
	my ($count) = scalar @$values;
	if (defined $value) {
	    @$values = grep {
		$_ ne $value;
	    } @$values;
	    $count -= scalar(@$values);
	    # この項目が空になったら項目自体を削除
	    if (@$values == 0) {
		delete $this->{database}->{$key};
	    }
	} else {
	    # $value が指定されていない場合は項目削除
	    delete $this->{database}->{$key};
	}

	$this->synchronize();

	return $count;		# deleted
    }
    return 0;			# not deleted
}

sub get_value_random {
    my ($this, $key) = @_;

    $this->checkupdate();
    return Tools::HashTools::get_value_random($this->{database}, $key);
}

sub get_value {
    my ($this, $key) = @_;

    $this->checkupdate();
    return Tools::HashTools::get_value($this->{database}, $key);
}

sub get_array {
    my ($this, $key) = @_;

    $this->checkupdate();
    return Tools::HashTools::get_array($this->{database}, $key);
}


# group misc functions
sub dup_group {
    # グループの複製を行います。

    my ($group) = @_;
    my ($new_group) = {};

    return undef unless defined($group);

    map {
	$new_group->{$_} = $group->{$_};
    } CORE::keys(%$group);

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
    } CORE::keys(%$group);

    return $new_group;
}

# replace support functions
sub replace_with_callbacks {
    # マクロの置換を行なう。%optionalは置換に追加するキーと値の組みで、省略可。
    # $callbacksはgroup/optionalで置換できなかった際に呼び出されるコールバック関数のリファレンス。
    # optionalの値はSCALARでもARRAY<SCALAR>でも良い。
    my ($this,$str,$callbacks,%optional) = @_;
    my $main_table = %{$this->to_hashref};
    return Tools::HashTools::replace_recursive($str,[$main_table,\%optional],$callbacks);
}

1;
