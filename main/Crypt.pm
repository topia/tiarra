# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Ϳ����줿���ޤ��ϥ�����˷��ꤵ�줿salt���Ѥ���ʸ�����crypt���뵡ǽ��
# ������ʸ�����crypt��������줿ʸ�����ͽ��crypt���줿ʸ�����
# ��Ӥ��뵡ǽ����ġ�
# -----------------------------------------------------------------------------
package Crypt;
use strict;
use warnings;

use SelfLoader;
1;
__DATA__

sub encrypt {
    # salt�Ͼ�ά��ǽ����ά�����ȥ�����˺���롣
    my ($str,$salt) = @_;
    $salt = gen_salt() unless defined $salt;

    return crypt($str,$salt);
}

sub check {
    # encrypted��salt��raw��crypt()���Ƥߤơ����פ������ɤ����򿿵��ͤ��֤���
    my ($raw,$encrypted) = @_;

    return crypt($raw,substr($encrypted,0,2)) eq $encrypted;
}

sub gen_salt {
    my $salt = '';
    
    srand;
    for (0 .. 1) {
	my $n = int(rand(63));
	if ($n < 12) {
	    $salt .= chr($n + 46); # ./0-9
	}
	elsif ($n < 38) {
	    $salt .= chr($n + 65 - 12); # A-Z
	}
	elsif ($n < 64) {
	    $salt .= chr($n + 97 - 38); # a-z
	}
    }
    $salt;
}

1
