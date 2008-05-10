# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# 与えられた、またはランダムに決定されたsaltを用いて文字列をcryptする機能、
# そして文字列をcryptして得られた文字列を、予めcryptされた文字列と
# 比較する機能を持つ。
# -----------------------------------------------------------------------------
package Crypt;
use strict;
use warnings;

#use SelfLoader;
#1;
#__DATA__

sub encrypt {
    # saltは省略可能。省略されるとランダムに作られる。
    my ($str,$salt) = @_;
    $salt = gen_salt() unless defined $salt;

    return crypt($str,$salt);
}

sub check {
    # encryptedのsaltでrawをcrypt()してみて、一致したかどうかを真偽値で返す。
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
