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
    'threads' => [qw(threads threads::shared)],
    'ipv6' => [qw(IO::Socket::INET6 Socket6)],
    'time_hires' => [qw(Time::HiRes)],
    'unix_dom' => [qw(IO::Socket::UNIX)],
    'encode' => [qw(Encode)],
    'base64' => [qw(MIME::Base64)],
   );

sub _new {
    bless $status, shift;
}

sub all_modules {
    keys %modules;
}

sub repr_modules {
    my $this = shift->_this;
    $this->check_all;
    my @enabled = sort grep $this->check($_), keys %modules;
    my @disabled = sort grep !$this->check($_), keys %modules;

    ((@enabled ?
	  ("enabled:",
	   map {
	       "  - $_ (" . join(', ', map {
		   "$_ " . $_->VERSION;
	       } @{$modules{$_}}) . ")"
	   } @enabled) : ()),
     (@disabled ?
	  ("disabled:",
	   map {
	       "  - $_ (" . join(', ', @{$modules{$_}}) . ")"
	   } @disabled) : ()));
}

sub check_all {
    my $this = shift->_this;
    map { ($_, $this->check($_)) } $this->all_modules;
}

sub check {
    my ($class_or_this, $name) = @_;
    my $this = $class_or_this->_this;

    return $this->{$name} if defined $this->{$name};
    die "module $name spec. not found" unless defined $modules{$name};

    $this->{$name} = eval join(' && ', map { "require $_" } @{$modules{$name}}) . ';';
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
