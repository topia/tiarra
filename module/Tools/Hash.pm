# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Hash をデータストレージとして便利に使えるようにするクラス。
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
	ref($this)->new(undef,
			eval(Data::Dumper->new([$this->data])
				->Terse(1)->Deepcopy(1)->Purity(1)->Dump));
    } else {
	# shallow copy
	ref($this)->new(undef, {%{$this->data}});
    }
}

sub manipulate_keyname {
    # this method update myself, please clone before.
    my ($this, %opts) = @_;

    $this->with_session(
	sub {
	    my ($new_data) = {};
	    my $new_key;
	    foreach my $key ($this->keys) {
		$new_key = $key;
		$new_key = $opts{prefix} . $new_key if defined $opts{prefix};
		$new_key .= $opts{suffix} if defined $opts{suffix};
		$new_key = $opts{code}->($new_key) if defined $opts{code};
		$new_data->{$new_key} = $this->{$key};
	    }
	    $this->[DATA] = $new_data;
	    $this->set_modified;
	});

    $this;
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

sub with_session {
    my $this = shift;
    if (defined $this->parent) {
	$this->parent->with_session(@_);
    } else {
	shift->();
    }
}

foreach (qw(set_modified queue_cleanup)) {
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
	# 発見. どれか一つ選ぶ。
	my $idx = int(rand() * hex('0xffffffff')) % @$values;
	return $values->[$idx];
    }
    return undef;
}

sub get_value {
    my ($this, $key) = @_;

    my $values = $this->get_array($key);
    if ($values) {
	# 発見.
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
		# 発見
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
    # 成功すれば 1(true) が返る。
    # 不正なキーのため失敗した場合は 0(false) が返る。

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
		    # この項目が空になったら項目自体を削除
		    if (@$data == 0) {
			delete $this->data->{$key};
		    }
		} else {
		    # @values が指定されていない場合は項目削除
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
