# -----------------------------------------------------------------------------
# Iterator::RandomAccessIterator
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# これらのクラスはそれぞれの操作が行なえる事を示すために用いられる抽象クラスです。
# インスタンスを生成する事は出来ません。
# -----------------------------------------------------------------------------
package Iterator::RandomAccessIterator;
use strict;
use warnings;
use base qw(Iterator::BidirectionalIterator);
use overload
    '+' => \&_ope_addition,
    '-' => \&_ope_subtract,
    '+=' => \&_ope_add_to,
    '-=' => \&_ope_sub_from;

sub _ope_addition {
    my ($this,$value) = @_;
    $this->_addition($value);
}
sub _addition {
    die "RandomAccessIterator has to implement addition().\n";
}

sub _ope_subtract {
    my ($this,$value,$inverted) = @_;
    if ($inverted) {
	# $ite - 1はサポートされているが、1 - $iteはサポートされていない。
	die "Iterator::RandomAccessIterator : statement 'n - \$ite' is invalid.\n";
    }
    else {
	$this->_subtract($value);
    }
}
sub subtract {
    die "RandomAccessIterator has to implement subtract().\n";
}

sub _ope_add_to {
    my ($this,$value) = @_;
    $this->_add_to($value);
}
sub _add_to {
    die "RandomAccessIterator has to implement add_to().\n";
}

sub _ope_sub_from {
    my ($this,$value) = @_;
    $this->_sub_from($value);
}
sub _sub_from {
    die "RandomAccessIterator has to implement sub_from().\n";
}

1;

