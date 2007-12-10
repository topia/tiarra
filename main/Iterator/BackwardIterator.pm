# -----------------------------------------------------------------------------
# Iterator::BackwardIterator
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# これらのクラスはそれぞれの操作が行なえる事を示すために用いられる抽象クラスです。
# インスタンスを生成する事は出来ません。
# -----------------------------------------------------------------------------
package Iterator::BackwardIterator;
use strict;
use warnings;
use base qw(Iterator);
use overload
    '--' => \&_ope_decrement;

sub _ope_decrement {
    $_[0]->_decrement;
}
sub _decrement {
    die "BackwardIterator has to override decrement().\n";
}

1;
