# -----------------------------------------------------------------------------
# $Id: FunctionalVariable.pm,v 1.1 2003/08/12 01:45:35 admin Exp $
# -----------------------------------------------------------------------------
# FunctionalVariableは、与えられた任意の関数リファレンスを呼ぶように
# 変数に処理関数をtieする事が出来ます。Tie::Scalarとの違いは、処理関数を
# コンパイル時ではなく、生成時に決められる事です。
# -----------------------------------------------------------------------------
# 使い方:
#
# スカラー変数に割り当てる場合:
# my $foo;
# FunctionalVariable::tie(
#     \$foo,
#     FETCH => sub {
#         # FETCHは省略可能
#         return 500;
#     },
#     STORE => sub {
#         # STOREも省略可能
#         print shift;
#     },
# );
# print "$foo\n"; # "500\n"を出力
# $foo = 10;      # "10"を出力
# -----------------------------------------------------------------------------
# 内部動作:
#
# FunctionalVariable::tieを実行すると、その変数にはFunctionalVariable型の
# オブジェクトがtieされる。FunctionalVariable::FETCHその他は、tie実行時に
# 指定された関数に実際の処理を委譲する。
# -----------------------------------------------------------------------------
package FunctionalVariable;
use strict;
use warnings;
use Carp;

sub tie {
    # $variable: tieする変数への参照
    # @functions: 関数群
    my ($variable, @functions) = @_;

    # @functionsの検査
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
	# FETCHが定義されていないのなら、undefでも返す他無い。
	undef;
    }
}

sub STORE {
    my ($this, $value) = @_;
    my $f = $this->{functions}{'STORE'};
    if (defined $f) {
	$f->($value);
    }
    # STOREが定義されていないのなら、何もしない。
}

1;
