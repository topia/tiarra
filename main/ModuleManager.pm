# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# ���Υ��饹�����Ƥ�Tiarra�⥸�塼���������ޤ���
# �⥸�塼�����ɤ�������ɤ����˴�����ΤϤ��Υ��饹�Ǥ���
# -----------------------------------------------------------------------------
package ModuleManager;
use strict;
use Carp;
use warnings;
use UNIVERSAL;
use RunLoop;
use Tiarra::SharedMixin qw(shared shared_manager);
use Tiarra::ShorthandConfMixin;
use Tiarra::Utils;
our $_shared_instance;
utils->define_attr_getter(1, [qw(_runloop runloop)]);

sub _new {
    shift->new(shift || RunLoop->shared);
}

sub new {
    my ($class, $runloop) = @_;
    croak 'runloop is not specified!' unless defined $runloop;
    my $obj = {
	runloop => $runloop,
	modules => [], # ���߻��Ѥ���Ƥ������ƤΥ⥸�塼��
	using_modules_cache => undef, # �֥�å��ꥹ�Ȥ���������ƤΥ⥸�塼��Υ���å��塣
	mod_configs => {}, # ���߻��Ѥ���Ƥ������⥸�塼���Configuration::Block
	mod_timestamps => {}, # ���߻��Ѥ���Ƥ������⥸�塼�뤪��ӥ��֥⥸�塼��ν���use���줿����
	mod_blacklist => {}, # ��������ư��ʤ��ä��⥸�塼�롣
	updated_once => 0, # ����update_modules���¹Ԥ��줿�������뤫��
    };
    bless $obj,$class;
}

sub _initialize {
    my $this = shift;
    $this->update_modules;
}

sub add_to_blacklist {
    my ($this,$modname) = @_;
    $this->_set_blacklist($modname, 1);
}

sub remove_from_blacklist {
    my ($this,$modname) = @_;
    $this->_set_blacklist($modname, 0);
}

sub check_blacklist {
    my ($class_or_this,$modname) = @_;

    exists $class_or_this->_this->{mod_blacklist}->{$modname};
}

sub _set_blacklist {
    my ($class_or_this,$modname,$add_or_remove) = @_;
    my $this = $class_or_this->_this;

    $this->_clear_module_cache;
    if ($add_or_remove) {
	# modname ��¸�ߥƥ��ȤϤ��ʤ�: && defined $this->get($modname)
	$this->{mod_blacklist}->{$modname} = 1;
    } elsif (!$add_or_remove && exists $this->{mod_blacklist}->{$modname}) {
	delete $this->{mod_blacklist}->{$modname};
    } else {
	return undef;
    }
    return 1;
}

sub _clear_module_cache {
    shift->{using_modules_cache} = undef;
}

sub get_modules {
    # @options(��ά��ǽ):
    #   'even-if-blacklisted': �֥�å��ꥹ������Τ�Τ�ޤ�롣
    # �⥸�塼�������ؤλ��Ȥ��֤�����������ѹ����ƤϤʤ�ʤ���
    my ($class_or_this,@options) = @_;
    my $this = $class_or_this->_this;
    if (defined $options[0] && $options[0] eq 'even-if-blacklisted') {
	return $this->{modules};
    } else {
	if (!defined $this->{using_modules_cache}) {
	    $this->{using_modules_cache} = [grep {
		!$this->check_blacklist(ref($_));
	    } @{$this->{modules}}];
	}
	return $this->{using_modules_cache};
    }
}

sub get {
    my ($class_or_this,$modname) = @_;
    my $this = $class_or_this->_this;
    foreach (@{$this->{modules}}) {
	return $_ if ref $_ eq $modname;
    }
    undef;
}

sub terminate {
    # Tiarra��λ���˸Ƥֻ���
    my $this = shift->_this;
    foreach (@{$this->{modules}}) {
	eval {
	    $_->destruct;
	}; if ($@) {
	    print "$@\n";
	}
	$this->_unload(ref($_));
    }
    foreach (keys %{$this->{mod_timestamps}}) {
	eval {
	    $_->destruct;
	};
	$this->_unload($_);
    }
    @{$this->{modules}} = ();
    $this->_clear_module_cache;
    %{$this->{mod_configs}} = ();
    %{$this->{mod_timestamps}} = ();
}

sub timestamp {
    my ($class_or_this,$module,$timestamp) = @_;
    my $this = $class_or_this->_this;
    if (defined $timestamp) {
	$this->{mod_timestamps}->{$module} = $timestamp;
    }
    $this->{mod_timestamps}->{$module};
}

sub check_timestamp_update {
    my ($class_or_this,$module,$timestamp) = @_;
    my $this = $class_or_this->_this;

    $timestamp = $this->{mod_timestamps}->{$module} if !defined $timestamp;
    if (defined $timestamp) {
	(my $mod_filename = $module) =~ s|::|/|g;
	my $mod_fpath = $INC{$mod_filename.'.pm'};
	return if (!defined($mod_fpath) || !-f $mod_fpath);
	if ((stat($mod_fpath))[9] > $timestamp) {
	    return 1;
	} else {
	    return 0;
	}
    } else {
	return undef;
    }
}

sub update_modules {
    # +�ǻ��ꤵ�줿�⥸�塼��������ɤߡ�modules��ƹ������롣
    # ɬ�פʥ⥸�塼�뤬�ޤ����ɤ���Ƥ��ʤ���Х��ɤ���
    # ��Ϥ�ɬ�פȤ���ʤ��ʤä��⥸�塼�뤬������˴����롣
    # �����ܰʹߡ��Ĥޤ굯ư��ˤ��줬�¹Ԥ��줿����
    # �⥸�塼��Υ��ɤ��˴��˴ؤ����������ˤ��å���������Ϥ��롣
    my $this = shift->_this;
    my $mod_configs = $this->_conf->get_list_of_modules;
    my ($new,$deleted,$changed,$not_changed) = $this->_check_difference($mod_configs);

    my $show_msg = sub {
	if ($this->{updated_once}) {
	    # ���˰��ٰʾ塢update_modules���¹Ԥ��줿�������롣
	    return sub {
		$this->_runloop->notify_msg( $_[0] );
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
	$this->remove_from_blacklist($_->block_name);
	$_->block_name => $this->_load($_);
    } @$new;
    my %rebuilt_mods = map {
	# ���ľ���⥸�塼�롣
	# %loaded_mods�˸Ť�ʪ�����äƤ���Τǡ��˴����롣
	$show_msg->("Configuration of the module ".$_->block_name." has been changed. It will be restarted.");
	$loaded_mods{$_->block_name}->destruct;
	$this->remove_from_blacklist($_->block_name);
	$_->block_name => $this->_load($_);
    } @$changed;
    my %not_changed_mods = map {
	# �����ѹ�����ʤ��ä��⥸�塼�롣
	# %loaded_mods�˼�ʪ�����äƤ��롣
	my $modname = $_->block_name;
	if (!defined $loaded_mods{$modname} &&
		$this->check_timestamp_update($modname)) {
	    # ���ɤǤ��Ƥʤ��ơ��ʤ����ĥ��åץǡ��Ȥ���Ƥ�������ɤ��Ƥߤ롣
	    $show_msg->("$modname has been modified. It will be reloaded.");
	    $this->remove_from_blacklist($modname);
	    $modname => $this->_load($_);
	} else {
	    $modname => $loaded_mods{$modname};
	}
    } @$not_changed;

    # $mod_configs�˽񤫤줿����˽�����$this->{modules}��ƹ�����
    # â�����ɤ˼��Ԥ����⥸�塼���null�ˤʤäƤ���Τǽ�����
    @{$this->{modules}} = grep { defined $_ } map {
	my $modname = $_->block_name;
	$not_changed_mods{$modname} || $rebuilt_mods{$modname} || $new_mods{$modname};
    } @$mod_configs;

    my $deleted_any = @$deleted > 0;
    foreach (@$deleted) {
	# ������줿�⥸�塼�롣
	# %loaded_mods�˸Ť�ʪ�����äƤ�������˴������塢������ɤ��롣
	$show_msg->("Module ".$_->block_name." will be unloaded.");
	if (defined $loaded_mods{$_->block_name}) {
	    eval {
		$loaded_mods{$_->block_name}->destruct;
	    }; if ($@) {
		$this->_runloop->notify_error($@);
	    }
	}
	$this->_unload($_);
    }

    # gc �����˰��٥���å��奯�ꥢ
    $this->_clear_module_cache;

    if ($deleted_any > 0) {
	# ������ĤǤ⥢����ɤ����⥸�塼�뤬����С����Ỳ�Ȥ���ʤ��ʤä��⥸�塼�뤬
	# ���뤫�ɤ�����Ĵ�١���ĤǤ⤢���mark and sweep��¹ԡ�
	my $fixed = $this->fix_USED_fields;
	if ($fixed) {
	    $this->gc;
	}
    }

    $this->_clear_module_cache;

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
	$this->_runloop->notify_msg($_[0]);
    };

    my $mods_to_be_reloaded = {}; # �⥸�塼��̾ => 1
    my $check = sub {
	my ($modname,$timestamp) = @_;
	# ���˹������줿��ΤȤ��ƥޡ�������Ƥ����ȴ���롣
	return if $mods_to_be_reloaded->{$modname};

	if ($this->check_timestamp_update($modname, $timestamp)) {
	    # ��������Ƥ��롣���ʤ��Ȥ⤳�Υ⥸�塼��ϥ���ɤ���롣
	    $mods_to_be_reloaded->{$modname} = 1;
	    $show_msg->("$modname has been modified. It will be reloaded.");

	    my $trace;
	    $trace = sub {
		my ($modname, $depth) = @_;
		++$depth;
		no strict 'refs';
		# ���Υ⥸�塼���%USED���������Ƥ��뤫��
		my $USED = \%{$modname.'::USED'};
		if (defined $USED) {
		    # USED�����Ƥ����Ǥ��Ф��Ƶ�Ū�˥ޡ������դ��롣
		    foreach my $used_elem (keys %$USED) {
			if (!defined $mods_to_be_reloaded->{$used_elem} ||
				$mods_to_be_reloaded->{$used_elem} < $depth) {
			    $mods_to_be_reloaded->{$used_elem} = $depth;
			    $show_msg->("$used_elem will be reloaded because of modification of $modname");
			    $trace->($used_elem, $depth);
			}
		    }
		}
	    };

	    $trace->($modname, 1);
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
	foreach my $modname (map { $_->[0] }
				 sort { $a->[1] <=> $b->[1] }
				     map { [$_, $mods_to_be_reloaded->{$_}]; }
					 keys %$mods_to_be_reloaded) {
	    my $idx = $mod2index->{$modname};
	    if (defined $idx) {
		eval {
		    $this->{modules}->[$idx]->destruct;
		}; if ($@) {
		    $this->_runloop->notify_error($@);
		}

		my $conf_block = $this->{mod_configs}->{$modname};
		# message_io_hook ���������Ƥ���⥸�塼�뤬��̤��ݤ��Τ�
		# �Ȥꤢ���� undef �������̵�뤵���롣
		$this->{modules}->[$idx] = undef;
		$this->_unload($conf_block);
		$this->{modules}->[$idx] = $this->_load($conf_block); # ���Ԥ����undef�����롣
		# _unload �ǥ֥�å��ꥹ�Ȥ���ä��뤫������פ��Ȼפ����������
		$this->remove_from_blacklist($modname);
	    }
	    else {
		# ������ɸ塢use��
		no strict 'refs';
		# ���λ���%USED����¸���롣@USE����¸���ʤ���
		my %USED = %{$modname.'::USED'};
		eval {
		    $modname->destruct;
		};
		$this->_unload($modname);
		eval qq{
		    use $modname;
		}; if ($@) {
		    $this->_runloop->notify_error($@);
		}
		%{$modname.'::USED'} = %USED;
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

	$this->_clear_module_cache;
    }
}

sub _load {
    # �⥸�塼���use���ƥ��󥹥��󥹤����������֤���
    # ���Ԥ�����undef���֤���
    my ($this,$mod_conf) = @_;
    my $mod_name = $mod_conf->block_name;

    # use
    utils->do_with_errmsg("module load: $mod_name", sub {
			      eval "use $mod_name;";
			  });
    if ($@) {
	$this->_runloop->notify_error(
	    "Couldn't load module $mod_name because of exception.\n$@");
	return undef;
    }

    # �⥸�塼��̾��ե�����̾���Ѵ�����%INC�򸡺���
    # module/�ǻϤޤäƤ��ʤ���Х��顼��
    #(my $mod_filename = $mod_name) =~ s|::|/|g;
    #my $filepath = $INC{$mod_filename.'.pm'};
    #if ($filepath !~ m|^module/|) {
    #  $this->_runloop->notify_error(
    #      "Class $mod_name exists outside the module directory.\n$filepath\n");
    #  next;
    #}

    # ���Υ⥸�塼���������Module�Υ��֥��饹����
    # ���Τ�UNIVERSAL::isa�ϱ����դ���������ΤǼ��Ϥ�@ISA��򸡺����롣
    # 5.6.0 for darwin�Ǥϥ⥸�塼������ɤ���ȱ����դ���
    no strict 'refs';
    my $is_inherit_ok = sub {
	return 1 if UNIVERSAL::isa($mod_name,'Module');
	my @isa = @{$mod_name.'::ISA'};
	foreach (@isa) {
	    if ($_ eq 'Module') {
		::debug_printmsg('UNIVERSAL::isa tell a lie...');
		return 1;
	    }
	}
	undef;
    };
    unless ($is_inherit_ok->()) {
	$this->_runloop->notify_error(
	    "Class $mod_name doesn't inherit class Module.");
	return undef;
    }

    # ���󥹥�������
    my $mod;
    eval {
	$mod = $mod_name->new($this->_runloop);
    }; if ($@) {
	$this->_runloop->notify_error(
	    "Couldn't instantiate module $mod_name because of exception.\n$@");
	return undef;
    }

    # ���Υ��󥹥��󥹤�������$mod_name���Τ�Τ���
    if (ref($mod) ne $mod_name) {
	$this->_runloop->notify_error(
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

    # ���Υ⥸�塼��Υ֥�å��ꥹ�Ȥ�õ
    $this->remove_from_blacklist($modname);

    # ���Υ⥸�塼��Υե�����̾����Ƥ�����
    (my $mod_filename = $modname) =~ s|::|/|g;
    $mod_filename .= '.pm';

    # ����ܥ�ơ��֥�������Ƥ��ޤ����ѿ��䥵�֥롼����˥�����������ʤ��ʤ롣
    use Symbol ();
    # ���֥ѥå�������ä���ư�ϴ����⤷��ʤ��ΤǤȤꤢ��������
    # (%INC �Τ��Ȥ⤢�뤷)
    # �����������֥ѥå����������ʾ�ᥤ��ѥå������ʤ���ư���ݾڤϤɤ��ˤ�ʤ���

    no strict;
    my(%stab) = %{$modname.'::'};
    my %shelter = map {
	if (/::$/ &&
		!/^(SUPER)::$/ && !/^::(ISA|ISA::CACHE)::$/) {
	    ($_, $stab{$_});
	} else {
	    ();
	}
    } keys(%stab);

    Symbol::delete_package($modname);

    # ��Υ���Ƥ�������Τ��᤹��
    %{$modname.'::'} = ( %shelter, %{$modname.'::'} );

    # %INC�������
    delete $INC{$mod_filename};
}

sub fix_USED_fields {
    my $this = shift;
    my $result;
    no strict 'refs';
    foreach my $modname (keys %{$this->{mod_timestamps}}) {
	my $USED = \%{$modname.'::USED'};
	if (defined $USED) {
	    my @mods_refer_me = keys %$USED;
	    foreach my $mod_refs_me (@mods_refer_me) {
		# ���Υ⥸�塼���@USE�ˤ�������$modname�����äƤ��뤫��
		my $USE = \@{$mod_refs_me.'::USE'};
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
    no strict 'refs';
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
	    my $USE = \@{$modname.'::USE'};
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
    while (my ($key,$value) = each %all_mods) {
	if ($value ne '') {
	    eval {
		$key->destruct;
	    };

	    $this->_runloop->notify_msg(
		"Submodule $key is no longer required. It will be unloaded.");
	    $this->_unload($key);
	}
    }
}

1;
