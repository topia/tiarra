# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::Guess;
use strict;
use warnings;
use RunLoop;
use SelfLoader;
use Tiarra::SharedMixin;

# shorthand
our $re_ver = qr/[\d.][\d.a-zA-Z+-]+/;
our $re_tok = qr/\S+/;

sub _new {
    # don't need instance present
    return shift;
}

sub destruct {
    map {
	$_->remark('client-guess-cache', undef, 'delete');
    } RunLoop->shared_loop->clients_list;
}

sub is_target {
    my ($class_or_this, $type, $client) = @_;
    my $this = $class_or_this->_this;

    my $guess = $this->guess($client)->{type};
    if (defined $guess) {
	return $guess eq $type;
    } else {
	return undef;
    }
}

sub guess {
    my ($class_or_this, $client, $rehash) = @_;
    my $this = $class_or_this->_this;
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
    my ($class_or_this, $struct, $str) = @_;
    my $this = $class_or_this->_this;

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

    #$struct_set->('ctcp_version', $str);
    my $func = 'version_guess_' . lc(substr($str,0,1));
    if ($this->can($func)) {
	if ($this->$func($str, $struct_set)) {
	    return 1;
	}
    }

    if ($str =~ /^(Cotton|Unknown) Client/) {
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

sub version_guess_c {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^CHOCOA ($re_ver) \(($re_tok)\)/) {
	$struct_set->([qw(type ver plat)],
		      'chocoa', $1, $2);
    } elsif ($str =~ m[^Conversation ($re_ver) for (MacOS X|.+?) (http://$re_tok)]) {
	$struct_set->([qw(type ver plat url)],
		      'conversation', $1, $2, $3);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_t {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^Tiarra:($re_tok):perl ($re_tok) on ($re_tok)/) {
	$struct_set->([qw(type ver perl_ver perl_plat)],
		      'tiarra', $1, $2, $3);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_l {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^LimeChat ($re_ver) \((.+?)\)/) {
	$struct_set->([qw(type ver plat)], 'limechat', $1, $2);
    } elsif ($str =~ /^Loqui version ($re_tok)/) {
	$struct_set->([qw(type ver)], 'loqui', $1);
    } elsif ($str =~ m{^Liece/($re_ver) :}) {
	$struct_set->([qw(type ver)], 'liece', $1);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_m {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^madoka ($re_ver) in perl ($re_ver):/) {
	$struct_set->([qw(type ver perl_ver)], 'madoka', $1, $2);
    } elsif ($str =~ /^Misuzilla Ircv \(($re_ver) version\) on (.NET CLR-$re_tok)/) {
	$struct_set->([qw(type ver plat)], 'ircv', $1, $2);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_p {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^plum ($re_ver) perl ($re_ver)\s*:?/) {
	$struct_set->([qw(type ver perl_ver)], 'plum', $1, $2);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_r {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ m{^Riece/($re_ver) ($re_tok)/($re_ver)}) {
	$struct_set->([qw(type ver emacs_flavor emacs_ver)], 'riece', $1, $2, $3);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_w {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ /^WoolChat Ver ($re_ver)/) {
	$struct_set->([qw(type ver)], 'woolchat', $1);
    } else {
	return undef;
    }
    return 1;
}

sub version_guess_x {
    my ($this, $str, $struct_set) = @_;

    if ($str =~ m{^xchat ($re_ver) ($re_tok) ($re_tok) \[($re_tok)/($re_tok)\]}) {
	$struct_set->([qw(type ver plat plat_ver arch cpu_speed)],
		      'xchat', $1, $2, $3, $4, $5);
    } else {
	return undef;
    }
    return 1;
}
