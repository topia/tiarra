# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# RunLoopは任意のソケットを監視する事が出来るが、その登録の為にこのクラスを用いる。
# -----------------------------------------------------------------------------
# my $esock = ExternalSocket->new(
#     Socket => IO::Socket::INET->new(...), # IO::Socket型のオブジェクト
#     Read => sub {
#               # ソケットが読み込み可能になった時に呼ばれるクロージャ。
#               # ExternalSocketのオブジェクト自身を一つだけ引数に呼ばれる。
#               my $sock = shift->sock;
#               ...
#             },
#     Write => sub {
#               # ソケットが書き込み可能になった時に呼ばれるクロージャ。
#               my $sock = shift->sock;
#               ...
#             },
#     WantToWrite => sub {
#               # ソケットに書き込む必要があるかどうかをRunLoopが知る為に呼ばれるクロージャ。
#               # 引数はReadやWriteと同じだが、真偽値を返さなければならない。
#               undef;
#             },
#     Exception => sub {
#               # ソケットに例外が発生したときに呼ばれるクロージャ。
#               # 省略可能。
#               my $this = shift;
#               ::printmsg($this->errmsg('foo socket error'));
#               $this->disconnect;
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
use Tiarra::Utils;
use Tiarra::Socket;
use base qw(Tiarra::Socket);
utils->define_attr_getter(0, qw(name));

#use SelfLoader;
#SelfLoader->load_stubs;
#1;
#__DATA__

sub socket {
    shift->sock(@_);
}

sub new {
    my ($class,%opts) = @_;

    $class->_increment_caller('external-socket', \%opts);
    my $this = $class->SUPER::new(%opts);
    $this->{read} = undef;
    $this->{write} = undef;
    $this->{wanttowrite} = undef;
    $this->{exception} = undef;
    my $this_func = $class . '->new';

    if (defined $opts{Socket}) {
	if (ref $opts{Socket} &&
		UNIVERSAL::isa($opts{Socket},'IO::Socket')) {
	    $this->attach($opts{Socket});
	}
	else {
	    croak "$this_func, Arg{Socket} was illegal object: ".ref($opts{Socket})."\n";
	}
    }
    else {
	croak "$this_func, Arg{Socket} not exists\n";
    }

    foreach my $key (qw/Read Write WantToWrite Exception/) {
	if (defined $opts{$key}) {
	    if (ref($opts{$key}) eq 'CODE') {
		$this->{lc $key} = $opts{$key};
	    }
	    else {
		croak "$this_func, Arg{$key} was illegal reference: ".ref($opts{$key})."\n";
	    }
	}
	elsif ($key ne 'Exception') {
	    # Exception is optional
	    croak "$this_func, Arg{$key} not exists\n";
	}
    }

    if (defined $opts{Name}) {
	$this->name($opts{Name});
    }

    $this;
}

sub install {
    # RunLoopにインストールする。
    # 引数を省略した場合はデフォルトのRunLoopにインストールする。
    my ($this,$runloop) = @_;

    if ($this->installed) {
	croak "This " . ref($this) .
	    " has been already installed to RunLoop\n";
    }

    $runloop = RunLoop->shared unless defined $runloop;
    $this->{runloop} = $runloop;
    $this->SUPER::install;
}

sub uninstall {
    # インストールしたRunLoopから、このソケットをアンインストールする。
    my $this = shift;

    if (!$this->installed) {
	# インストールされていない。
	croak "This " . ref($this) . " hasn't been installed yet\n";
    }

    $this->SUPER::uninstall;
}

sub __check_caller {
    my $this = shift;
    my $caller_pkg = utils->get_package(1);
    if (!$caller_pkg->isa('RunLoop')) {
	croak "Only RunLoop may call method read/write/want_to_write of " .
	    ref($this) . "\n";
    }
}

sub read {
    # Readを実行する。RunLoopのみがこのメソッドを呼べる。
    my $this = shift;

    $this->__check_caller;
    $this->{read}->($this);
    $this;
}

sub write {
    # Writeを実行する。
    my $this = shift;

    $this->__check_caller;
    $this->{write}->($this);
    $this;
}

sub want_to_write {
    # WantToWriteを実行する。
    my $this = shift;

    $this->__check_caller;
    $this->{wanttowrite}->($this);
}

sub exception {
    # Exceptionを実行する。
    my $this = shift;

    $this->__check_caller;
    $this->{exception}->($this) if defined $this->{exception};
}

1;
