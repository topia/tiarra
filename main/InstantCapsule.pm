# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# �ե�����ɤȥ᥽�åɤ���ĥ��֥������Ȥ���Ū���������뤿��Υ��饹��
# �������˥᥽�åɤμ��Τ򥯥�������Ϥ��ޤ���
# AUTOLOAD��tie����Ѥ��Ƥ��뤿�ᡢư��®�٤��̾�Υ��饹����٤���ǽ��������ޤ���
#
# my $capsule = InstantCapsule->new(
#    Fields => {
#       # �������Ǥϥϥå��巿���֥������ȤΤ��б���
#       # ���󷿤䥰��ַ��Υ��֥������Ȥ����б��Ǥ���
#	foo => 10,
#	bar => undef,
#	baz => 'string',
#    },
#    Methods => {
#	# �᥽�å�̾new��InstantCapsule��ͽ�󤷤Ƥ��롣
#
#	printfoo => sub {
#	    # �᥽�åɤ��Ϥ����ǽ�ΰ�����InstantCapsule���ȡ�
#	    my $this = shift;
#	    print $this->{foo},"\n";
#	},
#
#	setbar => sub {
#	    # ����ܰʹߤΰ����ϡ����Υ᥽�åɸƤӽФ����Ѥ���줿��Τ����Τޤ��Ϥ���롣
#	    my ($this,$value) = @_;
#	    $this->{bar} = $value;
#	}
#
#	DESTROY => sub {
#	    print "DESTROY called.\n";
#	}
#    });
#
# $capsule->printfoo;
# $capsule->setbar(5);
# undef $capsule; # ������DESTROY���ƤФ�롣
# -----------------------------------------------------------------------------
package InstantCapsule;
use strict;
use warnings;
use Carp;
use UNIVERSAL;
use vars qw($AUTOLOAD);

sub new {
    my ($class,%args) = @_;
    my $this = {
	fields => $args{Fields},
	methods => $args{Methods},
    };

    if (!defined $this->{fields}) {
	croak "InstantCapsule->new, Arg[Fields] not defined.\n";
    }
    elsif (!ref($this->{fields}) || !UNIVERSAL::isa($this->{fields},'HASH')) {
	croak "InstantCapsule->new, Arg[Fields] is bad type.\n";
    }

    if (!defined $this->{methods}) {
	croak "InstantCapsule->new, Arg[Methods] not defined.\n";
    }
    elsif (!ref($this->{methods}) || !UNIVERSAL::isa($this->{methods},'HASH')) {
	croak "InstantCapsule->new, Arg[Methods] is bad type.\n";
    }

    # methods�������å���
    while (my ($name,$code) = each %{$this->{methods}}) {
	if (eval qq{defined \&${class}::${name}}) {
	    croak "InstantCapsule->new, method $name is reserved for InstantCapsule itself.\n";
	}
	if (!ref($code) || ref($code) ne 'CODE') {
	    croak "InstantCapsule->new, method $name is not a valid CODE value.\n";
	}
    }

    my $obj = {};
    tie %$obj,$class,$this; # �������Ƥ����ʤ��ȥե�����ɤ����Ƚ���ʤ���
    bless $obj,$class; # �������Ƥ����ʤ���AUTOLOAD���Ȥ��ʤ���
}

sub TIEHASH {
    my ($class,$tie) = @_;
    bless $tie,$class;
}

sub FETCH {
    my ($this,$key) = @_;
    $this->{fields}->{$key};
}

sub STORE {
    my ($this,$key,$value) = @_;
    $this->{fields}->{$key} = $value;
}

sub DELETE {
    my ($this,$key) = @_;
    delete $this->{fields}->{$key};
}

sub EXISTS {
    my ($this,$key) = @_;
    exists $this->{fields}->{$key};
}

sub CLEAR {
    my $this = shift;
    %{$this->{fields}} = ();
}

sub FIRSTKEY {
    my $this = shift;
    values %{$this->{fields}}; # reset iterator
    each %{$this->{fields}};
}

sub NEXTKEY {
    my $this = shift;
    each %{$this->{fields}};
}

sub AUTOLOAD {
    my ($obj,@args) = @_;
    my $this = tied %$obj;
    (my $method = $AUTOLOAD) =~ s/.+?:://g;

    if (defined $this->{methods}->{$method}) {
	$this->{methods}->{$method}->($obj,@args);
    }
    else {
	# DESTROY������̵���Ƥ⹽��ʤ���
	if ($method ne 'DESTROY') {
	    croak "InstantCapsule->AUTOLOAD, method $method is not defined.\n";
	}
    }
}

1;
