# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Mask;
use strict;
use warnings;
use Carp;
use Multicast;

sub match {
  # match�ϥ磻��ɥ����ɤ�Ȥä��ޥå��󥰤�Ԥ��ؿ��Ǥ���
  # �磻��ɥ����ɰʳ��ˤ⡢+��-��Ȥä���������䡢
  # re: ��Ȥä�����ɽ���ޥå��󥰤��Ԥ��ޤ���

  # $masks�ˤ�','(�����)�Ƕ��ڤä��ޥå��ꥹ�Ȥ��Ϥ��Ƥ���������
  # ������','(�����)��Ȥ���������'\,'�Ƚ񤱤ޤ���

  # ����̾      : [������] - ���� -
  # $match_type : [0] 0: �Ǹ�˥ޥå������ͤ��֤��ޤ��� 1: �ǽ�˥ޥå������ͤ��֤��ޤ���
  # $use_re     : [1] 0: ����ɽ���ޥå�����Ѥ��ޤ��� 1: ���Ѥ��ޤ���
  # $use_flag   : [1] 0: +��-����Ѥ��ޤ���           1: ���Ѥ��ޤ���

  # �֤���      : { 1 (true)  => + �˥ޥå�,
  #                 0 (false) => - �˥ޥå�,
  #                  (undef)  => �ޤä����ޥå����ʤ��ä�
  my ($masks, $str, $match_type, $use_re, $use_flag) = @_;
  if (!defined $masks || !defined $str) {
    return undef;
  }

  return match_array([_split($masks)], $str, $match_type, $use_re, $use_flag);
}

sub match_deep {
  # match_deep�ϼ��Τ褦�ʥޥ����β��˻Ȥ��ޤ���

  # mask: +*!*@*
  # mask: -example!*

  # ����̾             : [������] - ���� -
  # $masks_array       : [̵��] �ޥ�������λ��Ȥ��Ϥ��ޤ���
  #  Mask::match_deep([Mask::mask_array_or_all($this->config->mask('all'))], $msg->prefix)
  #                    : �Τ褦�˻Ȥ��ޤ���
  # $global_match_type : [1] 0: �Ǹ�˥ޥå������Ԥ��ͤ��֤��ޤ��� 1: �ǽ�˥ޥå������Ԥ��ͤ��֤��ޤ���
  my ($masks_array, $str, $g_match_type, $match_type, $use_re, $use_flag) = @_;
  if (!defined $masks_array) {
    return undef;
  }

  $g_match_type = 1 unless defined $g_match_type;

  my $g_matched = undef;
  foreach my $masks (@$masks_array) {
    my $matched = match_array([_split($masks)], $str, $match_type, $use_re, $use_flag);
    if (defined $matched) {
      $g_matched = $matched;
      return $g_matched if $g_match_type == 1;
    }
  }

  return $g_matched;
}

sub match_array {
  # match_array�ϡ�match����ƤФ�������ؿ��Ǥ��������̤˸ƤӽФ��ƻȤ����Ȥ�Ǥ��ޤ���
  # match �Ȥΰ㤤�ϡ��ޥ�����ޥ�������λ��ȤȤ����Ϥ����Ǥ���

  # $match_type: 0: last matching rule, 1: first matching rule
  # $use_re    : use 're:' feature.
  # $use_flag  : use [+-] match flag.

  # <return value> : status { 1 (true)  => +, matched,
  #                           0 (false) => -, matched,
  #                            (undef)  => no-match }
  my ($mask_array, $str, $match_type, $use_re, $use_flag) = @_;

  if (!defined $mask_array || ref($mask_array) ne 'ARRAY' || !defined $str) {
    return undef;
  }

  $match_type = 0 unless defined $match_type;
  $use_re = 1 unless defined $use_re;
  $use_flag = 1 unless defined $use_flag;

  my $matched = undef;
  foreach my $part (@$mask_array) {
    my $work = $part;
    my $first = substr($work, 0, 1);
    my $include = 1;
    if (!$use_flag) {
      # noop
    } elsif ($first eq '+') {
      substr($work, 0, 1) = '';
    } elsif ($first eq '-') {
      $include = 0;
      substr($work, 0, 1) = '';
    }

    if ($use_re && substr($work, 0, 3) eq 're:') {
      # ����ɽ��
      $work = substr($work,3);
      # untaint
      $work =~ /\A(.*)\z/s;
      $work = eval {
	qr/$1/;
      }; if ($@) {
	$work = '';
	carp "error in regex: $@";
      }
    } else {
      $work = make_regex($work);
    }

    if ($str =~ m/$work/) {
      # �ޥå�����
      $matched = $include;
      return $matched if  $match_type == 1;
    }
  }
  return $matched;
}


# channel version
sub match_chan {
  my ($masks, $str, $chan, $match_type, $use_re, $use_flag) = @_;
  if (!defined $masks || !defined $str) {
    return undef;
  }

  return match_array_chan(_split_with_chan($masks), $str, $chan, $match_type, $use_re, $use_flag);
}

sub match_deep_chan {
  my ($masks_array, $str, $chan, $g_match_type, $match_type, $use_re, $use_flag) = @_;
  if (!defined $masks_array) {
    return undef;
  }

  $g_match_type = 1 unless defined $g_match_type;

  my $g_matched = undef;
  foreach my $masks (@$masks_array) {
    my $matched = match_array_chan(_split_with_chan($masks), $str, $chan, $match_type, $use_re, $use_flag);
    if (defined $matched) {
      $g_matched = $matched;
      return $g_matched if $g_match_type == 1;
    }
  }

  return $g_matched;
}

my $chanmask_mode = undef; # undefined,
my $CHANMASK_TIARRA = 1;
my $CHANMASK_PLUM = 2;

# tiarra Configuration check;
sub _check_chanmask_conf {
  # configuration ���ɤߡ�chanmask_mode ����ꤹ�롣
  use Configuration;

  my $maskmode = Configuration::shared_conf->general->chanmask_mode;
  if (defined $maskmode) {
    if ($maskmode =~ /plum/i) {
      $chanmask_mode = $CHANMASK_PLUM;
    } elsif ($maskmode =~ /tiarra/i) {
      $chanmask_mode = $CHANMASK_TIARRA;
    } else {
      ::printmsg('Configure_variable [maskmode] ' . $maskmode . ' is not known... use Tiarra mode.');
      $chanmask_mode = $CHANMASK_TIARRA;
    }
  } else {
    # fallback
    $chanmask_mode = $CHANMASK_TIARRA;
  }
}

sub match_array_chan {
  # $match_type: 0: last matching rule, 1: first matching rule
  # $use_re    : use 're:' feature.
  # $use_flag  : use [+-] match flag.

  # <return value> : status { 1 (true)  => +, matched,
  #                           0 (false) => -, matched,
  #                            (undef)  => no-match }
  my ($usermask_array, $chanmask_array, $str, $chan, $match_type, $use_re, $use_flag) = @_;

  return undef if (!defined $str);
  foreach my $var ($usermask_array, $chanmask_array) {
    return undef if (!defined $var || ref($var) ne 'ARRAY');
  }

  _check_chanmask_conf() if (!defined($chanmask_mode));

  my ($chanmask_use_flag);
  if ($chanmask_mode == $CHANMASK_TIARRA) {
    $chanmask_use_flag = $use_flag;
  } elsif ($chanmask_mode == $CHANMASK_PLUM) {
    $chanmask_use_flag = 0;
  } else {
    croak 'chanmask_mode is unsupported value!';
  }

  # channel�ޥå���ԤäƤ���user�ޥå���Ԥ���
  # channel�ޥå��Ǥ�flag�ϻȤ�ʤ���
  my $matched = undef;
  if (Multicast::channel_p($chan)) {
    # $chan��channel�λ������̤˥ޥå���
    $matched = match_array($chanmask_array, $chan, $match_type, $use_re, $chanmask_use_flag);
  } else {
    # $chan��channel�Ǥʤ��Ȥ���priv���ʤΤ� * �˥ޥå������롣
    $matched = match_array($chanmask_array, '*', $match_type, $use_re, $chanmask_use_flag);
  }

  $matched = undef unless $matched; # match���ʤ��ä���undef����������
  # channel�ǥޥå����ʤ��ä��餳�ιԤ�̵�뤹�롣
  if (defined $matched) {
    $matched = undef;
    $matched = match_array($usermask_array, $str, $match_type, $use_re, $use_flag);
  }

  return $matched;
}

# support functions
my $cache_limit = 150;
my @cache_keys;
my %cache_table;
sub make_regex {
    my $str = $_[0];

    if (my $cached = $cache_table{$str}) {
	$cached;
    }
    else {
	# ����å��夵��Ƥ��ʤ���
	if (@cache_keys >= $cache_limit) {
	    # ����å��夵��Ƥ����ͤ������˰�ľä���
	    my $to_delete = scalar(splice @cache_keys, int(rand @cache_keys), 1);
	    delete $cache_table{$to_delete};
	}

	my $compiled = compile($str);
	push @cache_keys, $str;
	$cache_table{$str} = $compiled;
	
	$compiled;
    }
}

sub compile {
    # $mask: �ޥ���ʸ����
    # $consider_case: ���ʤ顢��ʸ����ʸ������̤��롣
    my ($mask, $consider_case) = @_;

    if (!defined $mask) {
	return qr/(?!)/; # �ޥå����ʤ�����ɽ��
    }

    my $regex = $mask;
    $regex =~ s/(\W)/\\$1/g;
    $regex =~ s/\\\?/\./g;
    $regex =~ s/\\\*/\.\*/g;
    $regex = "^$regex\$";
    if ($consider_case) {
	qr/$regex/;
    }
    else {
	qr/$regex/i;
    }
}

sub _split {
    # ',' �Ǥ櫓��줿�ޥ���������ˤ��롣
    my $mask = shift;
    return () if !defined $mask;

    return map {
	s/\\,/,/g;
	$_;
    } split /(?<!\\),/,$mask;
}

sub _split_with_chan {
    # �����ͥ��դ��ޥ���������ˤ��롣
    # �ѥ�᡼��: mask �ץ�ѥƥ�������
    # output (user-array-ref, channel-array-ref)
    _check_chanmask_conf() if (!defined($chanmask_mode));

    if ($chanmask_mode == $CHANMASK_TIARRA) {
	my ($chan, $user) = split(/\s+/, shift, 2);

	return [_split($user)], [_split($chan)];
    } elsif ($chanmask_mode == $CHANMASK_PLUM) {
	my ($user, @chanarray) = split(/\s+/, shift);

	@chanarray = '*' unless @chanarray;

	@chanarray = map {
	    s/\\,/,/g;
	    $_;
	} map {
	    split /(?<!\\),/;
	} @chanarray;

	return [_split($user)], [@chanarray];
    } else {
	croak 'chanmask_mode is unsupported value!';
    }
}

# not related but often use
sub array_or_default {
  my ($default, @array) = @_;

  unless (@array) {
    return $default;
  } else {
    return @array;
  }
}

sub array_or_all {
  return array_or_default(all_mask(), @_);
}

sub array_or_all_chan {
  return array_or_default(all_chan_mask(), @_);
}

sub all_mask {
  return '*';
}

sub all_chan_mask {
  _check_chanmask_conf() if (!defined($chanmask_mode));
  if ($chanmask_mode == $CHANMASK_TIARRA) {
    return '* *!*@*';
  } elsif ($chanmask_mode == $CHANMASK_PLUM) {
    return '*!*@*';
  } else {
    croak 'chanmask_mode is unsupported value!';
  }
}


1;
