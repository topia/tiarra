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
our %modules = (
    'threads' => {
	requires => [qw(threads threads::shared Thread::Queue)],
	note => 'for threading dns resolving',
    },
    'ipv6' => {
	requires => [qw(IO::Socket::INET6 Socket6)],
	note => 'for ipv6 support',
    },
    'time_hires' => {
	requires => [qw(Time::HiRes)],
	note => 'for hi-resolution timer support',
    },
    'unix_dom' => {
	requires => [qw(IO::Socket::UNIX)],
	note => 'for control port support',
    },
    'encode' => {
	requires => [qw(Encode)],
	note => 'for Tiarra::Encoding::Encode encoding driver',
    },
    'base64' => {
	requires => [qw(MIME::Base64)],
	note => 'for Tiarra::Encoding::Encode\'s base64 support',
    },
    'ssl' => {
	requires => [qw(IO::Socket::SSL)],
	note => 'for ssl-enabled server support',
    },
   );

sub _new {
    bless $status, shift;
}

sub all_modules {
    keys %modules;
}

sub repr_modules {
    my $this = shift->_this;
    my $verbose = shift;
    my %status = $this->check_all;
    my @enabled = sort grep $status{$_}, keys %status;
    my @disabled = sort grep !$status{$_}, keys %status;

    my $repr_module = sub {
	my ($modname, $eachmod) = @_;
	my $ver;
	my $error = $this->{$modname}->{errors}->{$eachmod};
	if (defined $error) {
	    if ($verbose) {
		$error =~ s/ at .*//s;
		$error =~ s/ \(\@INC .*\)//g;
		$error =~ s/[\r\n]+/ /sg;
		$error =~ s/ +$//g;
		"[failed: $error]";
	    } else {
		"[failed to load]";
	    }
	} else {
	    eval {
		$ver = $eachmod->VERSION;
	    };
	    if (!defined $ver) {
		'unknown';
	    } else {
		$ver;
	    }
	}
    };

    my $repr_modules = sub {
	my $title = shift;
	my $modname;
	(@_ ?
	     ("$title:",
	      map {
		  $modname = $_;
		  "  - $_ (" . join(', ', map {
		      "$_ " . $repr_module->($modname, $_);
		  } @{$modules{$_}->{requires}}) . ") " .
		      $modules{$_}->{note}
	      } @_) : ())
    };

    ($repr_modules->("enabled", @enabled),
     $repr_modules->("disabled", @disabled));
}

sub check_all {
    my $this = shift->_this;
    map { ($_, $this->check($_)) } $this->all_modules;
}

sub check {
    my ($class_or_this, $name) = @_;
    my $this = $class_or_this->_this;

    return $this->{$name}->{status} if defined $this->{$name};
    die "module $name spec. not found" unless defined $modules{$name};
    if ($ENV{"TIARRA_DISABLE_\U$name\E"}) {
	$this->{$name}->{status} = !1;
	return !1;
    }

    my $failed;
    for my $mod (@{$modules{$name}->{requires}}) {
	if (!eval "require $mod") {
	    $failed = 1;
	};
	if ($@) {
	    $this->{$name}->{errors}->{$mod} = $@;
	}
    }
    $this->{$name}->{status} = !$failed;
}

sub AUTOLOAD {
    my $this = shift;
    our $AUTOLOAD;
    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROYは伝達させない。
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    $this->check($key);
}

1;
