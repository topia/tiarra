# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id: PersonInChannel.pm,v 1.7 2003/09/22 19:23:06 admin Exp $
# -----------------------------------------------------------------------------
# なるとや発言権を持っているかどうかの情報とPersonalInfoのセット。
# -----------------------------------------------------------------------------
package PersonInChannel;
use strict;
use warnings;
use Carp;
use PersonalInfo;

use constant PERSON  => 0;
use constant HAS_O   => 1;
use constant HAS_V   => 2;
use constant REMARKS => 3;

sub new {
    my ($class,$person,$has_o,$has_v) = @_;
    croak "PersonInChannel->new requires 3 parameters.\n" if @_ != 4;
    my $obj = bless [] => $class;
    $obj->[PERSON] = $person;
    $obj->[HAS_O] = $has_o;
    $obj->[HAS_V] = $has_v;
    $obj->[REMARKS] = undef;
    $obj;
}

sub person {
    shift->[PERSON];
}

sub info {
    my ($this, $wantarray) = @_;
    shift->[PERSON]->info($wantarray);
}

sub has_o {
    my ($this,$option) = @_;
    $this->[HAS_O] = $option if defined $option;
    $this->[HAS_O];
}

sub has_v {
    my ($this,$option) = @_;
    $this->[HAS_V] = $option if defined $option;
    $this->[HAS_V];
}

*remarks = \&remark;
sub remark {
    my ($this,$key,$value) = @_;
    my $remarks = $this->[REMARKS];
    
    if (defined $value) {
	if (!$remarks) {
	    $remarks = $this->[REMARKS] = {};
	}
	
	$remarks->{$key} = $value;
    }
    elsif (@_ >= 3) {
	if ($remarks) {
	    delete $remarks->{$key};
	}
    }

    if ($remarks) {
	$remarks->{$key};
    }
    else {
	undef;
    }
}

sub delete_remark {
    my ($this,$key) = @_;
    if ($_ = $this->[REMARKS]) {
	delete $_->{$key};
    }
}

1;
