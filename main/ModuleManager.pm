# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# このクラスは全てのTiarraモジュールを管理します。
# モジュールをロードし、リロードし、破棄するのはこのクラスです。
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
	modules => [], # 現在使用されている全てのモジュール
	using_modules_cache => undef, # ブラックリストを除いた全てのモジュールのキャッシュ。
	mod_configs => {}, # 現在使用されている全モジュールのConfiguration::Block
	mod_timestamps => {}, # 現在使用されている全モジュールおよびサブモジュールの初めてuseされた時刻
	mod_blacklist => {}, # 過去に正常動作しなかったモジュール。
	updated_once => 0, # 過去にupdate_modulesが実行された事があるか。
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
	# modname の存在テストはしない: && defined $this->get($modname)
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
    # @options(省略可能):
    #   'even-if-blacklisted': ブラックリスト入りのものを含める。
    # モジュールの配列への参照を返すが、これを変更してはならない！
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
    # Tiarra終了時に呼ぶ事。
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
    # +で指定されたモジュール一覧を読み、modulesを再構成する。
    # 必要なモジュールがまだロードされていなければロードし、
    # もはや必要とされなくなったモジュールがあれば破棄する。
    # 二度目以降、つまり起動後にこれが実行された場合は
    # モジュールのロードや破棄に関して成功時にもメッセージを出力する。
    my $this = shift->_this;
    my $mod_configs = $this->_conf->get_list_of_modules;
    my ($new,$deleted,$changed,$not_changed) = $this->_check_difference($mod_configs);

    my $show_msg = sub {
	if ($this->{updated_once}) {
	    # 過去に一度以上、update_modulesが実行された事がある。
	    return sub {
		$this->_runloop->notify_msg( $_[0] );
	    };
	}
	else {
	    # 起動時なので何もしない無名関数を設定。
	    return sub {};
	}
    }->();

    # $this->{modules}をモジュール名 => Moduleのテーブルに。
    my %loaded_mods = map {
	ref($_) => $_;
    } @{$this->{modules}};

    # 新たに追加されたモジュール、作り直されたモジュール、変更されなかったモジュールを
    # モジュール名 => Moduleの形式でテーブルにする。
    my %new_mods = map {
	# 新たに追加されたモジュール。
	$show_msg->("Module ".$_->block_name." will be loaded newly.");
	$this->remove_from_blacklist($_->block_name);
	$_->block_name => $this->_load($_);
    } @$new;
    my %rebuilt_mods = map {
	# 作り直すモジュール。
	# %loaded_modsに古い物が入っているので、破棄する。
	$show_msg->("Configuration of the module ".$_->block_name." has been changed. It will be restarted.");
	$loaded_mods{$_->block_name}->destruct;
	$this->remove_from_blacklist($_->block_name);
	$_->block_name => $this->_load($_);
    } @$changed;
    my %not_changed_mods = map {
	# 設定変更されなかったモジュール。
	# %loaded_modsに実物が入っている。
	my $modname = $_->block_name;
	if (!defined $loaded_mods{$modname} &&
		$this->check_timestamp_update($modname)) {
	    # ロードできてなくて、なおかつアップデートされていたらロードしてみる。
	    $show_msg->("$modname has been modified. It will be reloaded.");
	    $this->remove_from_blacklist($modname);
	    $modname => $this->_load($_);
	} else {
	    $modname => $loaded_mods{$modname};
	}
    } @$not_changed;

    # $mod_configsに書かれた順序に従い、$this->{modules}を再構成。
    # 但しロードに失敗したモジュールはnullになっているので除外。
    @{$this->{modules}} = grep { defined $_ } map {
	my $modname = $_->block_name;
	$not_changed_mods{$modname} || $rebuilt_mods{$modname} || $new_mods{$modname};
    } @$mod_configs;

    my $deleted_any = @$deleted > 0;
    foreach (@$deleted) {
	# 削除されたモジュール。
	# %loaded_modsに古い物が入っている場合は破棄した上、アンロードする。
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

    # gc の前に一度キャッシュクリア
    $this->_clear_module_cache;

    if ($deleted_any > 0) {
	# 何か一つでもアンロードしたモジュールがあれば、最早参照されなくなったモジュールが
	# あるかどうかを調べ、一つでもあればmark and sweepを実行。
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
    # 前回の_check_difference実行時から、現在のモジュール設定がどのように変化したか。
    # 戻り値は(<新規追加>,<削除>,<変更>,<無変更>) それぞれARRAY<Configuration::Block>への参照である。
    # 新規追加と変更はそれぞれ新しいConfiguration::Blockが、削除には(新しいものが無いので)古いConfiguration::Blockが返される。
    my ($this,$mod_configs) = @_;
    # まずは新たに登場したモジュールと、設定を変更されたモジュールを探す。
    my @new;
    my @changed;
    my @not_changed;
    foreach my $conf (@$mod_configs) {
	my $old_conf = $this->{mod_configs}->{$conf->block_name};
	if (defined $old_conf) {
	    # このモジュールは既に定義されているが、変更を加えられてはいないか？
	    if ($old_conf->equals($conf)) {
		# 変わってない。
		push @not_changed,$conf;
	    }
	    else {
		# 内容が変わった。
		push @changed,$conf;
	    }
	}
	else {
	    # 初めて見るモジュールだ。
	    push @new,$conf;
	}
    }
    # 削除されたモジュールを探す。
    # 上のループと纏める事も出来るが、コードが分かりにくくなる。
    my %names_of_old_modules
	= map { $_ => 1 } keys %{$this->{mod_configs}};
    foreach my $conf (@$mod_configs) {
	delete $names_of_old_modules{$conf->block_name};
    }
    my @deleted = map {
	$this->{mod_configs}->{$_};
    } keys %names_of_old_modules;
    # $this->{mod_configs}に新たな値を設定。
    %{$this->{mod_configs}} =
	map { $_->block_name => $_ } @$mod_configs;
    # 完了
    return (\@new,\@deleted,\@changed,\@not_changed);
}

sub reload_modules_if_modified {
    # コード自体が更新されているモジュールがあれば、それを一旦アンロードしてロードし直す。
    # インスタンスも当然作り直す。
    my $this = shift;

    my $show_msg = sub {
	$this->_runloop->notify_msg($_[0]);
    };

    my $mods_to_be_reloaded = {}; # モジュール名 => 1
    my $check = sub {
	my ($modname,$timestamp) = @_;
	# 既に更新されたものとしてマークされていれば抜ける。
	return if $mods_to_be_reloaded->{$modname};

	if ($this->check_timestamp_update($modname, $timestamp)) {
	    # 更新されている。少なくともこのモジュールはリロードされる。
	    $mods_to_be_reloaded->{$modname} = 1;
	    $show_msg->("$modname has been modified. It will be reloaded.");

	    my $trace;
	    $trace = sub {
		my ($modname, $depth) = @_;
		++$depth;
		no strict 'refs';
		# このモジュールに%USEDは定義されているか？
		my $USED = \%{$modname.'::USED'};
		if (defined $USED) {
		    # USEDの全ての要素に対し再帰的にマークを付ける。
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

    # 一つでもマークされたモジュールがあれば、$this->{modules}内の何処に
    # 目的のモジュールが在るのかを調べるために、モジュール名 => 位置のテーブルを作る。
    if (keys(%$mods_to_be_reloaded) > 0) {
	my $mod2index = {};
	for (my $i = 0; $i < @{$this->{modules}}; $i++) {
	    $mod2index->{ref $this->{modules}->[$i]} = $i;
	}

	# マークされたモジュールをリロードするが、それが$mod2indexに登録されていたら
	# インスタンスを作り直す。
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
		# message_io_hook が定義されているモジュールが死ぬと怖いので
		# とりあえず undef を入れて無視させる。
		$this->{modules}->[$idx] = undef;
		$this->_unload($conf_block);
		$this->{modules}->[$idx] = $this->_load($conf_block); # 失敗するとundefが入る。
		# _unload でブラックリストから消えるから大丈夫だと思うが、一応。
		$this->remove_from_blacklist($modname);
	    }
	    else {
		# アンロード後、use。
		no strict 'refs';
		# その時、%USEDを保存する。@USEは保存しない。
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

	# 全てのモジュールの%USEDを調べて、その%USEDが指しているモジュールが
	# 本当にそのモジュールを参照しているのかどうかをチェック。
	# モジュールの更新で最早参照しなくなっていれば、%USEDから削除する。
	# このような事が起こるのはリロード時に%USEDを保存するためである。
	my $fixed = $this->fix_USED_fields;

	# %USEDの不整合性が見付かったら、もはや必要とされなくなった
	# モジュールがあるかも知れない。gcを実行。
	if ($fixed) {
	    $this->gc;
	}

	# $this->{modules}にはundefの要素が入っているかも知れないので、そのような要素は除外する。
	@{$this->{modules}} = grep {
	    defined $_;
	} @{$this->{modules}};

	$this->_clear_module_cache;
    }
}

sub _load {
    # モジュールをuseしてインスタンスを生成して返す。
    # 失敗したらundefを返す。
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

    # モジュール名をファイル名に変換して%INCを検査。
    # module/で始まっていなければエラー。
    #(my $mod_filename = $mod_name) =~ s|::|/|g;
    #my $filepath = $INC{$mod_filename.'.pm'};
    #if ($filepath !~ m|^module/|) {
    #  $this->_runloop->notify_error(
    #      "Class $mod_name exists outside the module directory.\n$filepath\n");
    #  next;
    #}

    # このモジュールは本当にModuleのサブクラスか？
    # 何故かUNIVERSAL::isaは嘘を付く事があるので自力で@ISA内を検索する。
    # 5.6.0 for darwinではモジュールをリロードすると嘘を付く。
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

    # インスタンス生成
    my $mod;
    eval {
	$mod = $mod_name->new($this->_runloop);
    }; if ($@) {
	$this->_runloop->notify_error(
	    "Couldn't instantiate module $mod_name because of exception.\n$@");
	return undef;
    }

    # このインスタンスは本当に$mod_nameそのものか？
    if (ref($mod) ne $mod_name) {
	$this->_runloop->notify_error(
	    "A thing ".$mod_name."->new returned was not a instance of $mod_name.");
	return undef;
    }

    # timestampに登録
    $this->timestamp($mod_name,time);

    return $mod;
}

sub _unload {
    # 指定されたモジュールを削除する。
    # モジュール名の代わりにConfiguration::Blockを渡しても良い。
    my ($this,$modname) = @_;
    $modname = $modname->block_name if UNIVERSAL::isa($modname,'Configuration::Block');

    # このモジュールのuse時刻を消去
    delete $this->{mod_timestamps}->{$modname};

    # このモジュールのブラックリストを消去。
    $this->remove_from_blacklist($modname);

    # このモジュールのファイル名を求めておく。
    (my $mod_filename = $modname) =~ s|::|/|g;
    $mod_filename .= '.pm';

    # シンボルテーブルを削除してしまえば変数やサブルーチンにアクセス出来なくなる。
    use Symbol ();
    # サブパッケージを消す挙動は危険かもしれないのでとりあえず退避。
    # (%INC のこともあるし)
    # ただし、サブパッケージの性格上メインパッケージなしに動く保証はどこにもない。

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

    # 隔離しておいたものを戻す。
    %{$modname.'::'} = ( %shelter, %{$modname.'::'} );

    # %INCからも削除
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
		# このモジュールの@USEには本当に$modnameが入っているか？
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
		    # 実際には参照されていなかった。
		    delete $USED->{$mod_refs_me};
		    $result = 1;
		}
	    }
	}
    }
    $result;
}

sub gc {
    # $this->{modules}から到達可能でないサブモジュールを全てアンロードする。
    my $this = shift;
    my %all_mods = %{$this->{mod_timestamps}}; # コピーする
    # %all_modsの要素で値が空になっている部分が、マークされた個所。

    my $trace;
    no strict 'refs';
    $trace = sub {
	my $modname = shift;
	# 既にマークされているか、もしくはモジュールが存在しなければ抜ける。
	my $val = $all_mods{$modname};
	if (!defined($val) || $val eq '') {
	    return;
	}
	else {
	    # このモジュールをマークする
	    $all_mods{$modname} = '';
	    # このモジュールに@USEが定義されていたら、
	    # その全てのモジュールについて再帰的にトレース。
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

    # マークされなかったサブモジュールは到達不可能なのでアンロードする。
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
