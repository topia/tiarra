# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# RunLoop��Ǥ�դΥ����åȤ�ƻ뤹���������뤬��������Ͽ�ΰ٤ˤ��Υ��饹���Ѥ��롣
# -----------------------------------------------------------------------------
# my $esock = ExternalSocket->new(
#     Socket => IO::Socket::INET->new(...), # IO::Socket���Υ��֥�������
#     Read => sub {
#               # �����åȤ��ɤ߹��߲�ǽ�ˤʤä����˸ƤФ�륯�����㡣
#               # ExternalSocket�Υ��֥������ȼ��Ȥ��Ĥ��������˸ƤФ�롣
#               my $sock = shift->sock;
#               ...
#             },
#     Write => sub {
#               # �����åȤ��񤭹��߲�ǽ�ˤʤä����˸ƤФ�륯�����㡣
#               my $sock = shift->sock;
#               ...
#             },
#     WantToWrite => sub {
#               # �����åȤ˽񤭹���ɬ�פ����뤫�ɤ�����RunLoop���Τ�٤˸ƤФ�륯�����㡣
#               # ������Read��Write��Ʊ�������������ͤ��֤��ʤ���Фʤ�ʤ���
#               undef;
#             },
#     )->install;
#
# $esock->uninstall;
# -----------------------------------------------------------------------------
package ExternalSocket;
use strict;
use warnings;
use UNIVERSAL;
use Carp;

use SelfLoader;
1;
__DATA__

sub new {
    my ($class,%args) = @_;
    
    my $this = bless {
	socket => undef,
	read => undef,
	write => undef,
	wanttowrite => undef,
	runloop => undef,
	creator => (caller)[0],
    },$class;

    if (defined $args{Socket}) {
	if (ref $args{Socket} &&
	    UNIVERSAL::isa($args{Socket},'IO::Socket')) {

	    $this->{socket} = $args{Socket};
	}
	else {
	    croak "ExternalSocket->new, Arg{Socket} was illegal reference: ".ref($args{Socket})."\n";
	}
    }
    else {
	croak "ExternalSocket->new, Arg{Socket} not exists\n";
    }

    foreach my $key (qw/Read Write WantToWrite/) {
	if (defined $args{$key}) {
	    if (ref($args{$key}) eq 'CODE') {
		$this->{lc $key} = $args{$key};
	    }
	    else {
		croak "ExternalSocket->new, Arg{$key} was illegal reference: ".ref($args{$key})."\n";
	    }
	}
	else {
	    croak "ExternalSocket->new, Arg{$key} not exists\n";
	}
    }

    $this;
}

sub creator {
    shift->{creator};
}

*socket = \&sock;
sub sock {
    # ����ExternalSocket���ݻ����Ƥ��륽���åȤ��֤���
    shift->{socket};
}

sub install {
    # RunLoop�˥��󥹥ȡ��뤹�롣
    # �������ά�������ϥǥե���Ȥ�RunLoop�˥��󥹥ȡ��뤹�롣
    my ($this,$runloop) = @_;

    if (defined $this->{runloop}) {
	croak "This ExternalSocket has been already installed to RunLoop\n";
    }

    $runloop = RunLoop->shared unless defined $runloop;
    $runloop->install_socket($this);

    $this->{runloop} = $runloop;
    $this;
}

sub uninstall {
    # ���󥹥ȡ��뤷��RunLoop���顢���Υ����åȤ򥢥󥤥󥹥ȡ��뤹�롣
    my $this = shift;

    if (!defined $this->{runloop}) {
	# ���󥹥ȡ��뤵��Ƥ��ʤ���
	croak "This ExternalSocket hasn't been installed yet\n";
    }

    $this->{runloop}->uninstall_socket($this);
    $this->{runloop} = undef;
    $this;
}

sub read {
    # Read��¹Ԥ��롣RunLoop�Τߤ����Υ᥽�åɤ�Ƥ٤롣
    my $this = shift;

    my ($caller_pkg) = caller;
    if (!$caller_pkg->isa('RunLoop')) {
	croak "Only RunLoop may call method read/write/want_to_write of ExternalSocket\n";
    }
    
    $this->{read}->($this);
    $this;
}

sub write {
    # Write��¹Ԥ��롣
    my $this = shift;

    my ($caller_pkg) = caller;
    if (!$caller_pkg->isa('RunLoop')) {
	croak "Only RunLoop may call method read/write/want_to_write of ExternalSocket\n";
    }
    
    $this->{write}->($this);
    $this;
}

sub want_to_write {
    # WantToWrite��¹Ԥ��롣
    my $this = shift;

    my ($caller_pkg) = caller;
    if (!$caller_pkg->isa('RunLoop')) {
	croak "Only RunLoop may call method read/write/want_to_write of ExternalSocket\n";
    }
    
    $this->{wanttowrite}->($this);
}

1;
