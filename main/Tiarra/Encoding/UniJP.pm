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
    # getcode�Ǹ��Ф��줿ʸ�������ɤ�encodings�˻��ꤵ��Ƥ����Τ�����к��ѡ�
    # ̵�����encodings�ΰ��ֺǽ����Ѥ��롣 (UTF-8��SJIS��ǧ�������ꤹ�뤿�ᡣ)
    $guess = ((grep {$guess eq $_} @encodings), @encodings)[0];
    $guess;
}

sub set {
    my $this = shift;
    my $str = shift;
    my $code = shift;

    if (!exists $this->{unijp}) {
	$this->{unijp} = Unicode::Japanese->new;
    }

    if (defined $str) {
	if ($code =~ /,/) {
	    # comma seperated guess-list
	    $code = $this->getcode($str, split(/\s*,\s*/, $code));
	}

	if (ref($str) && !overload::Method($str,'""')) {
	    croak "string neither scalar nor stringifiable";
	}
	# do stringify force to avoid bug on unijp <= 0.26
	$this->{unijp}->set("$str", $code, @_);
    }
    $this;
}

sub AUTOLOAD {
    our $AUTOLOAD;
    my $this = shift;

    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROY����ã�����ʤ���
	return;
    }

    (my $method = $AUTOLOAD) =~ s/.+?:://g;
    if (!exists $this->{unijp}) {
	$this->{unijp} = Unicode::Japanese->new;
    }
    $this->{unijp}->$method(@_);
}

1;
