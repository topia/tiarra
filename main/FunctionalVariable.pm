# -----------------------------------------------------------------------------
# $Id: FunctionalVariable.pm,v 1.1 2003/08/12 01:45:35 admin Exp $
# -----------------------------------------------------------------------------
# FunctionalVariable�ϡ�Ϳ����줿Ǥ�դδؿ���ե���󥹤�Ƥ֤褦��
# �ѿ��˽����ؿ���tie�����������ޤ���Tie::Scalar�Ȥΰ㤤�ϡ������ؿ���
# ����ѥ�����ǤϤʤ����������˷�������Ǥ���
# -----------------------------------------------------------------------------
# �Ȥ���:
#
# �����顼�ѿ��˳�����Ƥ���:
# my $foo;
# FunctionalVariable::tie(
#     \$foo,
#     FETCH => sub {
#         # FETCH�Ͼ�ά��ǽ
#         return 500;
#     },
#     STORE => sub {
#         # STORE���ά��ǽ
#         print shift;
#     },
# );
# print "$foo\n"; # "500\n"�����
# $foo = 10;      # "10"�����
# -----------------------------------------------------------------------------
# ����ư��:
#
# FunctionalVariable::tie��¹Ԥ���ȡ������ѿ��ˤ�FunctionalVariable����
# ���֥������Ȥ�tie����롣FunctionalVariable::FETCH����¾�ϡ�tie�¹Ի���
# ���ꤵ�줿�ؿ��˼ºݤν�����Ѿ����롣
# -----------------------------------------------------------------------------
package FunctionalVariable;
use strict;
use warnings;
use Carp;

sub tie {
    # $variable: tie�����ѿ��ؤλ���
    # @functions: �ؿ���
    my ($variable, @functions) = @_;

    # @functions�θ���
    my $functions = eval {
	my $funcs = {@functions};
	while (my ($key, $value) = each %$funcs) {
	    if (ref($value) ne 'CODE') {
		die "FunctionalVariable->tie, Arg[1]{$key} is not a function ref.\n";
	    }
	}
	$funcs;
    }; if ($@) {
	croak $@;
    }

    my $this = {
	variable => $variable,
	type => ref($variable),
	functions => $functions,
    };

    if ($this->{type} eq 'SCALAR') {
	tie $$variable, 'FunctionalVariable', $this;
    }
    elsif ($this->{type} eq '') {
	croak "FunctionalVariable->tie, Arg[0] was not a ref.\n";
    }
    else {
	croak "FunctionalVariable->tie, Arg[0] was bad ref: $this->{type}\n";
    }
}

sub TIESCALAR {
    my ($class, $this) = @_;
    bless $this => $class;
}

sub FETCH {
    my ($this) = @_;
    my $f = $this->{functions}{'FETCH'};
    if (defined $f) {
	$f->();
    }
    else {
	# FETCH���������Ƥ��ʤ��Τʤ顢undef�Ǥ��֤�¾̵����
	undef;
    }
}

sub STORE {
    my ($this, $value) = @_;
    my $f = $this->{functions}{'STORE'};
    if (defined $f) {
	$f->($value);
    }
    # STORE���������Ƥ��ʤ��Τʤ顢���⤷�ʤ���
}

1;
