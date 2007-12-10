# -----------------------------------------------------------------------------
# Iterator::BackwardIterator
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# �����Υ��饹�Ϥ��줾������Ԥʤ�����򼨤�������Ѥ�������ݥ��饹�Ǥ���
# ���󥹥��󥹤�����������Ͻ���ޤ���
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
