# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# RunLoopに登録され、指定された時刻に起動するタイマーです。
# 現在の実装では、精度は秒となっています。
# タイマーの生成に必要なパラメータは、1)起動するサブルーチン、2)起動時刻又は起動までの秒数、
# 3)起動までの秒数を指定した場合は起動後に再びタイマーをRunLoopに乗せるかどうか、です。
#
# 起動するサブルーチンとしては、CODE型の値なら何でも構いません。
# TimerはそのCODEに、引数として自分自身を渡してコールします。
#
# 3秒後にHello, world!と表示する。
# my $timer = Timer->new(
#     After => 3,
#     Code => sub { print "Hello, world!"; }
# )->install;
#
# 3秒毎にHello, world!と表示する。
# my $timer = Timer->new(
#     After => 3, # Intervalでも良い
#     Code => sub { print "Hello, world!"; },
#     Repeat => 1
# )->install;
#
# 3秒後にHello, world!と表示する。
# my $timer = Timer->new(
#     At => time + 3,
#     Code => sub { print "Hello, world!"; }
# )->install;
# -----------------------------------------------------------------------------
package Timer;
use strict;
use warnings;
use Carp;
use RunLoop;
use Tiarra::Utils;
Tiarra::Utils->define_attr_accessor(0, qw(interval name));

sub new {
    my ($class,%args) = @_;
    my $obj = {
	fire_time => undef, # 発動する時刻のエポック秒。
	interval => undef, # repeatする場合は、その間隔。しなければ未定義。
	code => undef, # 走らせるコード
	runloop => undef, # RunLoopに登録されている場合は、そのRunLoop。
	name => sprintf('timer registered at %s line %s',(caller(0))[1,2]),
    };
    bless $obj,$class;

    # AfterとIntervalは同義。
    $args{'After'} = $args{'Interval'} if exists($args{'Interval'});

    # Atで指定するか、AfterまたはIntervalで指定するか、そのどちらかでなければならない。
    if (exists($args{'At'}) && exists($args{'After'})) {
	croak "Timer cannot be made with both parameters At and After (or Interval).\n";
    }

    # Atか、AfterまたはIntervalか、そのどちらか一つは必要。
    if (!exists($args{'At'}) && !exists($args{'After'})) {
	croak "Either parameter At or After (or Interval) is required to make Timer.\n";
    }

    # Codeは常に必要。
    if (!exists($args{'Code'})) {
	croak "Code is always required to make Timer.\n";
    }

    # CodeがCODE型でなければdie。
    if (ref($args{'Code'}) ne 'CODE') {
	croak "Parameter Code was not valid CODE ref.\n";
    }

    $obj->{code} = $args{'Code'};

    if (defined $args{'At'}) {
	# Atで起動時刻が与えられた場合は、Repeatは出来ない。
	if ($args{'Repeat'}) {
	    carp "Warning: It can't repeat that Timer made with At.\n";
	}

	$obj->{fire_time} = $args{'At'};
    }
    elsif (defined $args{'After'}) {
	# Repeatが真であれば、間隔をAfterまたはIntervalで与えられた数値とする。
	if ($args{'Repeat'}) {
	    $obj->{interval} = $args{'After'};
	}
	
	$obj->{fire_time} = time + $args{'After'};
    }

    if (defined $args{'Name'}) {
	$obj->{name} = $args{'Name'};
    }

    $obj;
}

sub time_to_fire {
    my ($this, $time) = @_;
    if ($time) {
	$this->{fire_time} = $time;
    }
    $this->{fire_time};
}

sub install {
    # RunLoopにインストールする。
    # 引数を省略した場合はデフォルトのRunLoopにインストールする。
    my ($this,$runloop) = @_;

    if (defined $this->{runloop}) {
	# 既にインストール済みだった。
	croak "This Timer has been already installed to RunLoop.\n";
    }

    $runloop = RunLoop->shared_loop unless defined $runloop;
    $runloop->install_timer($this);

    $this->{runloop} = $runloop;
    $this;
}

sub uninstall {
    # インストールしたRunLoopから、このタイマーをアンインストールする。
    my $this = shift;

    unless (defined $this->{runloop}) {
	# インストールされていない。
	croak "This Timer hasn't been installed yet\n";
    }

    $this->{runloop}->uninstall_timer($this);
    $this->{runloop} = undef;
    $this;
}

sub execute {
    my $this = shift;
    # Codeを実行し、必要ならリピートする。
    # RunLoopのみがこのメソッドを呼べる。
    my ($package_of_caller,undef,undef) = caller;
    unless ($package_of_caller->isa('RunLoop')) {
	croak "Only RunLoop may call method execute of Timer.\n";
    }

    eval {
	$this->{code}->($this);
    }; if ($@) {
	RunLoop->shared_loop->notify_error(
	    "Exception in Timer($this->{name}).\n".
		"   $@");
    }

    if (defined $this->{interval}) {
	$this->{fire_time} += $this->{interval};
    }
    else {
	$this->uninstall;
    }

    $this;
}

sub reset {
    # interval から fire_time を算出しなおす
    my ($this) = shift;

    if (defined $this->{interval}) {
	$this->{fire_time} = time + $this->{interval};
    } else {
	croak "Only Interval(Repeat) Timer can reset.\n";
    }
    $this;
}

1;
