# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Hash ��ǡ������ȥ졼���Ȥ��������˻Ȥ���褦�ˤ��륯�饹��
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tools::Hash;
use strict;
use warnings;
use enum qw(PARENT DATA);
use Tiarra::Utils;
use overload
    '%{}' => sub { shift->data },
    'bool' => sub { %{shift->data} };

utils->define_array_attr_accessor(0, 'parent');
utils->define_array_attr_getter(0, 'data');

sub new {
    my ($class, $parent, $data) = @_;

    my $this = [];
    $this->[PARENT] = $parent;
    $this->[DATA] = utils->get_first_defined($data, {});
    bless $this, $class;
    $this;
}

sub drop_parent	{ shift->parent(undef); }
sub set_parent	{ shift->parent(shift); }
sub keys	{ CORE::keys(%{shift->data}); }
sub values	{ CORE::values(%{shift->data}); }

sub clone {
    my ($this, %args) = @_;
    if ($args{deep}) {
	eval
	    Data::Dumper->new([$this])->Terse(1)->Deepcopy(1)->Purity(1)->Dump;
    } else {
	# shallow copy
	ref($this)->new(undef, {%{$this->data}});
    }
}

sub equals {
    my ($this, $target) = @_;

    $this->with_session(
	sub {
	    $target->with_session(
		sub {
		    map {
			return 0 if $this->$_ != $target->$_;
		    } qw(keys values);
		    my ($key, $value);
		    my ($values, $target_values);
		    while (($key, $values) = each %$this) {
			$target_values = $target->get_array($key);
			return 0 unless defined $target_values;
			return 0 unless @$values != @$target_values;
			$target_values = [@$target_values]; # clone
			foreach $value (sort @$values) {
			    if ($value ne shift(@$target_values)) {
				return 0;
			    }
			}
		    }
		})});
    return 1;
}

foreach (qw(set_modified queue_cleanup with_session)) {
    eval "
    sub $_ \{
	my \$this = shift;
	if (defined \$this->parent) {
	    \$this->parent->$_(\@_);
	}
    }";
}

sub get_value_random {
    my ($this, $key) = @_;

    my $values = $this->get_array($key);
    if ($values) {
	# ȯ��. �ɤ줫������֡�
	my $idx = int(rand() * hex('0xffffffff')) % @$values;
	return $values->[$idx];
    }
    return undef;
}

sub get_value {
    my ($this, $key) = @_;

    my $values = $this->get_array($key);
    if ($values) {
	# ȯ��.
	return $values->[0];
    }
    return undef;
}

sub get_array {
    my ($this, $key) = @_;

    $this->with_session(
	sub {
	    my $value = $this->data->{$key};
	    if (defined $value) {
		# ȯ��
		if (ref($value) eq 'ARRAY') {
		    return $value;
		} else {
		    return [$value];
		}
	    }
	    return undef;
	});
}

sub add_hash {
    my ($this, %hash) = @_;
    my $retval = 1;

    $this->with_session(
	sub {
	    map {
		my $value = $hash{$_};
		if (ref($value) ne 'ARRAY') {
		    $value = [$value];
		}
		$retval &= $this->add_array($_, @$value) ? 1 : 0;
	    } CORE::keys %hash;
	});
    return $retval;
}

sub add_array {
    # ��������� 1(true) ���֤롣
    # �����ʥ����Τ��Ἲ�Ԥ������� 0(false) ���֤롣

    my ($this, $key, @values) = @_;

    return 0 if $key =~ / /;

    $this->with_session(
	sub {
	    my $data = $this->data->{$key};
	    if (!defined $data) {
		$data = [];
		$this->data->{$key} = $data;
	    }
	    push @$data,@values;
	    $this->set_modified;
	});

    return 1;
}

sub del_array {
    my ($this, $key, @values) = @_;

    $this->with_session(
	sub {
	    my $data = $this->data->{$key};
	    if (defined $data) {
		my ($count) = scalar @$data;
		if (@values) {
		    my $item;
		    @$data = grep {
			$item = $_;
			!(utils->get_first_defined(
			    map {
				$item eq $_ ? 1 : undef;
			    } @values))
			} @$data;
		    $count -= scalar(@$data);
		    # ���ι��ܤ����ˤʤä�����ܼ��Τ���
		    if (@$data == 0) {
			delete $this->data->{$key};
		    }
		} else {
		    # @values �����ꤵ��Ƥ��ʤ����Ϲ��ܺ��
		    delete $this->data->{$key};
		}
		$this->set_modified;
		$this->queue_cleanup;
		# deleted
		return $count;
	    }

	    # not deleted
	    return 0;
	});
}

*add_value = \&add_array;
*del_value = \&del_array;
*del_key = \&del_array;

1;
