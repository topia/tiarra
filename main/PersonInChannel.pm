# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# なるとや発言権を持っているかどうかの情報とPersonalInfoのセット。
# -----------------------------------------------------------------------------
package PersonInChannel;
use strict;
use warnings;
use Carp;
use PersonalInfo;
use Tiarra::DefineEnumMixin qw(PERSON HAS_O HAS_V REMARKS);
use Tiarra::Utils;
Tiarra::Utils->define_array_attr_getter(0, qw(person));
Tiarra::Utils->define_array_attr_accessor(0, qw(has_o has_v));

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

sub info {
    my ($this, $wantarray) = @_;
    shift->[PERSON]->info($wantarray);
}

sub priv_symbol {
    my $this = shift;

    return '@' if ($this->has_o);
    return '+' if ($this->has_v);
    return '';
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
