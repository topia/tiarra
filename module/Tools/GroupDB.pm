# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# �����ꥢ���Τ褦�ˡ�Hash��쥳���ɤȤ���DB��������롣
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.


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

package Tools::GroupDB;
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
my $utils = Tiarra::Utils->shared;

sub new {
    # ���󥹥ȥ饯��

    # - ���� -
    # $fpath	: ��¸����ե�����Υѥ������ե����� or undef �ǥե�����˴�Ϣ�դ����ʤ�DB����������ޤ���
    # $primary_key
    # 		: �祭�������ꤷ�ޤ����ǡ����١���Ū�������Ϥޤä�������ޤ���(��)����Ŭ���˺�äƲ�������
    # 		  $split_primary�����ꤵ��Ƥ��ʤ����� undef ���Ϥ����Ȥ�����ޤ���
    # $charset	: �ե������ʸ�����åȤ���ꤷ�ޤ�����ά����� UTF-8 �ˤʤ�ޤ���
    # $split_primary
    # 		: true �ʤ顢�ǡ����ե����뤫����ɤ߹��߻��ˡ�$primary_key�Ƕ��ڤ�ޤ���
    # 		  �����Ǥʤ���Хǡ�����̵���Ԥ����ڤ�ˤʤ�ޤ�����ά������ false �Ǥ���
    # $use_re	: �ͤθ���/����Ƚ�������ɽ����ĥ��Ȥ����ɤ�������ά�����лȤ��ޤ���
    # $ignore_proc
    # 		: ̵�뤹��Ԥ���ꤹ�륯�����㡣�Ԥ�����˸ƤӽФ��졢 true ���֤�Ф��ιԤ�̵�뤷�ޤ���
    # 		  ������ ignore ���줿�Ԥϲ��Ϥ����Ԥ��ޤ���Τǡ�
    # 		  $split_primary=0�Ǥ���ڤ��ǧ�����줿��Ϥ��ޤ���
    # 		  ����Ū����դȤ��ơ����ξ��֤Υǡ����١�������¸���줿���� ignore ���줿�Ԥ����ƾ��Ǥ��ޤ���

    my ($class,$fpath,$primary_key,$charset,$split_primary,$use_re,$ignore_proc) = @_;

    if (defined $primary_key) {
	if ($primary_key =~ / /) {
	    croak('primary_key name "'.$primary_key.'" include space!')
	}
    } else {
	croak('primary_key not defined, but split_primary is true!') if $split_primary;
    }

    my $this = {
	time => undef, # �ե�����κǽ��ɤ߹��߻���
	fpath => $fpath,
	primary_key => $primary_key,
	split_primary => $split_primary || 0,
	charset => $charset || 'utf8', # �ե������ʸ��������
	use_re => $use_re || 0,
	ignore_proc => $ignore_proc || sub { $_[0] =~ /^\s*#/; },
	cleanup_queued => undef,

	caller_name => $utils->simple_caller_formatter('GroupDB registered'),
	database => undef, # ARRAY<HASH*>
	# <���� SCALAR,�ͤν��� ARRAY<SCALAR>>
    };

    bless $this,$class;
    $this->clear_modified;
    $this->_session_init;
    $this->_load;
}

$utils->define_attr_accessor(0,
			     qw(time fpath charset),
			     qw(primary_key split_primary),
			     qw(cleanup_queued));
__PACKAGE__->define_session_wrap(0,
				 qw(checkupdate synchronize cleanup));

sub name {
    my $this = shift;
    join('/', $this->{caller_name},
	 (defined $this->fpath ? $this->fpath : ()));
}

sub _load {
    my $this = shift;
    my $database = [];

    if (defined $this->fpath && $this->fpath ne '') {
	my $fh = IO::File->new($this->fpath,'r');
	if (defined $fh) {
	    my $current = {};
	    my $flush = sub {
		if ((!$this->split_primary && scalar(%$current)) ||
			(defined $this->primary_key &&
			     defined $current->{$this->primary_key})) {
		    push @{$database}, Tools::Hash->new($this, $current);
		    $current = {};
		}
	    };
	    my $unicode = Unicode::Japanese->new;
	    foreach (<$fh>) {
		my $line = $unicode->set($_, $this->charset)->get;
		next if $this->{ignore_proc}->($line);
		my ($key,$value) = grep {defined($_)}
		    ($line =~ /^\s*(?:([^:]+?)\s*|:([^:]+?)):\s*(.+?)\s*$/);
		if (!defined $key || $key eq '' ||
			!defined $value || $value eq '') {
		    if (!$this->split_primary) {
			$flush->();
		    }
		} else {
		    # can use colon(:) on key, but cannot use space( ).
		    $key =~ s/ /:/g;
		    if ($this->split_primary &&
			    $key eq $this->primary_key) {
			$flush->();
		    }
		    push(@{$current->{$key}}, $value);
		}
	    }
	    $flush->();
	    $this->{database} = $database;
	    $this->set_time;
	    $this->clear_modified;
	    $this->dequeue_cleanup;
	}
    }
    return $this;
}

sub _check_primary_key {
    my $this = shift;

    croak "primary_key not defined; can't use this method."
	unless defined $this->primary_key;
}

sub _check_no_primary_key {
    my $this = shift;

    croak "primary_key defined; can't use this method."
	if defined $this->primary_key;
}

sub _checkupdate {
    my $this = shift;

    if (defined $this->fpath && $this->fpath ne '') {
	my $stat = stat($this->fpath);

	if (defined $stat && defined $this->time &&
		$stat->mtime > $this->time) {
	    $this->_load;
	    return 1;
	}
    }
    return 0;
}

sub queue_cleanup  { shift->cleanup_queued(1); }
sub dequeue_cleanup{ shift->cleanup_queued(0); }
sub set_time       { shift->time(CORE::time); }

sub _synchronize {
    my $this = shift;
    my $force = shift || 0;

    if (defined $this->fpath && $this->fpath ne '' &&
	    ($this->modified || $force)) {
	my $fh = IO::File->new($this->fpath,'w');
	if (defined $fh) {
	    my $unicode = Unicode::Japanese->new;
	    foreach my $person (@{$this->{database}}) {
		my @keys = keys %{$person->data};
		if (defined $this->primary_key) {
		    @keys = grep { $_ ne $this->primary_key } @keys;
		    unshift(@keys, $this->primary_key);
		}
		my ($key, $values);
		foreach $key (@keys) {
		    $values = $person->data->{$key};
		    # can use colon(:) on key, but cannot use space( ).
		    $key =~ s/:/ /g;
		    # \s ����Ƭ/�Ǹ�ˤ��ä�����ɤ߹��ߤǾä����ΤǤ�����ɻߡ�
		    $key = ':' . $key if ($key =~ /^\s/ || $key =~ /\s$/);
		    map {
			my $line = "$key: " . $_ . "\n";
			$fh->print($unicode->set($line)->conv($this->{charset}));
		    } @$values
		}
		$fh->print("\n");
	    }
	    $this->set_time;
	    $this->clear_modified;
	    $this->dequeue_cleanup;
	}
    }
    return $this;
}

sub groups {
    my ($this) = @_;

    return @{$this->with_session(sub{ $this->{database}; })};
}

sub find_group_with_primary {
    # ���դ���ʤ����undef���֤���
    my ($this, $value) = @_;

    $this->_check_primary_key;
    return $this->find_group([$this->primary_key], \$value);
}

sub find_group {
    my ($this, $keys, $values) = @_;

    return $this->find_groups($keys, $values, 1);
}

sub find_groups_with_primary {
    my ($this, $value, $count) = @_;

    $this->_check_primary_key;
    return $this->find_groups([$this->primary_key], [$value], $count);
}

sub find_groups {
    # on not found return 'undef'
    # $keys is ref[array or scalar]
    # $values is ref[array or scalar]
    # $count is num of max found group, optional.
    my ($this, $keys, $values, $count) = @_;
    my (@ret);

    ($keys, $values) = map {
	if (!ref($_)) {
	    [$_];
	} elsif (ref($_) eq 'SCALAR') {
	    [$$_];
	} else {
	    $_;
	}
    } ($keys, $values);

    my ($return) = sub {
	if (wantarray) {
	    return @ret;
	} else {
	    return $ret[0] || undef;
	}
    };

    $this->with_session(
	sub {
	group_loop:
	    foreach my $group (@{$this->{database}}) {
		foreach my $key (@$keys) {
		    foreach my $value (@$values) {
			if (Mask::match_array($group->get_array($key), $value, 1,
					      $this->{use_re}, 0)) {
			    #match.
			    push(@ret, $group);
			    if (defined($count) && ($count <= scalar(@ret))) {
				return $return->();
			    }
			    next group_loop; # next at $group loop.
			}
		    }
		}
	    }
	    return $return->();
	});
}

sub new_group {
    my $this = shift;
    my (@primary_key_values) = @_;

    if (!@primary_key_values && defined $this->primary_key) {
	croak 'primary_key_values not defined! please pass value';
    } elsif (@primary_key_values && !defined $this->primary_key) {
	carp 'primary_key_values defined! ignore value...';
	@primary_key_values = ();
    }
    my $group = Tools::Hash->new($this, {
	(@primary_key_values) ?
	    ($this->primary_key => [@primary_key_values]) :
		()
	       });
    $this->with_session(
	sub {
	    push @{$this->{database}}, $group;
	    $this->set_modified;
	});

    return $group;
}

sub add_group {
    # �ǡ����١����˥��롼�פ��ɲä��롣
    # ��������� 1(true) ���֤롣

    # key �� space ���ޤޤ�ʤ��������å����٤��������Ȥꤢ�����Ϥ��Ƥ��ʤ���
    my ($this, @groups) = @_;
    $this->with_session(
	sub {
	    push @{$this->{database}}, map {
		if (ref($_) eq 'HASH') {
		    Tools::Hash->new($this, $_);
		} else {
		    $_;
		}
	    } @groups;
	    $this->set_modified;
	});

    return 1;
}

sub add_array {
    my ($this, $group, $key, @values) = @_;

    $group->add_array($key, @values);
}

sub add_array_with_primary {
    my ($this, $primary, $key, @values) = @_;

    $this->_check_primary_key;
    $this->with_session(
	sub {
	    # �ɲá����뤫��
	    my $group = $this->find_group_with_primary($primary);

	    if (defined $group) {
		# found.
		return $group->add_array($key, @values);
	    } else {
		# ̵���ä���硢primary_key�������ɲä�������롣
		if ($key eq $this->primary_key) {
		    # primary_key ���ͤ� @values �����פ��뤫�����å���
		    if (Mask::match_array([@values], $primary, 1, $this->{use_re}, 0)) {
			$this->new_group(@values);
			$this->set_modified;
			# added
			return 1;
		    }
		}
	    }
	    # not added
	    return 0;
	});
}

sub del_array {
    my ($this, $group, $key, @values) = @_;

    $utils->do_with_ensure(
	sub {
	    $group->del_array($key, @values);
	},
	sub {
	    if ($key eq $this->primary_key) {
		$this->queue_cleanup;
	    }
	});
}

sub del_array_with_primary {
    my ($this, $primary, $key, @values) = @_;

    $this->_check_primary_key;
    $this->with_session(
	sub {
	    # ��������뤫��
	    my $group = $this->find_group_with_primary($primary);

	    if (defined $group) {
		return $group->del_value($key, @values);
	    }
	    # not deleted
	    return 0;
	});
}

*add_value = \&add_array;
*add_value_with_primary = \&add_array_with_primary;
*del_value = \&del_array;
*del_value_with_primary = \&del_array_with_primary;

sub _cleanup {
    # primary_key����Ĥ�ʤ������ꥢ���������롣
    my $this = shift;
    my $force = shift || 0;

    if (defined $this->primary_key) {
	if ($this->cleanup_queued || $force) {
	    @{$this->{database}} = grep {
		my $primary = $_->{$this->primary_key};
		defined $primary && @$primary > 0;
	    } @{$this->{database}};
	    $this->set_modified;
	    $this->dequeue_cleanup;
	}
    }
}

sub _after_session_start {
    my $this = shift;
    $this->_checkupdate;
}

sub _before_session_finish {
    my $this = shift;
    $this->_cleanup;
    $this->_synchronize;
}

# group misc functions
sub dup_group {
    # ���롼�פ�ʣ����Ԥ��ޤ���

    my ($group) = @_;
    return undef unless defined($group);

    return $group->clone;
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
    } keys(%$group);

    return $new_group;
}

sub get_value_random {
    my ($group, $key) = @_;

    return $group->get_value_random($key);
}

sub get_value {
    my ($group, $key) = @_;

    return $group->get_value($key);
}

sub get_array {
    my ($group, $key) = @_;

    return $group->get_array($key);
}

# replace support functions
sub replace_with_callbacks {
    # �ޥ�����ִ���Ԥʤ���%optional���ִ����ɲä��륭�����ͤ��Ȥߤǡ���ά�ġ�
    # $callbacks��group/optional���ִ��Ǥ��ʤ��ä��ݤ˸ƤӽФ���륳����Хå��ؿ��Υ�ե���󥹡�
    # optional���ͤ�SCALAR�Ǥ�ARRAY<SCALAR>�Ǥ��ɤ���
    my ($this,$primary,$str,$callbacks,%optional) = @_;
    my $main_table = $this->find_group_with_primary($primary) || {};
    return Tools::HashTools::replace_recursive($str,[$main_table,\%optional],$callbacks);
}

1;
