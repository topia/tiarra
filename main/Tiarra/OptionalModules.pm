# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Optional Modules Loader
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::OptionalModules;
use strict;
use warnings;
use Tiarra::SharedMixin;
use Tiarra::Utils;
# failsafe to module-reload
our $status = {};

sub _new {
    bless $status, shift;
}

do {
    my %struct = (
	'threads' => 'use threads; use threads::shared;',
	'ipv6' => 'use IO::Socket::INET6;',
	'time_hires' => 'use Time::HiRes;',
	'unix_dom' => 'use IO::Socket::UNIX;',
       );
    while (my ($name, $statement) = each %struct) {
	eval '
sub '.$name.' {
    my $this = shift->_this;
    return $this->{'.$name.'} if defined $this->{'.$name.'};

    local $@;
    eval q{ '.$statement.' };
    $this->{'.$name.'} = ($@ ? 0 : 1);
}';
    }
};

1;
