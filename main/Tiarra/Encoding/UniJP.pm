# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Encoding with Unicode::Japanese
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Encoding::UniJP;
use strict;
use warnings;
use Carp;
use base qw(Tiarra::Encoding);
use Unicode::Japanese;

our @default_probe_encodings = qw(sjis euc utf8 jis);

sub getcode {
    my $this = shift;
    my $str = shift;
    my @encodings = (@_ ? @_ : @default_probe_encodings);
    my $guess = $this->{unijp}->getcode($str);

    # really unknown encoding.
    return $guess if $guess eq 'unknown';

    # getcodeで検出された文字コードでencodingsに指定されているものがあれば採用。
    # 無ければencodingsの一番最初を採用する。 (UTF-8をSJISと認識したりするため。)
    $guess = ((grep {$guess eq $_} @encodings), @encodings)[0];
    $guess;
}

sub set {
    my $this = shift;
    my $str = shift;
    my $code = shift;

    if (defined $str) {
	if ($code =~ /,/) {
	    # comma seperated guess-list
	    $code = $this->getcode($str, split(/\s*,\s*/, $code));
	    $code = 'binary' if $code eq 'unknown';
	}

	if (ref($str) && !overload::Method($str,'""')) {
	    croak "string neither scalar nor stringifiable";
	}
	# do stringify force to avoid bug on unijp <= 0.26
	$this->{unijp}->set("$str", $code, @_);
    }
    $this;
}

sub _init {
    my $this = shift;
    $this->{unijp} = Unicode::Japanese->new;
}

sub AUTOLOAD {
    our $AUTOLOAD;
    my $this = shift;

    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROYは伝達させない。
	return;
    }

    (my $method = $AUTOLOAD) =~ s/.+?:://g;
    if ($method =~ /^(?:h2z|z2h).*$/) {
	$this->{unijp}->$method(@_);
	$this;
    } else {
	$this->{unijp}->$method(@_);
    }
}

1;
