# -----------------------------------------------------------------------------
# Iterator::ArrayIterator
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# このクラスは配列の値を順番に指すイテレータです。
# ランダムアクセス可能ですが、巡回は出来ません。
#
# 情報源としての配列そのものは、このイテレータは保持しません。
# その代わりに配列への参照を保持します。
# つまり、このイテレータを使用中に情報源の配列が変化すると
# イテレータの状態も変化します。
# -----------------------------------------------------------------------------
package Iterator::ArrayIterator;
use strict;
use warnings;
use base qw(Iterator::RandomAccessIterator);

sub new {
    my ($class,$src_array) = @_;
    my $obj = {
	source => $src_array,
	current_index => 0, # 作られた時にはイテレータは先頭の要素を指している。
    };
    bless $obj,$class;
}

sub _increment {
    my $this = shift;
    if (exists $this->{source}->[$this->{current_index}]) {
	# 今回はまだ要素が残っている。インクリメントしても要素があるか、または初めてundefになる。
	$this->{current_index}++;
    }
    else {
	# 今回で既にundefを指している。これ以上進めない。
	die "Iterator::ArrayIterator::increment : operation ++ failed. no more elements in this iterator.\n";
    }
    $this;
}

sub _decrement {
    my $this = shift;
    if ($this->{current_index} > -1) {
	$this->{current_index}--;
    }
    else {
	die "Iterator::ArrayIterator::decrement : operation -- failed. iterator pointed at element indexed -1.\n";
    }
    $this;
}

sub _addition {
    my ($this,$value) = @_;
    my $result = ref($this)->new($this->{source});
    $result->{current_index} = $this->{current_index} + $value;
    return $result;
}

sub _subtract {
    my ($this,$value) = @_;
    return $this->_addition(-$value);
}

sub _add_to {
    my ($this,$value) = @_;
    $this->{current_index} += $value;
    return $this;
}

sub _sub_from {
    my ($this,$value) = @_;
    return $this->_add_to(-$value);
}

sub get {
    $_[0]->{source}->[$_[0]->{current_index}];
}

1;
