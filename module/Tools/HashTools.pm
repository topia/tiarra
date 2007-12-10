# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# ハッシュをフォーマットする関数群。

package Tools::HashTools;

sub get_value_random {
    my ($hash, $key) = @_;

    my $values = get_array($hash, $key);
    if ($values) {
	# 発見. どれか一つ選ぶ。
	my $idx = int(rand() * hex('0xffffffff')) % @$values;
	return $values->[$idx];
    }
    return undef;
}

sub get_value {
    my ($hash, $key) = @_;

    my $values = get_array($hash, $key);
    if ($values) {
	# 発見.
	return $values->[0];
    }
    return undef;
}

sub get_array {
    my ($hash, $key) = @_;

    my $value = $hash->{$key};
    if (defined $value) {
	# 発見
	if (ref($value) eq 'ARRAY') {
	    return $value;
	} else {
	    return [$value];
	}
	last;
    }
    return undef;
}

sub replace_recursive {
    # ()がネスト可能な_replace.

    # ていうか ad hoc 過ぎる気がするなあ。良い解析方法無いかな。

    my ($str,$hashtables,$callbacks) = @_;

    return '' if !defined($str) || ($str eq '');

    my $start = 0;
    my $end;
    my $pos;
    while (($pos = $start = index($str, '#(', $start)) != -1) {
	# 検索開始。
	my $level = 1;
	do {
	    # こっかを探す。
	    $end = index($str, ')', $pos + 1);
	    if ($end == -1) {
		# こっかが無い。困ったことになったが、終わった後にこっかがあったことにして誤魔化そう。
		$str .= ')';
		$end = length($str);
		last;
	    }

	    # かっこを探す。
	    my $next = index($str, '(', $pos + 2);
	    if ($next == -1 || $next > $end) {
		# かっこが無かったか、こっかより後。階層レベルを減らして検索位置を次のこっかに移す。
		$pos = $end;
		$level--;
	    } else {
		# こっかより前にかっこがあった。階層レベルを増やして繰り返す。
		$pos = $next;
		$level++;
	    }
	} while ($level > 0);	# 階層レベルが0になるまで繰り返し。
	# こっかの前までを抽出範囲とする。
	$end--;
	#proc $start  to  $end
	my $work = substr($str, $start + 2, $end - $start - 1);
	$work = _replace($work,$hashtables,$callbacks);
	substr($str, $start, $end - $start + 2) = $work;
	$start = $start + length($work);
    }

    return $str;
}

sub _replace {
    my ($str,$hashtables,$callbacks) = @_;

    # variables := variable ( '|' variable )*
    # variable  := key ( ';' format )?
    foreach my $variable (split /\|/,$str) {
	my ($key, $format) = split(/;/,$variable,2);
	my ($ret) = undef;
	if (defined($key) && $key ne '') {
	    foreach my $table (@$hashtables) {
		$ret =  get_value($table, $key);
		last if (defined $ret);
	    }
	    if (!defined $ret) {
		# not found.
		foreach my $callback (@$callbacks) {
		    if (defined $callback) {
			# callback function definition: func($key, [hashtables], [callbacks]);
			my $value = $callback->($key, $hashtables, $callbacks);
			if (defined $value) {
			    $ret = $value;
			    last;
			}
		    }
		}
	    }
	} else {
	    # callback等がエラーを吐くので強制的に''を入れる。
	    $ret = '';
	}
	if (defined $ret) {
	    if (defined $format) {
		return _format($format,$ret,$hashtables,$callbacks);
	    } else {
		return $ret;
	    }
	}
    }
    # 最終的に見付からなければ$strそのものを返す。
    return $str;
}

sub _format {
    # %s形式の値をフォーマットする。
    # replace_recursiveを呼び出して再帰変換も行う。
    my ($str,$value,$hashtables,$callbacks) = @_;

    $str = replace_recursive($str,$hashtables,$callbacks);
    $str =~ s/%(.)/_format_percent($1, $value)/eg;
    return $str;
}

sub _format_percent {
    $char = shift;

    if ($char eq 's') {
	return $_[0];
    } else {
	return $char;
    }
}

1;
