# -----------------------------------------------------------------------------
# $Id: ChannelInfo.pm,v 1.13 2003/09/26 12:07:13 topia Exp $
# -----------------------------------------------------------------------------
# �����ͥ������ݻ�
# -----------------------------------------------------------------------------
package ChannelInfo;
use strict;
use warnings;
use Carp;
use PersonInChannel;
use Multicast;
our $AUTOLOAD;

sub new {
    # name�˻�̾�ޤ��դ��ʤ��褦����ա�#channel@ircnet��NG��
    my ($class,$name,$network_name) = @_;
    my $obj = {
	name => $name,
	network_name => $network_name,
	topic => '',
	topic_who => undef,
	topic_time => undef,
	names => undef, # hash; nick => PersonInChannel
	switches => undef, # hash; a��s�ʤɤΥ����ͥ�⡼�ɡ�������a��s�ǡ��ͤϾ��1��
	parameters => undef, # hash; l��k�ʤɤΥ����ͥ�⡼�ɡ�
	banlist => undef, # array; +b�ꥹ�ȡ��Τ�ʤ���ж���
	exceptionlist => undef, # array; +e�ꥹ�ȡ��Τ�ʤ���ж���
	invitelist => undef, # array; +I�ꥹ�ȡ��Τ�ʤ���ж���
	remarks => undef, # hash; Tiarra������Ū�˻��Ѥ������͡�
    };

    unless (defined $name) {
	croak "ChannelInfo->new requires name parameter.\n";
    }

    bless $obj,$class;
}

sub equals {
    # �����ͥ�̾�ȥ����С���Ʊ���ʤ鿿��
    my ($this,$ch) = @_;
    defined $ch && $this->name eq $ch->name &&
	$this->network_name eq $ch->network_name;
}

sub fullname {
    # �����С�̾���դ����֤���
    my $this = shift;
    scalar Multicast::attach($this->name,$this->network_name);
}

my $types = {
    topic => 'scalar',
    topic_who => 'scalar',
    topic_time => 'scalar',
    names => 'hash',
    switches => 'hash',
    parameters => 'hash',
    banlist => 'array',
    exceptionlist => 'array',
    invitelist => 'array',
    remarks => 'hash',
};
sub remarks;
*remark = \&remarks; # remark��remarks�Υ����ꥢ����
sub AUTOLOAD {
    my ($this,@args) = @_;
    (my $key = $AUTOLOAD) =~ s/^.+?:://g;

    if ($key eq 'DESTROY') {
	return;
    }

    if ($key eq 'name' || $key eq 'network_name') {
	return $this->{$key};
    }

    my $type = $types->{$key};
    if (!defined($type)) {
	croak "ChannelInfo doesn't have the parameter $key\n";
    }

    if ($type eq 'scalar') {
	# $info->topic;
	# $info->topic('NEW-TOPIC');
	if (defined $args[0]) {
	    $this->{$key} = $args[0];
	}
	return $this->{$key};
    }
    elsif ($type eq 'hash') {
	# $info->names;
	# $info->names('saitama');
	# $info->names('saitama',$person);
	# $info->names('saitama',undef,'delete');
	# $info->names(undef,undef,'clear');
	# $info->names(undef,undef,'size');
	# $info->names(undef,undef,'keys');
	# $info->names(undef,undef,'values');
	my $hash = $this->{$key};

	if (!defined $args[0] && !defined $args[2]) {
	    # HASH*���֤���
	    $this->{$key} = $hash = {} if !$hash;
	    return $hash;
	}

	if (defined $args[1]) {
	    $this->{$key} = $hash = {} if !$hash;
	    $hash->{$args[0]} = $args[1];
	}
	if (defined $args[2]) {
	    if ($args[2] eq 'delete') {
		delete $hash->{$args[0]} if $hash;
	    }
	    elsif ($args[2] eq 'clear') {
		$this->{$key} = undef;
	    }
	    elsif ($args[2] eq 'size') {
		return $hash ? scalar(keys %$hash) : 0;
	    }
	    elsif ($args[2] eq 'keys') {
		return $hash ? keys %$hash : ();
	    }
	    elsif ($args[2] eq 'values') {
		return $hash ? values %$hash : ();
	    }
	    else {
		croak '[hash]->([key],[value],'.$args[2].") is invalid\n";
	    }
	}
	return ($hash and $args[0]) ? $hash->{$args[0]} : undef;
    }
    elsif ($type eq 'array') {
	# $info->banlist;
	# $info->banlist('set','a!*@*','b!*@*','c!*@*');
	# $info->banlist('add','*!*@*.hoge.net');
	# $info->banlist('delete','*!*@*.hoge.net');
	my $array = $this->{$key};
	if (@args == 0) {
	    # ARRAY*���֤���
	    $this->{$key} = $array = [] if !$array;
	    return $array;
	}

	if ($args[0] eq 'set') {
	    $this->{$key} = $array = [] if !$array;
	    @$array = @args[1 .. $#args];
	}
	elsif ($args[0] eq 'add') {
	    croak "'add' requires a value to add\n" unless defined $args[1];
	    $this->{$key} = $array = [] if !$array;
	    push @$array,$args[1];
	}
	elsif ($args[0] eq 'delete') {
	    croak "'delete' requires a value to remove\n" unless defined $args[1];
	    if ($array) {
		for (my $i = 0; $i < @$array; $i++) {
		    if ($array->[$i] eq $args[1]) {
			splice @$array,$i,1;
			$i--;
		    }
		}
	    }
	}
	else {
	    croak "invalid command '".$args[0]."'\n";
	}
	return $this;
    }
}

1;
