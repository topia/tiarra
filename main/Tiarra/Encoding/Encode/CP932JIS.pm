package Tiarra::Encoding::CP932JIS;
use strict;

our $VERSION = '1.0';

use Encode qw(:fallbacks);

__PACKAGE__->Define(qw(cp932-jis));

use base qw(Encode::Encoding);

# perlio not supported yet
sub perlio_ok { 0 }

use Encode::CJKConstants qw(:all);

#
# decode is identical for all 2022 variants
#
my $re_scan_jis = qr{
   (?:($RE{JIS_0212})|($RE{JIS_0208})|($RE{ISO_ASC})|($RE{JIS_KANA}))([^\e]*)
}x;

sub decode($$;$)
{
    my ($obj, $str, $chk) = @_;
    my $ret = '';
    Encode::_utf8_on($ret);
    my $chr;
    while (length($str)) {
	if ($str =~ s/\A$re_scan_jis//s) {
	    my ($esc_0212, $esc_0208, $esc_asc, $esc_kana, $chunk) =
		($1, $2, $3, $4, $5);
	    # parse si/so
	    $chunk =~ s/\x0e(.+)\x0f/pack('C*', map $_ | 0x80, unpack('C*', $1))/eg;

	    if (!$esc_asc) {
		if ($esc_0212) {
		    # JIS X 0212-1990
		    # FIXME
		    $ret .= join '', '[JISX0212:', unpack('H*', $chunk), ']';
		} elsif ($esc_kana) {
		    # 0201 kana on G0
		    $chunk =~ s/(.)/pack('C', unpack('C', $1) | 0x80)/eog;
		    $ret .= Encode::decode('cp932', $chunk, FB_PERLQQ);
		} elsif ($esc_0208) {
		    # s1 = ((j1 - 1) >> 1) + ((j1 <= 0x5e) ? 0x71 : 0xb1);
		    # s2 = j2 + ((j1 & 1) ? ((j2 < 0x60) ? 0x1f : 0x20) : 0x7e);
		    my ($j1, $j2);
		    $chunk =~ s{(.{2})}{
			($j1, $j2) = unpack('C*', $1);
		    pack('C*',
			 (($j1 - 1) >> 1) + (($j1 <= 0x5e) ? 0x71 : 0xb1),
			 $j2 + (($j1 & 1) ? (($j2 < 0x60) ? 0x1f : 0x20) : 0x7e));
		    }exog;
		    $ret .= Encode::decode('cp932', $chunk, FB_PERLQQ);
		}
	    } else {
		$ret .= Encode::decode('cp932', $chunk);
	    }
	} elsif ($str =~ s/\A(\e?[^\e]+)//s) {
	    $ret .= Encode::decode('iso-8859-1', $1);
	}
    }
    return $ret;
}

#
# encode is different
#

sub encode($$;$)
{
    my ($obj, $utf8, $chk) = @_;
    my $str = Encode::encode('cp932', $utf8, FB_PERLQQ) ;
    my $ret = '';
    Encode::_utf8_off($ret);
    my ($s1, $s2);
    my $lastmode = 'ascii';
    my $startmode = sub {
	my ($mode, $escape) = @_;
	if ($lastmode ne $mode) {
	    $lastmode = $mode;
	    $ret .= $escape;
	}
    };
    while (length($str)) {
	if ($str =~ s/\A((?:[\x81-\x9f\xe0-\xef].)+)//s) {
	    $startmode->('0218', $ESC{JIS_0208});
	    # sjis 2byte
	    #j1 = (s1 << 1) - (s1 <= 0x9f ? 0xe0 : 0x160) - (s2 < 0x9f ? 1 : 0);
	    #j2 = s2 - 0x1f - (s2 >= 0x7f ? 1 : 0) - (s2 >= 0x9f ? 0x5e : 0);
	    foreach ($1 =~ /(..)/g) {
		($s1, $s2) = unpack('C*', $_);
		$ret .= pack('C*',
			     ($s1 << 1) - ($s1 <= 0x9f ? 0xe0 : 0x160) - ($s2 < 0x9f ? 1 : 0),
			     $s2 - 0x1f - ($s2 >= 0x7f ? 1 : 0) - ($s2 >= 0x9f ? 0x5e : 0));
	    }
	} elsif ($str =~ s/\A([\xa1-\xdf]+)//s) {
	    $startmode->('0218', $ESC{JIS_0208});
	    foreach (split //, $1) {
		#$ret .= unpack('H*', $_);
		$ret .= $_;
	    }
	} elsif ($str =~ s/\A(.)//s) {
	    $startmode->('ascii', $ESC{ASC});
	    $ret .= $1;
	}
    }
    $startmode->('ascii', $ESC{ASC});
    return $ret;
}

1;
__END__
