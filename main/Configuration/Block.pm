# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Configuration::Block;
use strict;
use warnings;
use vars qw($AUTOLOAD);
use UNIVERSAL;
use Tiarra::Encoding;
use Tiarra::DefineEnumMixin qw(BLOCK_NAME TABLE);
use Tiarra::Utils;
# 値を取得するにはgetメソッドを用いる他、エントリ名をそのままメソッドとして呼ぶ事も出来ます。
#
# $block->hoge;
# これでパラメータhogeの値を返す。hogeが未定義ならundef値を返す。
# hogeの値が一つだけだったらそれを返すが、複数の値が存在したらその先頭の値だけを返す。
# 値もブロックだったら、そのブロックを返す。
#
# $block->hoge('all');
# パラメータhogeの全ての値を配列で返す。hogeが未定義なら空の配列を返す。
# 値が一つしか無ければ値が一つの配列を返す。
#
# $block->foo_bar;
# $block->foo_bar('all');
# パラメータ"foo-bar"の値を返す。"foo_bar"ではない！
#
# $block->foo('random');
# パラメータfooに複数の定義があれば、そのうちの一つをランダムに返す。
# 一つも無ければundefを返す。
#
# $block->foo_bar('block');
# $block->get('foo-bar', 'block');
# パラメータ"foo-bar"の値が未定義である場合、undef値の代わりに
# 空のConfiguration::Blockを返す。
# 定義されている場合、その値がブロックであればそれを返すが、
# そうでなければ "foo-bar: その値" の要素を持ったブロックを生成し、それを返す。
#
# $block->get('foo_bar');
# $block->get('foo_bar','all');
# パラメータ"foo_bar"の値を返す。
#
# 以上の事から、Configuration::Blockはnew,block_name,table,set,get,
# reinterpret-encoding,AUTOLOADといった属性はget()でしか読めない。
# また、属性名にアンダースコアを持つ属性もget()でしか読めない。

sub new {
    my ($class,$block_name) = @_;
    my $obj = bless [] => $class;
    $obj->[BLOCK_NAME] = $block_name;
    $obj->[TABLE]      = {}; # ラベル -> 値(配列リファもしくはスカラー)
    $obj;
}

Tiarra::Utils->define_array_attr_accessor(0, qw(block_name table));

sub equals {
    # 二つのConfiguration::Blockが完全に等価なら1を返す。
    my ($this,$that) = @_;
    # ブロック名
    if ($this->[BLOCK_NAME] ne $that->[BLOCK_NAME]) {
	return undef;
    }
    # キーの数
    my @this_keys = sort keys %{$this->[TABLE]};
    my @that_keys = sort keys %{$that->[TABLE]};
    if (@this_keys != @that_keys) {
	return undef;
    }
    my $walk;
    $walk = sub {
	my ($this_value, $that_value) = @_;

	# 値の型
	if (ref($this_value) ne ref($that_value)) {
	    return undef;
	}

	# 値
	if (ref($this_value) eq 'ARRAY') {
	    # 配列なので要素数と全要素を比較。
	    if (@$this_value != @$that_value) {
		return undef;
	    }
	    my $valsize = @$this_value;
	    for (my $j = 0; $j < $valsize; $j++) {
		if (!$walk->($this_value->[$j], $that_value->[$j])) {
		    return undef;
		}
	    }
	}
	elsif (UNIVERSAL::isa($this_value,'Configuration::Block')) {
	    # ブロックなので再帰的に比較。
	    if (!$this_value->equals($that_value)) {
		return undef;
	    }
	}
	else {
	    if ($this_value ne $that_value) {
		return undef;
	    }
	}
	1;
    };

    # 各要素
    my $size = @this_keys;
    for (my $i = 0; $i < $size; $i++) {
	# キー
	if ($this_keys[$i] ne $that_keys[$i]) {
	    return undef;
	}
	# 値の型
	my $this_value = $this->[TABLE]->{$this_keys[$i]};
	my $that_value = $that->[TABLE]->{$that_keys[$i]};
	if (!$walk->($this_value, $that_value)) {
	    return undef;
	}
    }
    return 1;
}

sub _eval_code {
    # 渡された文字列中の、全ての%CODE{ ... }EDOC%を評価して返す。
    my ($this,$str) = @_;

    if (!defined($str) || ref($str)) {
	return $str; # 文字列でなかったらそのまま返す。
    }

    my $eval = sub {
	my $script = shift;
	no strict; no warnings;
	my $result = eval "package Configuration::Implanted; $script";
	use warnings; use strict;
	if ($@) {
	    die "\%CODE{ }EDOC\% interpretation error.\n".
		"block: ".$this->[BLOCK_NAME]."\n".
		"original: $str\n".
		"$@\n";
	}
	$result;
    };
    (my $evaluated = $str) =~ s/\%CODE{(.*?)}EDOC\%/$eval->($1)/eg;
    $evaluated;
}

sub _coerce_to_block {
    my ($this, $key, $value) = @_;

    if (ref($value) and UNIVERSAL::isa($value, 'Configuration::Block')) {
	return $value;
    }
    else {
	my $tmp_block = Configuration::Block->new($key);
	$tmp_block->set($key, $value);
	return $tmp_block;
    }
}

sub get {
    my $this = shift;
    my $key = shift;
    my %option;
    if (@_) {
	@option{@_} = (1) x @_;
    }

    if ($option{all}) {
	# list context
	my @values = $this->_get($key, %option);
	return map {
	    $option{block} ? $this->_coerce_to_block($key, $_) : $_;
	} map {
	    $this->_eval_code($_);
	} @values;
    } else {
	# scalar context
	my $value = $this->_eval_code($this->_get($key, %option));
	if ($option{block}) {
	    $value = $this->_coerce_to_block($key, $value);
	}
	return $value;
    }
}

sub _get {
    my ($this, $key, %option) = @_;

    unless (exists $this->[TABLE]->{$key}) {
	# そのような値は定義されていない。
	if ($option{all}) {
	    return ();
	}
	elsif ($option{block}) {
	    return Configuration::Block->new($key);
	}
	else {
	    return undef;
	}
    }

    my $value = $this->[TABLE]->{$key};
    if (ref($value) ne 'ARRAY') {
	# 配列のリファレンスでなければそのまま返す。
	return $value;
    } elsif ($option{all}) {
	# 逆参照して返す。
	return @{$value};
    }
    elsif ($option{random}) {
	# ランダムに選んで返す
	return $value->[int(rand(0xffffffff)) % @$value];
    }
    else {
	# 先頭の値を返す。
	return $value->[0];
    }
}

sub set {
    # 古い値があれば上書きする。
    my ($this,$key,$value) = @_;
    $this->[TABLE]->{$key} = $value;
    $this;
}

sub add {
    # 古い値があればそれに追加する。
    my ($this,$key,$value) = @_;
    if (defined $this->[TABLE]->{$key}) {
	# 定義済み。
	if (ref($this->[TABLE]->{$key}) eq 'ARRAY') {
	    # 既に複数の値を持っているのでただ追加する。
	    push @{$this->[TABLE]->{$key}},$value;
	}
	else {
	    # 配列に変更する。
	    $this->[TABLE]->{$key} = [$this->[TABLE]->{$key},$value];
	}
    }
    else {
	# 定義済みでない。
	$this->[TABLE]->{$key} = $value;
    }
}

sub reinterpret_encoding {
    # このブロックの全ての要素を指定された文字エンコーディングで再解釈する。
    # 再解釈後はUTF-8になる。
    my ($this,$encoding) = @_;

    my $unicode = Tiarra::Encoding->new;
    my $walk;
    $walk = sub {
	my $value = shift;

	if (ref($value) eq 'ARRAY') {
	    # 配列なので中身を全て変換。
	    my @newarray = map {
		$walk->($_);
	    } @$value;
	    \@newarray;
	}
	elsif (UNIVERSAL::isa($value, 'Configuration::Block')) {
	    # ブロックなので再帰的にコード変換。
	    $value->reinterpret_encoding($encoding);
	}
	else {
	    $unicode->set($value, $encoding)->utf8
	}
    };

    my $newtable = {};
    while (my ($key,$value) = each %{$this->[TABLE]}) {
	my $newkey = $unicode->set($key,$encoding)->utf8;
	$newtable->{$newkey} = $walk->($value);;
    }

    $this->[TABLE] = $newtable;
    $this;
}

sub AUTOLOAD {
    my ($this,@options) = @_;

    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROYは伝達させない。
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    $key =~ s/_/-/g;
    return $this->get($key,@options);
}

1;
