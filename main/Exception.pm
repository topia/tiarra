# -----------------------------------------------------------------------------
# $Id: Exception.pm,v 1.1 2003/02/02 05:39:39 admin Exp $
# -----------------------------------------------------------------------------
package Exception;
use strict;
use warnings;
use overload
    '""' => \&_ope_tostring;

sub new {
    my ($class,$msg) = @_;
    my $this = {
	msg => $msg,
	stacktrace => undef, # 後で書く。caller辿るの面倒。
    };
    bless $this,$class;
}

sub message {
    shift->{msg};
}

sub throw {
    die shift;
}

sub _ope_tostring {
    my ($this) = @_;
    ref($this).(defined $this->{msg} ? " : $this->{msg}" : '');
}

# -----------------------------------------------------------------------------
package QueueIsEmptyException;
use base qw(Exception);

1;
