# -----------------------------------------------------------------------------
# $Id: DateConvert.pm,v 1.2 2003/07/31 07:34:14 topia Exp $
# -----------------------------------------------------------------------------
# これはTiarraモジュールではありません。
# %Yや%mなどを置換する機能を提供します。
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/Tools/DateConvert.pm,v 1.4 2003/07/24 02:59:30 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# This module is supports POSIX strftime; based NetBSD libc strftime.
#   On PurePerl, Locale, timezone, and '%V', '%G', '%g' is not supported.
#     so use localized constants;
#       ex. %z => '$TIMEZONE_NAME'.
package Tools::DateConvert;
use strict;
use warnings;
use Carp;

my ($can_use_posix, $use_posix);

eval 'use POSIX';
unless ($@) { # successful loading POSIX;
    $use_posix = $can_use_posix = 1;
} else {
    $use_posix = $can_use_posix = 0;
    print "------can't use POSIX...\n$@\n------\n";
}

#constants;
my (
    $TIME_SEC, # 0
    $TIME_MIN, # 1
    $TIME_HOUR, # 2
    $TIME_DAY, # 3
    $TIME_MON, # 4
    $TIME_YEAR, # 5
    $TIME_WDAY, # 6
    $TIME_YDAY, # 7
    $TIME_ISDST # 8
   ) = (0...8);
my ($DAYSPERWEEK) = 7;
my ($YEAROFFSET) = 1900;
my ($HOURSPERDAY) = 24;
my ($HALF_HOURSPERDAY) = $HOURSPERDAY / 2;
#localized constants;
my (@DAYS) = qw(Sun Mon Tues Wednes Thurs Fri Satur);
my (@MONTHS) = qw(January February March April May June July August September October November December);
my ($FORMAT) = '%a %b %e %H:%M:%S %Y';
my ($TIME_FORMAT) = '%H:%M:%S';
my ($DATE_FORMAT) = '%m/%d/%y';
my ($TIMEZONE_NAME) = 'JST';
my ($TIMEZONE_OFFSET) = '+0900';
my (@AM_PM) = qw(AM PM);

sub import {
    my $pkg = shift;
    foreach (@_) {
	if ($_ eq 'PurePerl') {
	    $use_posix = 0;
	}
    }
}

sub unimport {
    my $pkg = shift;
    foreach (@_) {
	if ($_ eq 'PurePerl') {
	    $use_posix = $can_use_posix;
	    carp 'can\'t use posix. no longer effective.' unless $use_posix;
	}
    }
}

sub force {
    my ($posix) = @_;

    carp 'this is old interface. use "use Tools::DateConvert qw(PurePerl);" instead.';

    if (defined($posix)) {
	if ($posix == 1) { # force use POSIX
	    $use_posix = 1;
	} elsif ($posix == 0) {
	    $use_posix = 0;
	} else {
	    croak 'force(posix) is only (0,1,undef) value.';
	}
    }
}

sub replace {
    my ($str, $time) = @_;
    $time = time() unless defined $time;
    my (@times) = localtime($time);
    my ($temp) = $time;

    $str =~ s/%([+-]\d+[Oo]|.)/_replace_real($1, $time, \$temp, \@times)/eg;
    return $str;
}

sub _replace_real {
    my ($tag, $origtime, $time, $times) = @_;
    my ($fmt) = '%02d';
    my ($data) = '';

    if ($tag eq '%') {
	$fmt = '';
	$data = $tag;
    } elsif ($tag =~ /([+-]\d)?([Oo])/) {
	# change times array....
	my ($number, $each);
	$number = $1;
	$each = $2;
	$number = 0 unless defined $number;

	if ($each eq 'O') {	# each day
	    $$time = $origtime + $number * 3600;
	} else {		# 'o', each second
	    $$time = $origtime + $number;
	}

	@$times = localtime($$time);
	$fmt = '';
	$data = '';
    } elsif ($use_posix == 1) {
	$fmt = '';
	$data = POSIX::strftime('%' . $tag, @$times);
    } else {
	if ($tag eq 'A') {
	    $fmt = '';
	    $data = @DAYS[$$times[$TIME_WDAY]] . 'day';
	} elsif ($tag eq 'a') {
	    $fmt = '';
	    $data = substr(@DAYS[$$times[$TIME_WDAY]], 0, 3);
	} elsif ($tag eq 'B') {
	    $fmt = '';
	    $data = @MONTHS[$$times[$TIME_MON]];
	} elsif ($tag eq 'b' || $tag eq 'h') {
	    $fmt = '';
	    $data = substr(@MONTHS[$$times[$TIME_MON]], 0, 3);
	} elsif ($tag eq 'C') {
	    $data = ($$times[$TIME_YEAR] + $YEAROFFSET) / 100;
	} elsif ($tag eq 'c') {
	    $fmt = '';
	    $data = replace($FORMAT, $$time);
	} elsif ($tag eq 'D') {
	    $fmt = '';
	    $data = replace('%m/%d/%y', $$time);
	} elsif ($tag eq 'd') {
	    $data = $$times[$TIME_DAY];
	    # C99 locale modifiers: 'Ox' and 'Ex' is ommited.
	} elsif ($tag eq 'e') {
	    $fmt = '%2d';
	    $data = $$times[$TIME_DAY];
	} elsif ($tag eq 'F') {
	    $fmt = '';
	    $data = replace('%Y-%m-%d', $$time);
	} elsif ($tag eq 'H') {
	    $data = $$times[$TIME_HOUR];
	} elsif ($tag eq 'I') {
	    $data = $$times[$TIME_HOUR] % $HALF_HOURSPERDAY;
	    $data = 12 if $data == 0;
	} elsif ($tag eq 'j') {
	    $fmt = '%03d';
	    $data = $$times[$TIME_YDAY] + 1;
	} elsif ($tag eq 'k') {
	    $fmt = '%2d';
	    $data = $$times[$TIME_HOUR];
	} elsif ($tag eq 'l') {
	    $fmt = '%2d';
	    $data = $$times[$TIME_HOUR] % $HALF_HOURSPERDAY;
	    $data = $HALF_HOURSPERDAY if $data == 0;
	} elsif ($tag eq 'M') {
	    $data = $$times[$TIME_MIN];
	} elsif ($tag eq 'm') {
	    $data = $$times[$TIME_MON] + 1;
	} elsif ($tag eq 'n') {
	    $fmt = '';
	    $data = "\n";
	} elsif ($tag eq 'p') {
	    $fmt = '';
	    if ($$times[$TIME_HOUR] < $HALF_HOURSPERDAY) {
		$data = $AM_PM[0];
	    } else {
		$data = $AM_PM[1];
	    }
	} elsif ($tag eq 'R') {
	    $fmt = '';
	    $data = replace('%H:%M', $$time);
	} elsif ($tag eq 'r') {
	    $fmt = '';
	    $data = replace('%I:%M:%S %p', $$time);
	} elsif ($tag eq 'S') {
	    $data = $$times[$TIME_SEC];
	} elsif ($tag eq 's') {
	    $fmt = '%d';
	    $data = $$time;
	} elsif ($tag eq 'T') {
	    $fmt = '';
	    $data = replace('%H:%M:%S', $$time);
	} elsif ($tag eq 't') {
	    $fmt = '';
	    $data = "\t";
	} elsif ($tag eq 'U') {
	    $data = ($$times[$TIME_YDAY] + $DAYSPERWEEK - $$times[$TIME_WDAY]) / $DAYSPERWEEK;
	} elsif ($tag eq 'u') {
	    $fmt = '%d';
	    $data = $$times[$TIME_WDAY];
	    $data = $DAYSPERWEEK if $data == 0;
	} elsif ($tag eq 'V' || $tag eq 'G' || $tag eq 'g') {
	    # not supported
	    $fmt = '';
	    $data = '';
	} elsif ($tag eq 'v') {
	    $fmt = '';
	    $data = replace('%e-%b-%Y', $$time);
	} elsif ($tag eq 'W') {
	    $data = $$times[$TIME_WDAY];
	    $data = $DAYSPERWEEK if $data == 0;
	    $data = ($$times[$TIME_YDAY] + $DAYSPERWEEK - $data - 1) / $DAYSPERWEEK;
	} elsif ($tag eq 'w') {
	    $fmt = '%d';
	    $data = $$times[$TIME_WDAY];
	} elsif ($tag eq 'X') {
	    $fmt = '';
	    $data = replace($TIME_FORMAT, $$time);
	} elsif ($tag eq 'x') {
	    $fmt = '';
	    $data = replace($DATE_FORMAT, $$time);
	} elsif ($tag eq 'y') {
	    $data = $$times[$TIME_YEAR] % 100;
	} elsif ($tag eq 'Y') {
	    $fmt = '%d';
	    $data = $$times[$TIME_YEAR] + $YEAROFFSET;
	} elsif ($tag eq 'Z') {
	    $fmt = '';
	    $data = $TIMEZONE_NAME;
	} elsif ($tag eq 'z') {
	    $fmt = '';
	    $data = $TIMEZONE_OFFSET;
	} else {
	    $fmt = '';
	    $data = '';
	}
    }

    return sprintf($fmt, $data) if $fmt ne '';
    return $data;
}

1;
