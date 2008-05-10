# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Mask;
use strict;
use warnings;
use Carp;
use Multicast;


# -----------------------------------------------------------------------------
# $bool = match($masks, $str).
# $bool = match($masks, $str, $match_type, $use_re, $use_flag).
# どれにもマッチしなかった際はundef, つまり偽がかえる.
# 明示的に拒否された場合は 0, つまりdefinedな偽が返る.
#
sub match {
  # matchはワイルドカードを使ったマッチングを行う関数です。
  # ワイルドカード以外にも、+や-を使った除外指定や、
  # re: を使った正規表現マッチングが行えます。

  # $masksには','(コンマ)で区切ったマッチリストを渡してください。
  # 条件中に','(コンマ)を使いたい場合は'\,'と書けます。

  # 引数名      : [既定値] - 説明 -
  # $masks      : [-] カンマ区切りのマッチリスト.
  # $str        : [-] マッチ対象の文字列.
  # $match_type : [0] 0: 最後にマッチした値を返します。 1: 最初にマッチした値を返します。
  # $use_re     : [1] 0: 正規表現マッチを使用しません。 1: 使用します。
  # $use_flag   : [1] 0: +や-を使用しません。           1: 使用します。

  # 返り値      : { 1 (true)  => + にマッチ,
  #                 0 (false) => - にマッチ,
  #                  (undef)  => まったくマッチしなかった
  my ($masks, $str, $match_type, $use_re, $use_flag) = @_;
  if (!defined $masks || !defined $str) {
    return undef;
  }

  return match_array([_split($masks)], $str, $match_type, $use_re, $use_flag);
}

# -----------------------------------------------------------------------------
# $bool = match_deep(\@masks_list, $str).
# $bool = match_deep(\@masks_list, $str, $g_match_type, $match_type, $use_re, $use_flag);
# @masks の各要素に対して match() を行う.
#
sub match_deep {
  # match_deepは次のようなマスクの解釈に使います。

  # mask: +*!*@*
  # mask: -example!*

  # 引数名             : [既定値] - 説明 -
  # $masks_array       : [無し] マスク配列の参照を渡します。
  #  Mask::match_deep([Mask::mask_array_or_all($this->config->mask('all'))], $msg->prefix)
  #                    : のように使います。
  # $global_match_type : [1] 0: 最後にマッチした行の値を返します。 1: 最初にマッチした行の値を返します。
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

# -----------------------------------------------------------------------------
# $bool = match_array(\@masks, $str).
# $bool = match_array(\@masks, $str, $match_type, $use_re, $use_flag).
#
sub match_array {
  # match_arrayは、matchから呼ばれる内部関数ですが、普通に呼び出して使うこともできます。
  # match との違いは、マスクをマスク配列の参照として渡す点です。

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
      # 正規表現
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
      # マッチした
      $matched = $include;
      return $matched if  $match_type == 1;
    }
  }
  return $matched;
}


# channel version
# Mask::match_chan($mask, $user_long, $ch_long).
# $mask      = '#{example}@ircnet,-#{example2}@2ch   +*!*@*.example.com'
# $user_long = 'nick!user@remote'
# $ch_long   = '#chan@ircnet:*.jp'
# ユーザ名/チャンネル名のマッチング.
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
  # configuration を読み、chanmask_mode を決定する。
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

  # channelマッチを行ってからuserマッチを行う。
  # channelマッチではflagは使わない。
  my $matched = undef;
  if (Multicast::channel_p($chan)) {
    # $chanがchannelの時は普通にマッチ。
    $matched = match_array($chanmask_array, $chan, $match_type, $use_re, $chanmask_use_flag);
  } else {
    # $chanがchannelでないときはpriv等なので * にマッチさせる。
    $matched = match_array($chanmask_array, '*', $match_type, $use_re, $chanmask_use_flag);
  }

  $matched = undef unless $matched; # matchしなかったらundefを代入する
  # channelでマッチしなかったらこの行は無視する。
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
	# キャッシュされていない。
	if (@cache_keys >= $cache_limit) {
	    # キャッシュされている値をランダムに一つ消す。
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
    # $mask: マスク文字列
    # $consider_case: 真なら、大文字小文字を区別する。
    my ($mask, $consider_case) = @_;

    if (!defined $mask) {
	return qr/(?!)/; # マッチしない正規表現
    }

    my $regex = quotemeta($mask);
    $regex =~ s/\\\?/./g;
    $regex =~ s/\\\*/.*/g;
    #$regex =~ s/\\\#/\\d*/g;
    $regex = "^$regex\$";
    if ($consider_case) {
	qr/$regex/;
    }
    else {
	qr/$regex/i;
    }
}

sub _split {
    # ',' でわけられたマスクを配列にする。
    my $mask = shift;
    return () if !defined $mask;

    return map {
	s/\\,/,/g;
	$_;
    } split /(?<!\\),/,$mask;
}

sub _split_with_chan {
    # チャンネル付きマスクを配列にする。
    # パラメータ: mask プロパティの配列
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
