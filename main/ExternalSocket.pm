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
    # このExternalSocketが保持しているソケットを返す。
    shift->{socket};
}

sub install {
    # RunLoopにインストールする。
    # 引数を省略した場合はデフォルトのRunLoopにインストールする。
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
    # インストールしたRunLoopから、このソケットをアンインストールする。
    my $this = shift;

    if (!defined $this->{runloop}) {
	# インストールされていない。
	croak "This ExternalSocket hasn't been installed yet\n";
    }

    $this->{runloop}->uninstall_socket($this);
    $this->{runloop} = undef;
    $this;
}

sub read {
    # Readを実行する。RunLoopのみがこのメソッドを呼べる。
    my $this = shift;

    my ($caller_pkg) = caller;
    if (!$caller_pkg->isa('RunLoop')) {
	croak "Only RunLoop may call method read/write/want_to_write of ExternalSocket\n";
    }
    
    $this->{read}->($this);
    $this;
}

sub write {
    # Writeを実行する。
    my $this = shift;

    my ($caller_pkg) = caller;
    if (!$caller_pkg->isa('RunLoop')) {
	croak "Only RunLoop may call method read/write/want_to_write of ExternalSocket\n";
    }
    
    $this->{write}->($this);
    $this;
}

sub want_to_write {
    # WantToWriteを実行する。
    my $this = shift;

    my ($caller_pkg) = caller;
    if (!$caller_pkg->isa('RunLoop')) {
	croak "Only RunLoop may call method read/write/want_to_write of ExternalSocket\n";
    }
    
    $this->{wanttowrite}->($this);
}

1;
