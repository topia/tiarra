## ----------------------------------------------------------------------------
#  System::LivePatch.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# main/モジュールに対する動的パッチ.
# -----------------------------------------------------------------------------
package System::LivePatch;
use strict;
use warnings;
use base qw(Module);

our $PATCHES;
our $CODE2PATCH;

1;

# -----------------------------------------------------------------------------
# $pkg->new().
#
sub new
{
  my $pkg = shift;
  my $this = $pkg->SUPER::new(@_);

  eval{
    $this->_load_codes();
  };
  if( $@ )
  {
    RunLoop->shared_loop->notify_error("$@");
  }

  return $this;
}

# -----------------------------------------------------------------------------
# $pkg->_load_codes().
#
sub _load_codes
{
  my $thispkg = shift;
  $PATCHES = $thispkg->_load_patches();
  $CODE2PATCH = {};

  require B;
  require B::Deparse;
  require Digest::MD5;
  my $deparse = B::Deparse->new();
  my $digest = sub{
    Digest::MD5::md5_hex($_[0]);
  };

  $deparse->ambient_pragmas(
    strict   => 'all',
    warnings => 'all',
  );
  my $runloop = RunLoop->shared_loop;
  foreach my $patch (@$PATCHES)
  {
    my $pkg      = $patch->{pkg};
    my $subname  = $patch->{subname};
    my @revs     = reverse sort keys %{$patch->{revs}};
    $runloop->notify_msg("-");
    $runloop->notify_msg("  pkg  => $pkg");
    $runloop->notify_msg("  sub  => $subname");
    $runloop->notify_msg("  revs => ".join(", ", @revs));
    my $cursub = $pkg->can($patch->{subname});
    if( !defined(&$cursub) )
    {
      $runloop->notify_msg("  current => not loaded.");
      next;
    }
    my $curtext = $deparse->coderef2text($cursub);
    my $curmd5  = $digest->($curtext);
    $runloop->notify_msg("  current => $curmd5");
    my $found;
    my $lastest;
    foreach my $rev (@revs)
    {
      my $eval = "p"."ackage $pkg; ".$patch->{revs}{$rev};
      my $sub = eval $eval;
      if( $@ )
      {
        $runloop->notify_msg("  $rev => load failed: $@");
        next;
      }
      my $dump = $deparse->coderef2text($sub);
      if( $dump ne $curtext )
      {
        my $md5 = $digest->($dump);
        $runloop->notify_msg("  $rev => not match: $md5");
        $lastest ||= {rev=>$rev,'sub'=>$sub,md5=>$md5};
        next;
      }
      $found = $rev;
      if( $rev eq $revs[0] )
      {
        $runloop->notify_msg("  $rev => match, lastest.");
      }else
      {
        $runloop->notify_msg("  $rev => match, update to $lastest->{rev}");
        my $lastest_sub = $lastest->{'sub'};
        my $ref = $pkg . '::' . $subname;
        no strict 'refs';
        no warnings 'redefine';
        *$ref = $lastest_sub;
      }
      last;
    }
    if( !$found )
    {
      $runloop->notify_msg("  current => unsupported version.");
    }
  }
}

# -----------------------------------------------------------------------------
# $pkg->_load_patches().
#
sub _load_patches
{
  [
    {
      pkg => 'ModuleManager',
      subname => 'reload_modules_if_modified',
      revs => {
        r3004 => <<'EOF',
# package ModuleManager.
# sub _reload_modules_if_modified_r8009.
sub {
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
EOF
        r8009 => <<'EOF'
# package ModuleManager.
# sub _reload_modules_if_modified_r8009.
sub {
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

	my @mods_load_order = map { $_->[0] }
	    sort { $a->[1] <=> $b->[1] }
		map { [$_, $mods_to_be_reloaded->{$_}]; }
		    keys %$mods_to_be_reloaded;

	# 先に destruct して回る
	foreach my $modname (reverse @mods_load_order) {
	    my $idx = $mod2index->{$modname};
	    if (defined $idx) {
		eval {
		    $this->{modules}->[$idx]->destruct;
		}; if ($@) {
		    $this->_runloop->notify_error($@);
		}
	    } else {
		eval {
		    $modname->destruct;
		}; if ($@ && $modname->can('destruct')) {
		    $this->_runloop->notify_error($@);
		}
	    }
	}

	# マークされたモジュールをリロードするが、それが$mod2indexに登録されていたら
	# インスタンスを作り直す。
	foreach my $modname (@mods_load_order) {
	    my $idx = $mod2index->{$modname};
	    if (defined $idx) {
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
EOF
      },
    },
  ];
}

# -----------------------------------------------------------------------------
# End of Module.
# -----------------------------------------------------------------------------
__END__

=encoding utf8

=for stopwords
	YAMASHINA
	Hio
	ACKNOWLEDGEMENTS
	AnnoCPAN
	CPAN
	RT

=begin tiarra-doc

info:    Live Patch.
default: off
#section: important

# main/* に対する実行時パッチ
# 有効にすれば自動で適用される.

# 対応している箇所.
# ModuleManager / reload_modules_if_modified / r3004 => r8009

=end tiarra-doc

=cut
