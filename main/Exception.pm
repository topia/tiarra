# -----------------------------------------------------------------------------
# $Id$
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
	stacktrace => undef, # ��ǽ񤯡�calleré������ݡ�
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
