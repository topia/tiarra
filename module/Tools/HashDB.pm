# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.

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
use Module::Use qw(Tools::Hash Tools::HashTools);
use Tools::Hash;
use Tools::HashTools;
use Tiarra::Utils;
use Tiarra::ModifiedFlagMixin;
use Tiarra::SessionMixin;
use base qw(Tiarra::SessionMixin);

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

    my $this = {
	time => undef,			# �ե�����κǽ��ɤ߹��߻���
	fpath => $fpath,
	charset => $charset || 'utf8',	# �ե������ʸ��������
	use_re => $use_re || 0,
	ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },

	database => undef,		# HASH
    };

    bless $this,$class;
    $this->clear_modified;
    $this->_session_init;
    $this->_load;
}

__PACKAGE__->define_attr_accessor(0,
				  qw(time fpath charset),
				  qw(use_re));
__PACKAGE__->define_proxy('database', 0,
			  qw(keys values),
			  qw(add_value add_array del_value del_array),
			  qw(get_array get_value get_value_random));
__PACKAGE__->define_session_wrap(0,
				 qw(checkupdate synchronize cleanup));

sub _load {
    my $this = shift;

    my $database = Tools::Hash->new;

    if (defined $this->fpath && $this->fpath ne '') {
	my $fh = IO::File->new($this->fpath,'r');
	if (defined $fh) {
	    my $unicode = Unicode::Japanese->new;
	    foreach (<$fh>) {
		my $line = $unicode->set($_, $this->charset)->get;
		next if $this->{ignore_proc}->($line);
		my ($key,$value) = grep {defined($_)}
		    ($line =~ /^\s*(?:([^:]+?)\s*|:([^:]+?)):\s*(.+?)\s*$/);
		if (!defined $key || $key eq '' ||
			!defined $value || $value eq '') {
		    # ignore
		} else {
		    # can use colon(:) on key, but cannot use space( ).
		    $key =~ s/ /:/g;
		    $database->add_value($key, $value);
		}
	    }
	    $this->{database} = $database;
	    $this->set_time;
	    $this->clear_modified;
	}
    }
    return $this;
}

sub _checkupdate {
    my $this = shift;

    if (defined $this->fpath && $this->fpath ne '') {
	my $stat = stat($this->fpath);

	if (defined $stat && defined $this->time &&
		$stat->mtime > $this->time) {
	    $this->_load();
	    return 1;
	}
    }
    return 0;
}

sub _synchronize {
    my $this = shift;
    my $force = shift || 0;

    if (defined $this->fpath && $this->fpath ne '' &&
	    ($this->modified || $force)) {
	my $fh = IO::File->new($this->fpath,'w');
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
	    $this->set_time;
	    $this->clear_modified;
	}
    }
    return $this;
}

sub set_time       { shift->time(CORE::time); }

sub database {
    my $this = shift;
    return $this->with_session(sub{$this->{database};});
}
*to_hashref = \&database;

sub _before_session_start {
    my $this = shift;
    $this->_checkupdate;
}

sub _after_session_finish {
    my $this = shift;
    $this->_synchronize;
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
