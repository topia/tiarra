# -----------------------------------------------------------------------------
# Iterator::ForwardIterator
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# これらのクラスはそれぞれの操作が行なえる事を示すために用いられる抽象クラスです。
# インスタンスを生成する事は出来ません。
# -----------------------------------------------------------------------------
package Iterator::ForwardIterator;
use strict;
use warnings;
use base qw(Iterator);
use overload
    '++' => \&_ope_increment;

sub _ope_increment {
    $_[0]->_increment;
}
sub _increment {
    die "ForwardIterator has to override _increment().\n";
}

1;
