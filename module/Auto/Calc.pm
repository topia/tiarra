# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id: Calc.pm,v 1.2 2003/08/24 18:21:13 topia Exp $
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/Auto/Calc.pm,v 1.2 2003/08/24 18:21:13 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Auto::Calc;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;

use Safe;

sub new {
    my ($class) = @_;
    my $this = $class->SUPER::new;
    $this->{safe} = Safe->new();
    $this->{safe}->permit_only(qw(:base_core atan2 sin cos exp sqrt log exp pack unpack));

    return $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my $return_value = sub {
	return @result;
    };

    my (undef,undef,undef,$reply_anywhere,$get_full_ch_name)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

    if ($msg->command eq 'PRIVMSG') {
	my $method = $msg->param(1);
	$method =~ s/^\s*(.*)\s*$/$1/;
	my $keyword;
	($keyword, $method) = split(/\s+/, $method, 2);

	# request
	if (Mask::match_deep([$this->config->request('all')], $keyword)) {
	    if (Mask::match_deep_chan([$this->config->mask('all')], $msg->prefix, $get_full_ch_name->())) {
		my ($ret, $err);
		do {
		    # disable warning
		    local $SIG{__WARN__} = sub { };
		    # die handler
		    local $SIG{__DIE__} = sub { $err = $_[0] };
		    no strict 'all';
		    $ret = $this->{safe}->reval($method);
		};

		my $reply = sub {
		    my $array = shift;

		    map {
			if (defined($$_)) {
			    # ±øÀ÷¤Î½üµî
			    $$_ =~ tr/\t\n/ /;
			    $$_ =~ tr/\x00-\x1f//;
			    $$_ =~ s/^\s+//;
			    $$_ =~ s/\s+$//;
			} else {
			    $$_ = $this->config->undef || 'undef';
			}
		    } (\$ret, \$err);

		    map {
			$reply_anywhere->(
			    $_,
			    method => $method,
			    result => $ret,
			    error => $err,
			   );
		    } @$array;
		};

		if ($err) {
		    if ($err) {
			$err =~ s/ +at \(eval \d+\) line \d+//;
		    }
		    $reply->([$this->config->error_format('all')]);
		} else {
		    $reply->([$this->config->reply_format('all')]);
		}
	    }
	    return $return_value->();
	}
    }

    return $return_value->();
}

1;
