# -*- cperl -*-
# $Clovery: tiarra/module/Tools/HashDB.pm,v 1.2 2003/07/24 03:05:47 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# GroupDB ��1�쥳����ʬ�Υǡ������ݻ����롣

# - ����(���) -
#  * ����̾��Ⱦ�ѥ��ڡ����ϴޤ���ޤ��� error ���Фޤ���
#  * �ͤ���Ƭ���Ǹ�ˤ������ʸ��(\s)���ɤ߹��߻��˾ü����ޤ���
#  * ��ǽ��­�Ǥ���
#  * �����ɤ��ɤߤˤ����Ǥ���

# technical information
#  - datafile format
#    | abc: def
#      -> key 'abc', value 'def'
#    | : abc : def
#      -> key ':abc:', value 'def'
#    LINE := KEY ANYSPACES [value] ANYSPACES �����ܡ�
#    KEY := ANYSPACES [keyname] ANYSPACES ':' || ANYSPACES ':' [keyname] ':'
#    ANYSPACES := REGEXP:\s*
#    [keyname] �ˤϥ����򥹥ڡ������Ѵ���������̾�����롣
#      ����̾����Ƭ�ޤ��ϺǸ�˥��ڡ�����������ϡ�KEY�θ�ԤΥե����ޥåȤ���Ѥ��롣
#    [value] �Ϥ��Τޤޡ��Ĥޤ�ʣ���Ԥˤʤ�ǡ������ɲäǤ��ʤ������顼��Ф��٤���?

package Tools::HashDB;
use strict;
use warnings;
use IO::File;
use File::stat;
use Unicode::Japanese;
use Mask;
use Carp;
use Module::Use qw(Tools::HashTools);
use Tools::HashTools;

sub new {
    # ���󥹥ȥ饯��

    # - ���� -
    # $fpath	: ��¸����ե�����Υѥ������ե����� or undef �ǥե�����˴�Ϣ�դ����ʤ�DB����������ޤ���
    # $charset	: �ե������ʸ�����åȤ���ꤷ�ޤ�����ά����� UTF-8 �ˤʤ�ޤ���
    # $use_re	: �ͤθ���/����Ƚ�������ɽ����ĥ��Ȥ����ɤ�������ά�����лȤ��ޤ���
    # $ignore_proc
    # 		: ̵�뤹��Ԥ���ꤹ�륯�����㡣�Ԥ�����˸ƤӽФ��졢 true ���֤�Ф��ιԤ�̵�뤷�ޤ���
    # 		  ������ ignore ���줿�Ԥϲ��Ϥ����Ԥ��ޤ���Τǡ�
    # 		  $split_primary=0�Ǥ���ڤ��ǧ�����줿��Ϥ��ޤ���
    # 		  ����Ū����դȤ��ơ����ξ��֤Υǡ����١�������¸���줿���� ignore ���줿�Ԥ����ƾ��Ǥ��ޤ���

    my ($class,$fpath,$charset,$use_re,$ignore_proc) = @_;

    my $obj = {
	time => undef,			# �ե�����κǽ��ɤ߹��߻���
	fpath => $fpath,
	charset => $charset || 'utf8',	# �ե������ʸ��������
	use_re => $use_re || 0,
	ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },

	database => undef,		# HASH
    };

    bless $obj,$class;
    $obj->_load;
}

sub _load {
    my $this = shift;
    $this->{database} = {};

    if (defined $this->{fpath} && $this->{fpath} ne '') {
	my $fh = IO::File->new($this->{fpath},'r');
	if (defined $fh) {
	    my $unicode = Unicode::Japanese->new;
	    foreach (<$fh>) {
		my $line = $unicode->set($_, $this->{charset})->get;
		next if $this->{ignore_proc}->($line);
		my ($key,$value) = grep {defined($_)} ($line =~ /^\s*(?:([^:]+?)\s*|:([^:]+?)):\s*(.+?)\s*$/);
		if (!defined $key || $key eq '' ||
			!defined $value || $value eq '') {
		    # ignore
		} else {
		    $key =~ s/ /:/g; # can use colon(:) on key, but cannot use space( ).
		    push(@{$this->{database}->{$key}}, $value);
		}
	    }
	    $this->{time} = time();
	}
    }
    return $this;
}

sub checkupdate {
    my $this = shift;

    if (defined $this->{fpath} && $this->{fpath} ne '') {
	my $stat = stat($this->{fpath});

	if (defined $stat && $stat->mtime > $this->{time}) {
	    $this->_load();
	    return 1;
	}
    }
    return 0;
}

sub synchronize {
    my $this = shift;
    if (defined $this->{fpath} && $this->{fpath} ne '') {
	my $fh = IO::File->new($this->{fpath},'w');
	if (defined $fh) {
	    my $unicode = Unicode::Japanese->new;
	    while (my ($key,$values) = each %{$this->{database}}) {
		$key =~ s/:/ /g; # can use colon(:) on key, but cannot use space( ).
		# \s ����Ƭ/�Ǹ�ˤ��ä�����ɤ߹��ߤǾä����ΤǤ�����ɻߡ�
		$key = ':' . $key if ($key =~ /^\s/ || $key =~ /\s$/);
		map {
		    my $line = "$key: " . $_ . "\n";
		    $fh->print($unicode->set($line)->conv($this->{charset}));
		} @$values
	    }
	    $this->{time} = time();
	}
    }
    return $this;
}

sub to_hashref {
    my $this = shift;

    $this->checkupdate();

    return $this->{database};
}

sub keys {
    my $this = shift;

    $this->checkupdate();

    return CORE::keys(%{$this->to_hashref});
}

sub values {
    my $this = shift;

    $this->checkupdate();

    return CORE::values(%{$this->to_hashref});
}

sub add_value {
    # �ͤ��ɲä��롣
    # ��������� 1(true) ���֤롣
    # �����ʥ����Τ��Ἲ�Ԥ������� 0(false) ���֤롣

    my ($this, $key, $value) = @_;

    return 0 if $key =~ / /;

    $this->checkupdate();

    my $values = $this->{database}->{$key};
    if (!defined $values) {
	$values = [];
	$this->{database}->{$key} = $values;
    }
    push @$values,$value;

    $this->synchronize();

    return 1;
}

sub del_value {
    my ($this, $key, $value) = @_;

    $this->checkupdate();

    my $values = $this->{database}->{$key};
    if (defined $values) {
	# ���ä���
	my ($count) = scalar @$values;
	if (defined $value) {
	    @$values = grep {
		$_ ne $value;
	    } @$values;
	    $count -= scalar(@$values);
	    # ���ι��ܤ����ˤʤä�����ܼ��Τ���
	    if (@$values == 0) {
		delete $this->{database}->{$key};
	    }
	} else {
	    # $value �����ꤵ��Ƥ��ʤ����Ϲ��ܺ��
	    delete $this->{database}->{$key};
	}

	$this->synchronize();

	return $count;		# deleted
    }
    return 0;			# not deleted
}

sub get_value_random {
    my ($this, $key) = @_;

    $this->checkupdate();
    return Tools::HashTools::get_value_random($this->{database}, $key);
}

sub get_value {
    my ($this, $key) = @_;

    $this->checkupdate();
    return Tools::HashTools::get_value($this->{database}, $key);
}

sub get_array {
    my ($this, $key) = @_;

    $this->checkupdate();
    return Tools::HashTools::get_array($this->{database}, $key);
}


# group misc functions
sub dup_group {
    # ���롼�פ�ʣ����Ԥ��ޤ���

    my ($group) = @_;
    my ($new_group) = {};

    return undef unless defined($group);

    map {
	$new_group->{$_} = $group->{$_};
    } CORE::keys(%$group);

    return $new_group;
}

sub concat_string_to_key {
    # prefix �� suffix �� group �� key ���ղä��ޤ���

    # - ���� -
    # $group	: ���롼�ס�
    # $prefix	: prefix ʸ���� ('to.' �Ȥ� 'from.' �Ȥ�)
    # $suffix	: suffix ʸ����
    my ($group, $prefix, $suffix) = @_;
    my ($new_group) = {};

    $prefix = '' unless defined($prefix);
    $suffix = '' unless defined($suffix);

    map {
	$new_group->{$prefix . $_ . $suffix} = $group->{$_};
    } CORE::keys(%$group);

    return $new_group;
}

# replace support functions
sub replace_with_callbacks {
    # �ޥ�����ִ���Ԥʤ���%optional���ִ����ɲä��륭�����ͤ��Ȥߤǡ���ά�ġ�
    # $callbacks��group/optional���ִ��Ǥ��ʤ��ä��ݤ˸ƤӽФ���륳����Хå��ؿ��Υ�ե���󥹡�
    # optional���ͤ�SCALAR�Ǥ�ARRAY<SCALAR>�Ǥ��ɤ���
    my ($this,$str,$callbacks,%optional) = @_;
    my $main_table = %{$this->to_hashref};
    return Tools::HashTools::replace_recursive($str,[$main_table,\%optional],$callbacks);
}

1;
