# -----------------------------------------------------------------------------
# Iterator::ForwardIterator
# -----------------------------------------------------------------------------
# $Id: ForwardIterator.pm,v 1.2 2002/11/14 08:51:57 admin Exp $
# -----------------------------------------------------------------------------
# �����Υ��饹�Ϥ��줾������Ԥʤ�����򼨤�������Ѥ�������ݥ��饹�Ǥ���
# ���󥹥��󥹤�����������Ͻ���ޤ���
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
