# -----------------------------------------------------------------------------
# $Id: Block.pm,v 1.11 2004/02/23 02:46:18 topia Exp $
# -----------------------------------------------------------------------------
package Configuration::Block;
use strict;
use warnings;
use vars qw($AUTOLOAD);
use UNIVERSAL;
use Unicode::Japanese;
# �ͤ��������ˤ�get�᥽�åɤ��Ѥ���¾������ȥ�̾�򤽤Τޤޥ᥽�åɤȤ��ƸƤֻ������ޤ���
#
# $block->hoge;
# ����ǥѥ�᡼��hoge���ͤ��֤���hoge��̤����ʤ�undef�ͤ��֤���
# hoge���ͤ���Ĥ������ä��餽����֤�����ʣ�����ͤ�¸�ߤ����餽����Ƭ���ͤ������֤���
# �ͤ�֥�å����ä��顢���Υ֥�å����֤���
#
# $block->hoge('all');
# �ѥ�᡼��hoge�����Ƥ��ͤ�������֤���hoge��̤����ʤ����������֤���
# �ͤ���Ĥ���̵������ͤ���Ĥ�������֤���
#
# $block->foo_bar;
# $block->foo_bar('all');
# �ѥ�᡼��"foo-bar"���ͤ��֤���"foo_bar"�ǤϤʤ���
#
# $block->foo('random');
# �ѥ�᡼��foo��ʣ�������������С����Τ����ΰ�Ĥ��������֤���
# ��Ĥ�̵�����undef���֤���
#
# $block->foo_bar('block');
# $block->get('foo-bar', 'block');
# �ѥ�᡼��"foo-bar"���ͤ�̤����Ǥ����硢undef�ͤ������
# ����Configuration::Block���֤���
# �������Ƥ����硢�����ͤ��֥�å��Ǥ���Ф�����֤�����
# �����Ǥʤ���� "foo-bar: ������" �����Ǥ���ä��֥�å�����������������֤���
#
# $block->get('foo_bar');
# $block->get('foo_bar','all');
# �ѥ�᡼��"foo_bar"���ͤ��֤���
#
# �ʾ�λ����顢Configuration::Block��new,block_name,table,set,get,
# reinterpret-encoding,AUTOLOAD�Ȥ��ä�°����get()�Ǥ����ɤ�ʤ���
# �ޤ���°��̾�˥�����������������°����get()�Ǥ����ɤ�ʤ���

use constant BLOCK_NAME => 0;
use constant TABLE      => 1;

sub new {
    my ($class,$block_name) = @_;
    my $obj = bless [] => $class;
    $obj->[BLOCK_NAME] = $block_name;
    $obj->[TABLE]      = {}; # ��٥� -> ��(�����ե��⤷���ϥ����顼)
    $obj;
}

sub block_name {
    my ($this,$newvalue) = @_;
    if (defined $newvalue) {
	$this->[BLOCK_NAME] = $newvalue;
    }
    $this->[BLOCK_NAME];
}

sub table {
    my ($this,$newvalue) = @_;
    if (defined $newvalue) {
	$this->[TABLE] = $newvalue;
    }
    $this->[TABLE];
}

sub equals {
    # ��Ĥ�Configuration::Block�������������ʤ�1���֤���
    my ($this,$that) = @_;
    # �֥�å�̾
    if ($this->[BLOCK_NAME] ne $that->[BLOCK_NAME]) {
	return undef;
    }
    # �����ο�
    my @this_keys = keys %{$this->[TABLE]};
    my @that_keys = keys %{$that->[TABLE]};
    if (@this_keys != @that_keys) {
	return undef;
    }
    # ������
    my $size = @this_keys;
    for (my $i = 0; $i < $size; $i++) {
	# ����
	if ($this_keys[$i] ne $that_keys[$i]) {
	    return undef;
	}
	# �ͤη�
	my $this_value = $this->[TABLE]->{$this_keys[$i]};
	my $that_value = $that->[TABLE]->{$that_keys[$i]};
	if (ref($this_value) ne ref($that_value)) {
	    return undef;
	}
	# ��
	if (ref($this_value) eq 'ARRAY') {
	    # ����ʤΤ����ǿ��������Ǥ���ӡ�
	    if (@$this_value != @$that_value) {
		return undef;
	    }
	    my $valsize = @$this_value;
	    for (my $j = 0; $j < $valsize; $j++) {
		if ($this_value->[$j] ne $that_value->[$j]) {
		    return undef;
		}
	    }
	}
	elsif (UNIVERSAL::isa($this_value,'Configuration::Block')) {
	    # �֥�å��ʤΤǺƵ�Ū����ӡ�
	    return $this_value->equals($that_value);
	}
	else {
	    if ($this_value ne $that_value) {
		return undef;
	    }
	}
    }
    return 1;
}

sub eval_code {
    # �Ϥ��줿ʸ������Ρ����Ƥ�%CODE{ ... }EDOC%��ɾ�������֤���
    my ($this,$str) = @_;

    if (ref($str)) {
	return $str; # ʸ����Ǥʤ��ä��餽�Τޤ��֤���
    }

    my $eval = sub {
	my $script = shift;
	no strict; no warnings;
	my $result = eval "package Configuration::Implanted; $script";
	use warnings; use strict;
	if ($@) {
	    die "\%CODE{ }EDOC\% interpretation error.\n".
		"block: ".$this->[BLOCK_NAME]."\n".
		"original: $str\n".
		"$@\n";
	}
	$result;
    };
    (my $evaluated = $str) =~ s/\%CODE{(.*?)}EDOC\%/$eval->($1)/eg;
    $evaluated;
}

sub get {
    my ($this,$key,$option) = @_;

    unless (exists $this->[TABLE]->{$key}) {
	# ���Τ褦���ͤ��������Ƥ��ʤ���
	if ($option && $option eq 'all') {
	    return ();
	}
	elsif ($option and $option eq 'block') {
	    return Configuration::Block->new($key);
	}
	else {
	    return undef;
	}
    }

    my $value = $this->[TABLE]->{$key};
    if ($option && $option eq 'all') {
	if (ref($value) eq 'ARRAY') {
	    return map {
		$this->eval_code($_);
	    } @{$value}; # �����ե��ʤ�ջ��Ȥ����֤���
	}
	else {
	    return $this->eval_code($value);
	}
    }
    elsif ($option && $option eq 'random') {
	if (ref($value) eq 'ARRAY') {
	    # �����ե��ʤ�������������֤�
	    return $this->eval_code(
		$value->[int(rand(0xffffffff)) % @$value]);
	}
	else {
	    return $this->eval_code($value);
	}
    }
    elsif ($option and $option eq 'block') {
	if (ref($value) and UNIVERSAL::isa($value, 'Configuration::Block')) {
	    return $value;
	}
	else {
	    my $tmp_block = Configuration::Block->new($key);
	    $tmp_block->set($key, $value);
	    return $tmp_block;
	}
    }
    else {
	if (ref($value) eq 'ARRAY') {
	    return $this->eval_code($value->[0]); # �����ե��ʤ���Ƭ���ͤ��֤���
	}
	else {
	    return $this->eval_code($value);
	}
    }
}

sub set {
    # �Ť��ͤ�����о�񤭤��롣
    my ($this,$key,$value) = @_;
    $this->[TABLE]->{$key} = $value;
    $this;
}

sub add {
    # �Ť��ͤ�����Ф�����ɲä��롣
    my ($this,$key,$value) = @_;
    if (defined $this->[TABLE]->{$key}) {
	# ����Ѥߡ�
	if (ref($this->[TABLE]->{$key}) eq 'ARRAY') {
	    # ����ʣ�����ͤ���äƤ���ΤǤ����ɲä��롣
	    push @{$this->[TABLE]->{$key}},$value;
	}
	else {
	    # ������ѹ����롣
	    $this->[TABLE]->{$key} = [$this->[TABLE]->{$key},$value];
	}
    }
    else {
	# ����ѤߤǤʤ���
	$this->[TABLE]->{$key} = $value;
    }
}

sub reinterpret_encoding {
    # ���Υ֥�å������Ƥ����Ǥ���ꤵ�줿ʸ�����󥳡��ǥ��󥰤ǺƲ�᤹�롣
    # �Ʋ����UTF-8�ˤʤ롣
    my ($this,$encoding) = @_;

    my $unicode = Unicode::Japanese->new;
    my $newtable = {};
    while (my ($key,$value) = each %{$this->[TABLE]}) {
	my $newkey = $unicode->set($key,$encoding)->utf8;
	my $newvalue = do {
	    if (ref($value) eq 'ARRAY') {
		# ����ʤΤ���Ȥ����ƥ������Ѵ���
		my @newarray = map {
		    $unicode->set($_,$encoding)->utf8;
		} @$value;
		\@newarray;
	    }
	    elsif (UNIVERSAL::isa($value,'Configuration::Block')) {
		# �֥�å��ʤΤǺƵ�Ū�˥������Ѵ���
		$value->reinterpret_encoding($encoding);
	    }
	    else {
		$unicode->set($value,$encoding)->utf8;
	    }
	};
	$newtable->{$newkey} = $newvalue;
    }

    $this->[TABLE] = $newtable;
    $this;
}

sub AUTOLOAD {
    my ($this,$option) = @_;
    
    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROY����ã�����ʤ���
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    $key =~ s/_/-/g;
    return $this->get($key,$option);
}

1;
