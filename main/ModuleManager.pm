# -----------------------------------------------------------------------------
# $Id: ModuleManager.pm,v 1.11 2003/09/23 14:00:26 admin Exp $
# -----------------------------------------------------------------------------
# ���Υ��饹�����Ƥ�Tiarra�⥸�塼���������ޤ���
# �⥸�塼�����ɤ�������ɤ����˴�����ΤϤ��Υ��饹�Ǥ���
# -----------------------------------------------------------------------------
package ModuleManager;
use strict;
use warnings;
use UNIVERSAL;
use Configuration;
use RunLoop;
our $_shared_instance;

*shared = \&shared_manager;
sub shared_manager {
    unless (defined $_shared_instance) {
	$_shared_instance = _new ModuleManager;
	$_shared_instance->update_modules;
    }
    $_shared_instance;
}

sub _new {
    my $class = shift;
    my $obj = {
	modules => [], # ���߻��Ѥ���Ƥ������ƤΥ⥸�塼��
	mod_configs => {}, # ���߻��Ѥ���Ƥ������⥸�塼���Configuration::Block
	mod_timestamps => {}, # ���߻��Ѥ���Ƥ������⥸�塼�뤪��ӥ��֥⥸�塼��ν���use���줿����
	updated_once => 0, # ����update_modules���¹Ԥ��줿�������뤫��
    };
    bless $obj,$class;
}

sub get_modules {
    # �⥸�塼�������ؤλ��Ȥ��֤�����������ѹ����ƤϤʤ�ʤ���
    shift->{modules};
}

sub get {
    my ($this,$modname) = @_;
    foreach (@{$this->{modules}}) {
	return $_ if ref $_ eq $modname;
    }
    undef;
}

sub terminate {
    # Tiarra��λ���˸Ƥֻ���
    my $this = shift;
    foreach (@{$this->{modules}}) {
	eval {
	    $_->destruct;
	}; if ($@) {
	    print "$@\n";
	}
    }
    @{$this->{modules}} = ();
    %{$this->{mod_configs}} = ();
}

sub timestamp {
    my ($this,$module,$timestamp) = @_;
    if (defined $timestamp) {
	$this->{mod_timestamps}->{$module} = $timestamp;
    }
    $this->{mod_timestamps}->{$module};
}

sub update_modules {
    # +�ǻ��ꤵ�줿�⥸�塼��������ɤߡ�modules��ƹ������롣
    # ɬ�פʥ⥸�塼�뤬�ޤ����ɤ���Ƥ��ʤ���Х��ɤ���
    # ��Ϥ�ɬ�פȤ���ʤ��ʤä��⥸�塼�뤬������˴����롣
    # �����ܰʹߡ��Ĥޤ굯ư��ˤ��줬�¹Ԥ��줿����
    # �⥸�塼��Υ��ɤ��˴��˴ؤ����������ˤ��å���������Ϥ��롣
    my $this = shift;
    my $mod_configs = Configuration->shared_conf->get_list_of_modules;
    my ($new,$deleted,$changed,$not_changed) = $this->_check_difference($mod_configs);

    my $show_msg = sub {
	if ($this->{updated_once}) {
	    # ���˰��ٰʾ塢update_modules���¹Ԥ��줿�������롣
	    return sub {
		RunLoop->shared_loop
		    ->notify_msg( $_[0] );
	    };
	}
	else {
	    # ��ư���ʤΤǲ��⤷�ʤ�̵̾�ؿ������ꡣ
	    return sub {};
	}
    }->();

    # $this->{modules}��⥸�塼��̾ => Module�Υơ��֥�ˡ�
    my %loaded_mods = map {
	ref($_) => $_;
    } @{$this->{modules}};

    # �������ɲä��줿�⥸�塼�롢���ľ���줿�⥸�塼�롢�ѹ�����ʤ��ä��⥸�塼���
    # �⥸�塼��̾ => Module�η����ǥơ��֥�ˤ��롣
    my %new_mods = map {
	# �������ɲä��줿�⥸�塼�롣
	$show_msg->("Module ".$_->block_name." will be loaded newly.");	
	$_->block_name => $this->_load($_);
    } @$new;
    my %rebuilt_mods = map {
	# ���ľ���⥸�塼�롣
	# %loaded_mods�˸Ť�ʪ�����äƤ���Τǡ��˴����롣
	$show_msg->("Configuration of the module ".$_->block_name." has been changed. It will be restarted.");
	$loaded_mods{$_->block_name}->destruct;
	$_->block_name => $this->_load($_);
    } @$changed;
    my %not_changed_mods = map {
	# �����ѹ�����ʤ��ä��⥸�塼�롣
	# %loaded_mods�˼�ʪ�����äƤ��롣
	$_->block_name => $loaded_mods{$_->block_name};
    } @$not_changed;

    my $deleted_any = @$deleted > 0;
    foreach (@$deleted) {
	# ������줿�⥸�塼�롣
	# %loaded_mods�˸Ť�ʪ�����äƤ���Τ��˴������塢������ɤ��롣
	$show_msg->("Module ".$_->block_name." will be unloaded.");
	eval {
	    $loaded_mods{$_->block_name}->destruct;
	}; if ($@) {
	    $show_msg->($@);
	}
	$this->_unload($_);
    }

    # $mod_configs�˽񤫤줿����˽�����$this->{modules}��ƹ�����
    # â�����ɤ˼��Ԥ����⥸�塼���null�ˤʤäƤ���Τǽ�����
    @{$this->{modules}} = grep { defined $_ } map {	
	my $modname = $_->block_name;
	$not_changed_mods{$modname} || $rebuilt_mods{$modname} || $new_mods{$modname};
    } @$mod_configs;

    if ($deleted_any > 0) {
	# ������ĤǤ⥢����ɤ����⥸�塼�뤬����С����Ỳ�Ȥ���ʤ��ʤä��⥸�塼�뤬
	# ���뤫�ɤ�����Ĵ�١���ĤǤ⤢���mark and sweep��¹ԡ�
	my $fixed = $this->fix_USED_fields;
	if ($fixed) {
	    $this->gc;
	}
    }

    $this->{updated_once} = 1;
    $this;
}

sub _check_difference {
    # �����_check_difference�¹Ի����顢���ߤΥ⥸�塼�����꤬�ɤΤ褦���Ѳ���������
    # ����ͤ�(<�����ɲ�>,<���>,<�ѹ�>,<̵�ѹ�>) ���줾��ARRAY<Configuration::Block>�ؤλ��ȤǤ��롣
    # �����ɲä��ѹ��Ϥ��줾�쿷����Configuration::Block��������ˤ�(��������Τ�̵���Τ�)�Ť�Configuration::Block���֤���롣
    my ($this,$mod_configs) = @_;
    # �ޤ��Ͽ������о줷���⥸�塼��ȡ�������ѹ����줿�⥸�塼���õ����
    my @new;
    my @changed;
    my @not_changed;
    foreach my $conf (@$mod_configs) {
	my $old_conf = $this->{mod_configs}->{$conf->block_name};
	if (defined $old_conf) {
	    # ���Υ⥸�塼��ϴ����������Ƥ��뤬���ѹ���ä����ƤϤ��ʤ�����	    
	    if ($old_conf->equals($conf)) {
		# �Ѥ�äƤʤ���
		push @not_changed,$conf;
	    }
	    else {
		# ���Ƥ��Ѥ�ä���
		push @changed,$conf;
	    }
	}
	else {
	    # ���Ƹ���⥸�塼�����
	    push @new,$conf;
	}
    }
    # ������줿�⥸�塼���õ����
    # ��Υ롼�פ�Ż���������뤬�������ɤ�ʬ����ˤ����ʤ롣
    my %names_of_old_modules
	= map { $_ => 1 } keys %{$this->{mod_configs}};
    foreach my $conf (@$mod_configs) {
	delete $names_of_old_modules{$conf->block_name};
    }
    my @deleted = map {
	$this->{mod_configs}->{$_};
    } keys %names_of_old_modules;
    # $this->{mod_configs}�˿������ͤ����ꡣ
    %{$this->{mod_configs}} =
	map { $_->block_name => $_ } @$mod_configs;
    # ��λ
    return (\@new,\@deleted,\@changed,\@not_changed);
}

sub reload_modules_if_modified {
    # �����ɼ��Τ���������Ƥ���⥸�塼�뤬����С�������ö������ɤ��ƥ��ɤ�ľ����
    # ���󥹥��󥹤��������ľ����
    my $this = shift;

    my $show_msg = sub {
	RunLoop->shared_loop->notify_msg($_[0]);
    };

    my $mods_to_be_reloaded = {}; # �⥸�塼��̾ => 1
    my $check = sub {
	my ($modname,$timestamp) = @_;
	# ���˹������줿��ΤȤ��ƥޡ�������Ƥ����ȴ���롣
	return if $mods_to_be_reloaded->{$modname};

	(my $mod_filename = $modname) =~ s|::|/|g;
	my $mod_fpath = $INC{$mod_filename.'.pm'};
	return if (!defined($mod_fpath) || !-f $mod_fpath);
	if ((stat($mod_fpath))[9] > $timestamp) {
	    # ��������Ƥ��롣���ʤ��Ȥ⤳�Υ⥸�塼��ϥ���ɤ���롣
	    $mods_to_be_reloaded->{$modname} = 1;
	    $show_msg->("$modname has been modified. It will be reloaded.");

	    my $trace;
	    $trace = sub {
		my $modname = shift;
		# ���Υ⥸�塼���%USED���������Ƥ��뤫��
		my $USED = eval qq{ \\\%${modname}::USED };
		if (defined $USED) {
		    # USED�����Ƥ����Ǥ��Ф��Ƶ�Ū�˥ޡ������դ��롣
		    foreach my $used_elem (keys %$USED) {
			$show_msg->("$used_elem will be reloaded because of modification of $modname");
			$trace->($used_elem);
		    }
		}
	    };

	    $trace->($modname);
	}
    };

    while (my ($modname,$timestamp) = each %{$this->{mod_timestamps}}) {
	$check->($modname,$timestamp);
    }

    # ��ĤǤ�ޡ������줿�⥸�塼�뤬����С�$this->{modules}��β����
    # ��Ū�Υ⥸�塼�뤬�ߤ�Τ���Ĵ�٤뤿��ˡ��⥸�塼��̾ => ���֤Υơ��֥���롣
    if (keys(%$mods_to_be_reloaded) > 0) {
	my $mod2index = {};
	for (my $i = 0; $i < @{$this->{modules}}; $i++) {
	    $mod2index->{ref $this->{modules}->[$i]} = $i;
	}

	# �ޡ������줿�⥸�塼������ɤ��뤬�����줬$mod2index����Ͽ����Ƥ�����
	# ���󥹥��󥹤���ľ����
	foreach my $modname (keys %$mods_to_be_reloaded) {
	    my $idx = $mod2index->{$modname};
	    if (defined $idx) {
		eval {
		    $this->{modules}->[$idx]->destruct;
		}; if ($@) {
		    $show_msg->($@);
		}

		my $conf_block = $this->{mod_configs}->{$modname};
		$this->_unload($conf_block);
		$this->{modules}->[$idx] = $this->_load($conf_block); # ���Ԥ����undef�����롣
	    }
	    else {
		# ������ɸ塢use��
		# ���λ���%USED����¸���롣@USE����¸���ʤ���
		my %USED = eval qq{ \%${modname}::USED };
		$this->_unload($modname);
		eval qq{
		    use $modname;
		}; if ($@) {
		    $show_msg->($@);
		}
		eval qq{
                    \%${modname}::USED = \%USED;
                };
	    }
	}

	# ���ƤΥ⥸�塼���%USED��Ĵ�٤ơ�����%USED���ؤ��Ƥ���⥸�塼�뤬
	# �����ˤ��Υ⥸�塼��򻲾Ȥ��Ƥ���Τ��ɤ���������å���
	# �⥸�塼��ι����Ǻ��Ỳ�Ȥ��ʤ��ʤäƤ���С�%USED���������롣
	# ���Τ褦�ʻ���������Τϥ���ɻ���%USED����¸���뤿��Ǥ��롣
	my $fixed = $this->fix_USED_fields;

	# %USED���������������դ��ä��顢��Ϥ�ɬ�פȤ���ʤ��ʤä�
	# �⥸�塼�뤬���뤫���Τ�ʤ���gc��¹ԡ�
	if ($fixed) {
	    $this->gc;
	}

	# $this->{modules}�ˤ�undef�����Ǥ����äƤ��뤫���Τ�ʤ��Τǡ����Τ褦�����ǤϽ������롣
	@{$this->{modules}} = grep {
	    defined $_;
	} @{$this->{modules}};
    }
}

sub _load {
    # �⥸�塼���use���ƥ��󥹥��󥹤����������֤���
    # ���Ԥ�����undef���֤���
    my ($this,$mod_conf) = @_;
    my $mod_name = $mod_conf->block_name;

    # use
    eval qq {
	    use $mod_name;
    }; if ($@) {
	RunLoop->shared_loop->notify_error(
	    "Couldn't load module $mod_name because of exception.\n$@");
	return undef;
    }

    # �⥸�塼��̾��ե�����̾���Ѵ�����%INC�򸡺���
    # module/�ǻϤޤäƤ��ʤ���Х��顼��
    #(my $mod_filename = $mod_name) =~ s|::|/|g;
    #my $filepath = $INC{$mod_filename.'.pm'};
    #if ($filepath !~ m|^module/|) {
    #  RunLoop->shared_loop->notify_error(
    #      "Class $mod_name exists outside the module directory.\n$filepath\n");
    #  next;
    #}

    # ���Υ⥸�塼���������Module�Υ��֥��饹����
    # ���Τ�UNIVERSAL::isa�ϱ����դ���������ΤǼ��Ϥ�@ISA��򸡺����롣
    # 5.6.0 for darwin�Ǥϥ⥸�塼������ɤ���ȱ����դ���
    my $is_inherit_ok = sub {
	return 1 if UNIVERSAL::isa($mod_name,'Module');
	my @isa = eval qq{ \@${mod_name}::ISA };
	foreach (@isa) {
	    if ($_ eq 'Module') {
		::printmsg('UNIVERSAL::isa tell a lie...');
		return 1;
	    }
	}
	undef;
    };
    unless ($is_inherit_ok->()) {
	RunLoop->shared_loop->notify_error(
	    "Class $mod_name doesn't inherit class Module.");
	return undef;
    }

    # ���󥹥�������
    my $mod;
    eval {
	$mod = new $mod_name;
    }; if ($@) {
	RunLoop->shared_loop->notify_error(
	    "Couldn't instantiate module $mod_name because of exception.\n$@");
	return undef;
    }

    # ���Υ��󥹥��󥹤�������$mod_name���Τ�Τ���
    if (ref($mod) ne $mod_name) {
	RunLoop->shared_loop->notify_error(
	    "A thing ".$mod_name."->new returned was not a instance of $mod_name.");
	return undef;
    }

    # timestamp����Ͽ
    $this->timestamp($mod_name,time);

    return $mod;
}

sub _unload {
    # ���ꤵ�줿�⥸�塼��������롣
    # �⥸�塼��̾�������Configuration::Block���Ϥ��Ƥ��ɤ���
    my ($this,$modname) = @_;
    $modname = $modname->block_name if UNIVERSAL::isa($modname,'Configuration::Block');

    # ���Υ⥸�塼���use�����õ�
    delete $this->{mod_timestamps}->{$modname};

    # ����ܥ�ơ��֥�������Ƥ��ޤ����ѿ��䥵�֥롼����˥�����������ʤ��ʤ롣
    # ¿ʬ����ǥ��꤬��������������
    if ($] < 5.008) {
	# NG��v5.6.0 built for darwin�Ǥ�������bus error������롣
	# ����˥���ܥ�ơ��֥�������ƤΥ���ܥ��undef���롣
	# ����ܥ�ơ��֥���ʬ�Υ���ϥ꡼�����뤬��������̵����
	no strict;
	local(*stab) = eval qq{\*${modname}::};
	while (($key,$val) = each(%stab)) {
	    local(*entry) = $val;
	    if (defined $entry) {
		undef $entry;
	    }
	    if (defined @entry) {
		undef @entry;
	    }
	    if (defined &entry) {
		undef &entry;
	    }
	    if ($key ne "${modname}::" && defined %entry) {
		undef %entry;
	    }
	}
    } else {
	# v5.8.0 built for i386-netbsd-multi-64int�ǤϤ����ȤǤ���褦����
	eval 'undef %'.$modname.'::;';
    }

    # %INC�������
    (my $mod_filename = $modname) =~ s|::|/|g;
    delete $INC{$mod_filename.'.pm'};
}

sub fix_USED_fields {
    my $this = shift;
    my $result;
    foreach my $modname (keys %{$this->{mod_timestamps}}) {
	my $USED = eval qq{ \\\%${modname}::USED };
	if (defined $USED) {
	    my @mods_refer_me = keys %$USED;
	    foreach my $mod_refs_me (@mods_refer_me) {
		# ���Υ⥸�塼���@USE�ˤ�������$modname�����äƤ��뤫��
		my $USE = eval qq{ \\\@${mod_refs_me}::USE };
		my $refers_actually = sub {
		    if (defined $USE) {
			foreach (@$USE) {
			    if ($_ eq $modname) {
				return 1;
			    }
			}
		    }
		    undef;
		}->();
		unless ($refers_actually) {
		    # �ºݤˤϻ��Ȥ���Ƥ��ʤ��ä���
		    delete $USED->{$mod_refs_me};
		    $result = 1;
		}
	    }
	}
    }
    $result;
}

sub gc {
    # $this->{modules}������ã��ǽ�Ǥʤ����֥⥸�塼������ƥ�����ɤ��롣
    my $this = shift;
    my %all_mods = %{$this->{mod_timestamps}}; # ���ԡ�����
    # %all_mods�����Ǥ��ͤ����ˤʤäƤ�����ʬ�����ޡ������줿�Ľꡣ

    my $trace;
    $trace = sub {
	my $modname = shift;
	# ���˥ޡ�������Ƥ��뤫���⤷���ϥ⥸�塼�뤬¸�ߤ��ʤ����ȴ���롣
	my $val = $all_mods{$modname};
	if (!defined($val) || $val eq '') {
	    return;
	}
	else {
	    # ���Υ⥸�塼���ޡ�������
	    $all_mods{$modname} = '';
	    # ���Υ⥸�塼���@USE���������Ƥ����顢
	    # �������ƤΥ⥸�塼��ˤĤ��ƺƵ�Ū�˥ȥ졼����
	    my $USE = eval qq{\\\@${modname}::USE};
	    if (defined $USE) {
		foreach (@$USE) {
		    $trace->($_);
		}
	    }
	}
    };
    
    for my $mod (@{$this->{modules}}) {
	my $modname = ref $mod;
	$trace->($modname);
    }
    
    # �ޡ�������ʤ��ä����֥⥸�塼�����ã�Բ�ǽ�ʤΤǥ�����ɤ��롣
    my $runloop = RunLoop->shared_loop;
    while (my ($key,$value) = each %all_mods) {
	if ($value ne '') {
	    eval qq{
		\&${key}::destruct();
	    };
	    
	    $runloop->notify_msg(
		"Submodule $key is no longer required. It will be unloaded.");
	    $this->_unload($key);
	}
    }
}

1;
