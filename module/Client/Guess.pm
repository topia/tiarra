# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::Guess;
use strict;
use warnings;
use RunLoop;
use SelfLoader;

# shorthand
our $re_ver = qr/[\d.][\d.a-z-+]+/;
our $re_tok = qr/[^\s]+/;

sub shared {
    # don't need instance present
    return __PACKAGE__;
}

sub destruct {
    map {
	$_->remark('client-guess-cache', undef, 'delete');
    } RunLoop->shared_loop->clients_list;
}

sub is_target {
    my ($this, $type, $client) = @_;

    my $guess = $this->guess($client)->{type};
    if (defined $guess) {
	return $guess eq $type;
    } else {
	return undef;
    }
}

sub guess {
    my ($this, $client, $rehash) = @_;
    my $struct = $client->remark('client-guess-cache');

    if (!$rehash && defined $struct && $struct->{completed}) {
	return $struct;
    } else {
	$struct = {};
    }

    if (defined $client->remark('client-version')) {
	if ($this->guess_ctcp_version($struct,
				      $client->remark('client-version'))) {
	    $struct->{completed} = 1;
	}
    }

    if (defined $client->remark('client-type')) {
	$struct->{type} = $client->remark('client-type');
    }

    if (scalar(keys(%{$struct}))) {
	# cache
	$client->remark('client-guess-cache', $struct);
    }
    return $struct;
}

sub guess_ctcp_version {
    my ($this, $struct, $str) = @_;

    my $struct_set = sub {
	my %stor;
	# copy values
	my $param;
	$param = shift;
	if (ref($param) eq 'ARRAY') {
	    $stor{keys} = [@$param];
	} else {
	    $stor{keys} = [$param];
	}
	$stor{values} = [@_];

	my ($key, $value);
	while () {
	    ($key, $value) = map {
		if (scalar @{$stor{$_}}) {
		    shift @{$stor{$_}};
		} else {
		    return $struct;
		}
	    } qw(keys values);
	    $struct->{$key} = $value;
	}
    };

    $struct_set->('ctcp_version', $str);
    my $func = 'version_guess_' . lc(substr($str,0,1));
    if ($this->can($func)) {
	if ($this->$func($str, $struct_set)) {
	    return 1;
	}
    }

    if ($str =~ /^(Cotton|Unknown) Client$/) {
	$struct->{type} = 'cotton';
	$struct->{exact_type} = lc($1);
    } else {
	return undef;
    }
    return 1;
}

no warnings 'redefine';
SelfLoader->load_stubs;
1;
__DATA__

sub version_guess_t {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^Tiarra:($re_tok):perl ($re_tok) on ($re_tok)$/) {
	$struct_set->([qw(type version perlver perlplat)],
		      'tiarra', $1, $2, $3);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_l {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^LimeChat ($re_ver) \((.+?)\)$/) {
	$struct_set->([qw(type version plat)], 'limechat', $1, $2);
    } elsif ($str =~ /^Loqui version ($re_tok)/) {
	$struct_set->([qw(type version)], 'loqui', $1);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_m {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^Misuzilla Ircv \(($re_ver) version\) on (.NET CLR-$re_tok)$/) {
	$struct_set->([qw(type version plat)], 'ircv', $1, $2);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_p {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^plum ($re_ver) perl ($re_ver)\s*:?$/) {
	$struct_set->([qw(type version perlver)], 'plum', $1, $2);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_w {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^WoolChat Ver ($re_ver)?$/) {
	$struct_set->([qw(type version)], 'woolchat', $1);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_x {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^xchat ($re_ver) ($re_tok) ($re_tok)/) {
	$struct_set->([qw(type version plat platver)], 'xchat', $1, $2, $3);
    } else {
	return undef;
    }
    return 1;
}
