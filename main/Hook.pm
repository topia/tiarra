# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Hook: ������եå��Υ١������饹
# HookTarget: ������եå���Υ١������饹
# -----------------------------------------------------------------------------
# Hook�λȤ���:
#
# �ѥå������ѿ� $HOOK_TARGET_NAME, @HOOK_NAME_CANDIDATES,
# $HOOK_NAME_DEFAULT, $HOOK_TARGET_DEFAULT ���������
# ���ѿ��ΰ�̣�ϼ����̤�
#
# $HOOK_TARGET_NAME:
#   ���Υեå��򤫤�����Υѥå�����̾��
#
# @HOOK_NAME_CANDIDATES:
#   �եå�̾�Ȥ��Ƶ������̾���θ��䡣
#
# $HOOK_NAME_DEFAULT:
#   �եå�̾����ά���줿���Υǥե�����͡�
#   ����Ͼ�ά��ǽ�ǡ���ά�������ϥեå�̾�θ���θĿ���
#   2�İʾ�Ǥ�����˸¤ꡢ�եå�̾�ξ�ά���Բ�ǽ�ˤʤ롣
#
# $HOOK_TARGET_DEFAULT:
#   �եå���ݤ����оݤΥ��֥������Ȥ���ά���줿���Υǥե�����͡�
#   ����Ͼ�ά��ǽ�ǡ���ά��������install���˥������åȤξ�ά������ʤ��ʤ롣
#
# �������ѿ����������Hook��@ISA�����줿�ѥå��������롣
# -----------------------------------------------------------------------------
# HookTarget�λȤ���:
#
# HookTarget��@ISA�����줿���饹���롣���󥹥ȥ饯���Ǥ���θ�����ס�
# $obj->call_hooks($hook_name)�ǡ����󥹥ȡ��뤵�줿���ƤΥեå���Ƥ֡�
# $obj->call_hooks($hook_name, $foo, $bar, $baz)�Τ褦��Ǥ�դθĿ��ΰ�����
# �Ϥ�������ǽ�ǡ����ξ��Ϥ���������Ȥ��ƥեå��ؿ����ƤФ�롣
#
# ���ߤμ����Ǥϡ�HookTarget�ϥ��֥������Ȥ�ϥå���ǻ��ĥ��饹�ǤΤ߻��Ѳ�ǽ��
# �ޤ���`installed-hooks'�ȱ��������򾡼�˻Ȥ���
# -----------------------------------------------------------------------------
package Hook;
use strict;
use warnings;
use Carp;
use UNIVERSAL;
use Tiarra::Utils;

sub new {
    my $class = shift;
    #my ($class, $code) = @_;
    my $name = shift;
    my $code = shift;
    if (!defined $name) {
	croak $class."->new, Arg[0] was undef.\n";
    }
    if (ref($name) eq 'CODE' && !defined($code)) {
	$code = $name;
	$name = utils->simple_caller_formatter($class.' registered');
    }

    my $this = {
	target => undef,
	target_package_name => undef,
	hook_name => undef,

	name => $name,
	code => $code,
    };

    if (ref($code) ne 'CODE') {
	croak $class."->new, Arg[0] was bad type.\n";
    }

    do {
	no strict;
	no warnings;

	local %symtable = %{$class.'::'};
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

	my %symtable = %{ref($this).'::'};
	if (!defined $hook_name) {
	    # @HOOK_NAME_CANDIDATES�θĿ���1�Ĥ���
	    # ����Ȥ�$HOOK_NAME_DEFAULT���������Ƥ��뤫��
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

	# $hook_name�������˥եå�̾�Ȥ��Ƶ�����Ƥ��뤫��
	if (!{map {$_ => 1} @{$symtable{HOOK_NAME_CANDIDATES}}}->{$hook_name}) {
	    croak ref($this)."->install, hook `$hook_name' is not available.\n";
	}

	if (!defined $target) {
	    # $HOOK_TARGET_DEFAULT���������Ƥ��뤫��
	    if (defined ${$symtable{HOOK_TARGET_DEFAULT}}) {
		$target = ${$symtable{HOOK_TARGET_DEFAULT}};
	    }
	    else {
		croak ref($this)."->install, you can't omit the hook target.\n";
	    }
	}
    };

    # $target��������HookTarget��Ѿ��������֥������Ȥ���
    if (!UNIVERSAL::isa($target, 'HookTarget')) {
	croak ref($this)."->install, target is not a subclass of HookTarget: ".
	    ref($target)."\n";
    }

    # $target��������$HOOK_TARGET_NAME�Υ��֥������Ȥ���
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
    my ($this, @args) = @_;

    my ($caller_pkg) = caller(2);
    if ($caller_pkg->isa(ref $this->{target})) {
	utils->do_with_errmsg("Hook: $this->{target}/$this->{hook_name}($this->{name})",
			      sub {
				  $this->{code}->($this, @args);
			      });
    }
    else {
	croak "Only ${\ref($this->{target})} can call ${\ref($this)}->call\n".
	  "$caller_pkg is not allowed to do so.\n";
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
    my ($this, $hook_name, @args) = @_;
    my $array = $this->_get_hooks_array($hook_name);

    foreach my $hook (@$array) {
	eval {
	    $hook->call(@args);
	}; if ($@) {
	    my $msg = ref($this)."->call_hooks, exception occured:\n".
		"  Hook: ".$hook->name."\n".
		    "$@";
	    if (require RunLoop) {
		RunLoop->notify_error($msg);
	    } else {
		die $msg;
	    }
	}
    }
}

1;
