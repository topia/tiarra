# -----------------------------------------------------------------------------
# $Id: Block.pm,v 1.11 2004/02/23 02:46:18 topia Exp $
# -----------------------------------------------------------------------------
package Configuration::Block;
use strict;
use warnings;
use vars qw($AUTOLOAD);
use UNIVERSAL;
use Unicode::Japanese;
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

use constant BLOCK_NAME => 0;
use constant TABLE      => 1;

sub new {
    my ($class,$block_name) = @_;
    my $obj = bless [] => $class;
    $obj->[BLOCK_NAME] = $block_name;
    $obj->[TABLE]      = {}; # ラベル -> 値(配列リファもしくはスカラー)
    $obj;
}

sub block_name {
    my ($this,$newvalue) = @_;
    if (defined $newvalue) {
	$this->[BLOCK_NAME] = $newvalue;
    }
    $this->[BLOCK_NAME];
}

sub table {
    my ($this,$newvalue) = @_;
    if (defined $newvalue) {
	$this->[TABLE] = $newvalue;
    }
    $this->[TABLE];
}

sub equals {
    # 二つのConfiguration::Blockが完全に等価なら1を返す。
    my ($this,$that) = @_;
    # ブロック名
    if ($this->[BLOCK_NAME] ne $that->[BLOCK_NAME]) {
	return undef;
    }
    # キーの数
    my @this_keys = keys %{$this->[TABLE]};
    my @that_keys = keys %{$that->[TABLE]};
    if (@this_keys != @that_keys) {
	return undef;
    }
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
		if ($this_value->[$j] ne $that_value->[$j]) {
		    return undef;
		}
	    }
	}
	elsif (UNIVERSAL::isa($this_value,'Configuration::Block')) {
	    # ブロックなので再帰的に比較。
	    return $this_value->equals($that_value);
	}
	else {
	    if ($this_value ne $that_value) {
		return undef;
	    }
	}
    }
    return 1;
}

sub eval_code {
    # 渡された文字列中の、全ての%CODE{ ... }EDOC%を評価して返す。
    my ($this,$str) = @_;

    if (ref($str)) {
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

sub get {
    my ($this,$key,$option) = @_;

    unless (exists $this->[TABLE]->{$key}) {
	# そのような値は定義されていない。
	if ($option && $option eq 'all') {
	    return ();
	}
	elsif ($option and $option eq 'block') {
	    return Configuration::Block->new($key);
	}
	else {
	    return undef;
	}
    }

    my $value = $this->[TABLE]->{$key};
    if ($option && $option eq 'all') {
	if (ref($value) eq 'ARRAY') {
	    return map {
		$this->eval_code($_);
	    } @{$value}; # 配列リファなら逆参照して返す。
	}
	else {
	    return $this->eval_code($value);
	}
    }
    elsif ($option && $option eq 'random') {
	if (ref($value) eq 'ARRAY') {
	    # 配列リファならランダムに選んで返す
	    return $this->eval_code(
		$value->[int(rand(0xffffffff)) % @$value]);
	}
	else {
	    return $this->eval_code($value);
	}
    }
    elsif ($option and $option eq 'block') {
	if (ref($value) and UNIVERSAL::isa($value, 'Configuration::Block')) {
	    return $value;
	}
	else {
	    my $tmp_block = Configuration::Block->new($key);
	    $tmp_block->set($key, $value);
	    return $tmp_block;
	}
    }
    else {
	if (ref($value) eq 'ARRAY') {
	    return $this->eval_code($value->[0]); # 配列リファなら先頭の値を返す。
	}
	else {
	    return $this->eval_code($value);
	}
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

    my $unicode = Unicode::Japanese->new;
    my $newtable = {};
    while (my ($key,$value) = each %{$this->[TABLE]}) {
	my $newkey = $unicode->set($key,$encoding)->utf8;
	my $newvalue = do {
	    if (ref($value) eq 'ARRAY') {
		# 配列なので中身を全てコード変換。
		my @newarray = map {
		    $unicode->set($_,$encoding)->utf8;
		} @$value;
		\@newarray;
	    }
	    elsif (UNIVERSAL::isa($value,'Configuration::Block')) {
		# ブロックなので再帰的にコード変換。
		$value->reinterpret_encoding($encoding);
	    }
	    else {
		$unicode->set($value,$encoding)->utf8;
	    }
	};
	$newtable->{$newkey} = $newvalue;
    }

    $this->[TABLE] = $newtable;
    $this;
}

sub AUTOLOAD {
    my ($this,$option) = @_;
    
    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROYは伝達させない。
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    $key =~ s/_/-/g;
    return $this->get($key,$option);
}

1;
