# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# �ϥå����ե����ޥåȤ���ؿ�����

package Tools::HashTools;

sub get_value_random {
    my ($hash, $key) = @_;

    my $values = get_array($hash, $key);
    if ($values) {
	# ȯ��. �ɤ줫������֡�
	my $idx = int(rand() * hex('0xffffffff')) % @$values;
	return $values->[$idx];
    }
    return undef;
}

sub get_value {
    my ($hash, $key) = @_;

    my $values = get_array($hash, $key);
    if ($values) {
	# ȯ��.
	return $values->[0];
    }
    return undef;
}

sub get_array {
    my ($hash, $key) = @_;

    my $value = $hash->{$key};
    if (defined $value) {
	# ȯ��
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
    # ()���ͥ��Ȳ�ǽ��_replace.

    # �Ƥ����� ad hoc �᤮�뵤������ʤ����ɤ�������ˡ̵�����ʡ�

    my ($str,$hashtables,$callbacks) = @_;

    return '' if !defined($str) || ($str eq '');

    my $start = 0;
    my $end;
    my $pos;
    while (($pos = $start = index($str, '#(', $start)) != -1) {
	# �������ϡ�
	my $level = 1;
	do {
	    # ���ä���õ����
	    $end = index($str, ')', $pos + 1);
	    if ($end == -1) {
		# ���ä���̵�������ä����Ȥˤʤä���������ä���ˤ��ä������ä����Ȥˤ��Ƹ��ⲽ������
		$str .= ')';
		$end = length($str);
		last;
	    }

	    # ���ä���õ����
	    my $next = index($str, '(', $pos + 2);
	    if ($next == -1 || $next > $end) {
		# ���ä���̵���ä��������ä����塣���إ�٥�򸺤餷�Ƹ������֤򼡤Τ��ä��˰ܤ���
		$pos = $end;
		$level--;
	    } else {
		# ���ä�������ˤ��ä������ä������إ�٥�����䤷�Ʒ����֤���
		$pos = $next;
		$level++;
	    }
	} while ($level > 0);	# ���إ�٥뤬0�ˤʤ�ޤǷ����֤���
	# ���ä������ޤǤ�����ϰϤȤ��롣
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
	    # callback�������顼���Ǥ��ΤǶ���Ū��''������롣
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
    # �ǽ�Ū�˸��դ���ʤ����$str���Τ�Τ��֤���
    return $str;
}

sub _format {
    # %s�������ͤ�ե����ޥåȤ��롣
    # replace_recursive��ƤӽФ��ƺƵ��Ѵ���Ԥ���
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
