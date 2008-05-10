# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# フィールドとメソッドを持つオブジェクトを一時的に生成するためのクラス。
# 生成時にメソッドの実体をクロージャで渡します。
# AUTOLOADやtieを使用しているため、動作速度は通常のクラスより遅い可能性があります。
#
# my $capsule = InstantCapsule->new(
#    Fields => {
#       # 現時点ではハッシュ型オブジェクトのみ対応。
#       # 配列型やグロブ型のオブジェクトは非対応です。
#	foo => 10,
#	bar => undef,
#	baz => 'string',
#    },
#    Methods => {
#	# メソッド名newはInstantCapsuleが予約している。
#
#	printfoo => sub {
#	    # メソッドに渡される最初の引数はInstantCapsule自身。
#	    my $this = shift;
#	    print $this->{foo},"\n";
#	},
#
#	setbar => sub {
#	    # 二つ目以降の引数は、このメソッド呼び出しに用いられたものがそのまま渡される。
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
# undef $capsule; # ここでDESTROYが呼ばれる。
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

    # methods内をチェック。
    while (my ($name,$code) = each %{$this->{methods}}) {
	if (eval qq{defined \&${class}::${name}}) {
	    croak "InstantCapsule->new, method $name is reserved for InstantCapsule itself.\n";
	}
	if (!ref($code) || ref($code) ne 'CODE') {
	    croak "InstantCapsule->new, method $name is not a valid CODE value.\n";
	}
    }

    my $obj = {};
    tie %$obj,$class,$this; # こうしておかないとフィールドが参照出来ない。
    bless $obj,$class; # こうしておかないとAUTOLOADが使えない。
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
	# DESTROYだけは無くても構わない。
	if ($method ne 'DESTROY') {
	    croak "InstantCapsule->AUTOLOAD, method $method is not defined.\n";
	}
    }
}

1;
