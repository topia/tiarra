# -----------------------------------------------------------------------------
# $Id: Hook.pm,v 1.1 2003/08/12 01:45:35 admin Exp $
# -----------------------------------------------------------------------------
# Hook: あらゆるフックのベースクラス
# HookTarget: あらゆるフック先のベースクラス
# -----------------------------------------------------------------------------
# Hookの使い方:
#
# パッケージ変数 $HOOK_TARGET_NAME, @HOOK_NAME_CANDIDATES,
# $HOOK_NAME_DEFAULT, $HOOK_TARGET_DEFAULT を定義する
# 各変数の意味は次の通り
#
# $HOOK_TARGET_NAME:
#   このフックをかける先のパッケージ名。
#
# @HOOK_NAME_CANDIDATES:
#   フック名として許される名前の候補。
#
# $HOOK_NAME_DEFAULT:
#   フック名が省略された場合のデフォルト値。
#   これは省略可能で、省略した場合はフック名の候補の個数が
#   2つ以上である場合に限り、フック名の省略が不可能になる。
#
# $HOOK_TARGET_DEFAULT:
#   フックを掛ける対象のオブジェクトが省略された場合のデフォルト値。
#   これは省略可能で、
#
# これらの変数を定義し、Hookを@ISAに入れたパッケージを作る。
# -----------------------------------------------------------------------------
# HookTargetの使い方:
#
# HookTargetを@ISAに入れたクラスを作る。コンストラクタでの配慮は不要。
# $obj->call_hooks($hook_name)で、インストールされた全てのフックを呼ぶ。
#
# 現在の実装では、HookTargetはオブジェクトをハッシュで持つクラスでのみ使用可能。
# また、`installed-hooks'と云うキーを勝手に使う。
# -----------------------------------------------------------------------------
package Hook;
use strict;
use warnings;
use Carp;
use UNIVERSAL;

sub new {
    my ($class, $code) = @_;
    my $this = {
	target => undef,
	target_package_name => undef,
	hook_name => undef,

	code => $code,
    };

    if (!defined $code) {
	croak $class."->new, Arg[0] was undef.\n";
    }
    elsif (ref($code) ne 'CODE') {
	croak $class."->new, Arg[0] was bad type.\n";
    }

    do {
	no strict;
	no warnings;
	
	local *symtable = eval "\*${class}::";
	if (defined ${$symtable{HOOK_TARGET_NAME}}) {
	    $this->{target_package_name} = ${$symtable{HOOK_TARGET_NAME}};
	}
	else {
	    croak "${class}->new, \$${class}::HOOK_TARGET_NAME undefined.\n";
	}

	if (@{$symtable{HOOK_NAME_CANDIDATES}} == 0) {
	    croak "${class}->new, \@${class}::HOOK_NAME_CANDIDATES undefined.\n";
	}
    };

    bless $this, $class;
}

sub install {
    my ($this, $hook_name, $target) = @_;

    if (defined $this->{target}) {
	croak ref($this)."->install, this hook is already installed.\n";
    }

    do {
	no strict;
	
	local *symtable = eval "\*${\ref($this)}::";
	if (!defined $hook_name) {
	    # @HOOK_NAME_CANDIDATESの個数は1つか？
	    # それとも$HOOK_NAME_DEFAULTは定義されているか？
	    if (@{$symtable{HOOK_NAME_CANDIDATES}} == 1) {
		$hook_name = $symtable{HOOK_NAME_CANDIDATES}->[0]; 
	    }
	    elsif (defined ${$symtable{HOOK_NAME_DEFAULT}}) {
		$hook_name = ${$symtable{HOOK_NAME_DEFAULT}};
	    }
	    else {
		croak ref($this)."->install, you can't omit the hook name.\n";
	    }
	}
	
	# $hook_nameは本当にフック名として許されているか？
	if (!{map {$_ => 1} @{$symtable{HOOK_NAME_CANDIDATES}}}->{$hook_name}) {
	    croak ref($this)."->install, hook `$hook_name' is not available.\n";
	}

	if (!defined $target) {
	    # $HOOK_TARGET_DEFAULTは定義されているか？
	    if (defined ${$symtable{HOOK_TARGET_DEFAULT}}) {
		$target = ${$symtable{HOOK_TARGET_DEFAULT}};
	    }
	    else {
		croak ref($this)."->install, you can't omit the hook target.\n";
	    }
	}
    };

    # $targetは本当にHookTargetを継承したオブジェクトか？
    if (!UNIVERSAL::isa($target, 'HookTarget')) {
	croak ref($this)."->install, target is not a subclass of HookTarget: ".
	    ref($target)."\n";
    }

    # $targetは本当に$HOOK_TARGET_NAMEのオブジェクトか？
    if (!UNIVERSAL::isa($target, $this->{target_package_name})) {
	croak ref($this)."->install, target is not a subclass of $this->{target_package_name}: ".
	    ref($target)."\n";
    }

    $this->{target} = $target;
    $this->{hook_name} = $hook_name;
    $target->install_hook($hook_name, $this);

    $this;
}

sub uninstall {
    my $this = shift;

    $this->{target}->uninstall_hook($this->{hook_name}, $this);
    $this->{target} = undef;
    $this->{hook_name} = undef;

    $this;
}

sub call {
    my $this = shift;

    my ($caller_pkg) = caller(2);
    if ($caller_pkg->isa(ref $this->{target})) {
	$this->{code}->($this);
    }
    else {
	croak "Only ${\ref($this->{target})} can call ${\ref($this)}->call\n";
    }
}

# -----------------------------------------------------------------------------
package HookTarget;

sub _get_hooks_hash {
    my $this = shift;
    my $ih = $this->{'installed-hooks'};
    if (defined $ih) {
	$ih;
    }
    else {
	$this->{'installed-hooks'} = {};
    }
}

sub _get_hooks_array {
    my ($this, $hook_name) = @_;
    my $installed_hooks = $this->_get_hooks_hash;
    my $ar = $installed_hooks->{$hook_name};
    if (defined $ar) {
	$ar;
    }
    else {
	$installed_hooks->{$hook_name} = [];
    }
}

sub install_hook {
    my ($this, $hook_name, $hook) = @_;
    my $array = $this->_get_hooks_array($hook_name);

    push @$array, $hook;
    $this;
}

sub uninstall_hook {
    my ($this, $hook_name, $hook) = @_;
    my $array = $this->_get_hooks_array($hook_name);

    @$array = grep {
	$_ != $hook;
    } @$array;
    $this;
}

sub call_hooks {
    my ($this, $hook_name) = @_;
    my $array = $this->_get_hooks_array($hook_name);

    foreach my $hook (@$array) {
	eval {
	    $hook->call;
	}; if ($@) {
	    die ref($this)."->call_hooks, exception occured: $@\n";
	}
    }
}

1;
