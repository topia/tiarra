# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Encoding with Encode
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Encoding::Encode;
use strict;
use warnings;
use Carp;
use Encode qw/find_encoding/;
use Encode::Guess; # for getcode
use Encode::JP::H2Z; # for h2zKana, z2hKana
BEGIN { eval { require Tiarra::Encoding::Encode::CP932JIS } }
use Tiarra::OptionalModules;
use base qw(Tiarra::Encoding);

our %encoding_names = ( # please specify _Encode.pm's canonical_ name.
    sjis => 'cp932', # compatible with unijp
    ucs2 => 'UCS-2BE',
    ucs4 => 'UTF-32BE',
    utf8 => 'utf8',
    utf16 => 'UTF-16',
    jis => (find_encoding('cp932-jis') ? 'cp932-jis' : '7bit-jis'),
    euc => 'euc-jp',
    binary => 'utf8',
);

our @default_probe_encodings =
    __PACKAGE__->_find_canon_encs(qw(sjis euc utf8 jis));


sub getu {
    my $this = shift;
    $this->{str};
}

sub _find_canon_encs {
    my $this = shift;
    my $temp;
    grep {
	return $_ unless wantarray;
	1;
    } map {
	if (exists $encoding_names{$_}) {
	    $encoding_names{$_};
	} else {
	    $temp = find_encoding($_);
	    if (defined $temp) {
		$temp->name
	    } elsif ($_ ne 'auto') {
		warn "Unknown encoding: $_";
		();
	    }
	}
    } @_;
}

sub decode {
    my ($this, $str, $encoding) = @_;

    if (defined $str) {
	if (ref($str) && !overload::Method($str,'""')) {
	    croak "string neither scalar nor stringifiable";
	}
	# do stringify force to avoid bug on old Encode
	$this->{str} = Encode::decode($this->_find_canon_encs($encoding), "$str");
    }
    $this;
}

sub encode {
    my ($this, $encoding) = @_;

    if (defined $this->{str}) {
	Encode::encode($this->_find_canon_encs($encoding), $this->{str});
    } else {
	undef;
    }
}

sub getcode {
    my $this = shift;
    my $str = shift;
    my @encodings = (@_ ? ($this->_find_canon_encs(@_)) :
			 @default_probe_encodings);
    my $guess = find_encoding('Guess')->renew;
    $guess->set_suspects(@encodings);
    my ($enc, @other) = $guess->guess($str);
    if (ref($enc)) {
	return wantarray ? ($enc->name, $enc) : $enc->name;
    } else {
	if (defined $enc && $enc =~ /Encodings too ambiguous/i) {
	    my @probed = split / or /, shift(@other);
	    $enc = [];
	    foreach my $try_enc (@encodings) {
		for (my $i = 0; $i < @probed; ++$i) {
		    if ($probed[$i] eq $try_enc) {
			push @$enc, splice @probed, $i, 1;
			last;
		    }
		}
	    }
	    if (@$enc == 1) {
		$enc = find_encoding(shift(@$enc));
		return wantarray ? ($enc->name, $enc) : $enc->name;
	    }
	}
	return wantarray ? ('unknown', $enc, @other) : 'unknown';
    }
}
sub h2z {
    # only kana supported
    my $this = shift;
    $this->h2zKana;
    $this;
}

sub h2zKana {
    my $this = shift;
    my $eucjp = $this->encode($this->_find_canon_encs(qw(euc)));
    Encode::JP::H2Z::h2z(\$eucjp);
    $this->decode($eucjp, $this->_find_canon_encs(qw(euc)));
    $this;
}

sub z2h {
    # only kana supported
    my $this = shift;
    $this->z2hKana;
    $this;
}

sub z2hKana {
    my $this = shift;
    my $eucjp = $this->encode($this->_find_canon_encs(qw(euc)));
    Encode::JP::H2Z::z2h(\$eucjp);
    $this->decode($eucjp, $this->_find_canon_encs(qw(euc)));
    $this;
}

foreach (qw(h2zNum h2zAlpha h2zSym z2hNum z2hAlpha z2hSym),
	 qw(kata2hira hira2kata),
	 (map { "sjis_$_" } qw(imode imode1 imode2 doti jsky jsky1 jsky2))) {
    eval "sub $_ \{ shift->_not_supported_feature \}";
}

# common for non-unijp's

do {
    my %methods = (
	qw(get utf8),
       );
    while (my ($key, $value) = each %methods) {
	eval "
	sub $key \{
	    shift-\>conv('$value', \@_);
	}";
    }

    my @methods = qw(jis euc sjis utf8 ucs2 ucs4 utf16);
    foreach (@methods) {
	eval "
	sub $_ \{
	    shift-\>conv('$_', \@_);
	}";
    }
};

sub set {
    my $this = shift;
    my $str = shift;
    my $code = shift;
    my $encode = shift;

    if (defined $encode && defined $str) {
	if ($encode eq 'base64') {
	    # if you have perl-bundled encode, also have mime-base64.
	    # (see Module::CoreList)
	    Tiarra::OptionalModules->check('base64') or
		    croak 'Couldn\'t load MIME::Base64.';
	    $str = MIME::Base64::decode($str);
	}
    }

    if (!defined $code) {
	$code = 'utf8';
    } elsif ($code eq 'auto' || $code =~ /,/) {
	my @codes = ();
	if ($code =~ /,/) {
	    # comma seperated guess-list
	    @codes = split(/\s*,\s*/, $code);
	}
	my ($enc, @enc_others) = $this->getcode($str, @codes);
	if (defined $enc && $enc ne 'unknown') {
	    $code = $enc;
	} else {
	    $enc = shift @enc_others;
	    if (ref($enc) eq 'ARRAY') {
		# use first
		$code = shift @$enc;
	    } else {
		# so we can't probe encoding.
		# use first of probe list.
		$enc = $default_probe_encodings[0];
	    }
	}
    }

    $this->decode($str, $code);
}

sub conv {
    my $this = shift;
    my $code = shift;
    my $encode = shift;

    my $str = $this->encode($code);

    if (defined $encode && defined $str) {
	if ($encode eq 'base64') {
	    # if you have perl-bundled encode, also have mime-base64.
	    # (see Module::CoreList)
	    Tiarra::OptionalModules->check('base64') or
		    croak 'Couldn\'t load MIME::Base64.';
	    $str = MIME::Base64::encode($str, '');
	}
    }
    return $str;
}

sub _not_supported_feature {
    my $this = shift;
    (my $funcname = (caller(1))[3]) =~ s/^.*::(.+?)$/$1/;
    die sprintf '%s is really not supported by %s', $funcname, (ref($this) || $this);
}

sub join_csv { shift->_not_supported_feature }
sub split_csv { shift->_not_supported_feature }
sub strcut { shift->_not_supported_feature }
sub strlen { shift->_not_supported_feature }

1;
