# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.

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
use Module::Use qw(Tools::Hash Tools::HashTools);
use Tools::Hash;
use Tools::HashTools;
use Tiarra::Utils;
use Tiarra::ModifiedFlagMixin;
use Tiarra::SessionMixin;
use base qw(Tiarra::SessionMixin);

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

    my $this = {
	time => undef,			# ファイルの最終読み込み時刻
	fpath => $fpath,
	charset => $charset || 'utf8',	# ファイルの文字コード
	use_re => $use_re || 0,
	ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },

	database => undef,		# HASH
    };

    bless $this,$class;
    $this->clear_modified;
    $this->_session_init;
    $this->_load;
}

__PACKAGE__->define_attr_accessor(0,
				  qw(time fpath charset),
				  qw(use_re));
__PACKAGE__->define_proxy('database', 0,
			  qw(keys values),
			  qw(add_value add_array del_value del_array),
			  qw(get_array get_value get_value_random));
__PACKAGE__->define_session_wrap(0,
				 qw(checkupdate synchronize cleanup));

sub _load {
    my $this = shift;

    my $database = Tools::Hash->new;

    if (defined $this->fpath && $this->fpath ne '') {
	my $fh = IO::File->new($this->fpath,'r');
	if (defined $fh) {
	    my $unicode = Unicode::Japanese->new;
	    foreach (<$fh>) {
		my $line = $unicode->set($_, $this->charset)->get;
		next if $this->{ignore_proc}->($line);
		my ($key,$value) = grep {defined($_)}
		    ($line =~ /^\s*(?:([^:]+?)\s*|:([^:]+?)):\s*(.+?)\s*$/);
		if (!defined $key || $key eq '' ||
			!defined $value || $value eq '') {
		    # ignore
		} else {
		    # can use colon(:) on key, but cannot use space( ).
		    $key =~ s/ /:/g;
		    $database->add_value($key, $value);
		}
	    }
	    $this->{database} = $database;
	    $this->set_time;
	    $this->clear_modified;
	}
    }
    return $this;
}

sub _checkupdate {
    my $this = shift;

    if (defined $this->fpath && $this->fpath ne '') {
	my $stat = stat($this->fpath);

	if (defined $stat && defined $this->time &&
		$stat->mtime > $this->time) {
	    $this->_load();
	    return 1;
	}
    }
    return 0;
}

sub _synchronize {
    my $this = shift;
    my $force = shift || 0;

    if (defined $this->fpath && $this->fpath ne '' &&
	    ($this->modified || $force)) {
	my $fh = IO::File->new($this->fpath,'w');
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
	    $this->set_time;
	    $this->clear_modified;
	}
    }
    return $this;
}

sub set_time       { shift->time(CORE::time); }

sub database {
    my $this = shift;
    return $this->with_session(sub{$this->{database};});
}
*to_hashref = \&database;

sub _before_session_start {
    my $this = shift;
    $this->_checkupdate;
}

sub _after_session_finish {
    my $this = shift;
    $this->_synchronize;
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
