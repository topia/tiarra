# -----------------------------------------------------------------------------
# Iterator::ArrayIterator
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# ���Υ��饹��������ͤ���֤˻ؤ����ƥ졼���Ǥ���
# �����ॢ��������ǽ�Ǥ��������Ͻ���ޤ���
#
# ���󸻤Ȥ��Ƥ����󤽤Τ�Τϡ����Υ��ƥ졼�����ݻ����ޤ���
# �������������ؤλ��Ȥ��ݻ����ޤ���
# �Ĥޤꡢ���Υ��ƥ졼���������˾��󸻤������Ѳ������
# ���ƥ졼���ξ��֤��Ѳ����ޤ���
# -----------------------------------------------------------------------------
package Iterator::ArrayIterator;
use strict;
use warnings;
use base qw(Iterator::RandomAccessIterator);

sub new {
    my ($class,$src_array) = @_;
    my $obj = {
	source => $src_array,
	current_index => 0, # ���줿���ˤϥ��ƥ졼������Ƭ�����Ǥ�ؤ��Ƥ��롣
    };
    bless $obj,$class;
}

sub _increment {
    my $this = shift;
    if (exists $this->{source}->[$this->{current_index}]) {
	# ����Ϥޤ����Ǥ��ĤäƤ��롣���󥯥���Ȥ��Ƥ����Ǥ����뤫���ޤ��Ͻ���undef�ˤʤ롣
	$this->{current_index}++;
    }
    else {
	# ����Ǵ���undef��ؤ��Ƥ��롣����ʾ�ʤ�ʤ���
	die "Iterator::ArrayIterator::increment : operation ++ failed. no more elements in this iterator.\n";
    }
    $this;
}

sub _decrement {
    my $this = shift;
    if ($this->{current_index} > -1) {
	$this->{current_index}--;
    }
    else {
	die "Iterator::ArrayIterator::decrement : operation -- failed. iterator pointed at element indexed -1.\n";
    }
    $this;
}

sub _addition {
    my ($this,$value) = @_;
    my $result = ref($this)->new($this->{source});
    $result->{current_index} = $this->{current_index} + $value;
    return $result;
}

sub _subtract {
    my ($this,$value) = @_;
    return $this->_addition(-$value);
}

sub _add_to {
    my ($this,$value) = @_;
    $this->{current_index} += $value;
    return $this;
}

sub _sub_from {
    my ($this,$value) = @_;
    return $this->_add_to(-$value);
}

sub get {
    $_[0]->{source}->[$_[0]->{current_index}];
}

1;
