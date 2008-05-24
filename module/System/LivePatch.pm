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
use BulletinBoard;

our $VERSION = '0.03';

our $DEBUG = 0;

1;

# -----------------------------------------------------------------------------
# $pkg->new().
#
sub new
{
  my $pkg = shift;
  my $this = $pkg->SUPER::new(@_);

  $this->{patches} = undef;

  $this->{bbs_val} = undef;
  $this->_load_history();

  eval{
    $this->{patches} = $pkg->_load_patches();
    my $on_load = $this->config->on_load || 'check';
    if( $on_load eq 'apply' )
    {
      RunLoop->shared_loop->notify_msg("- apply by on-load config");
      $this->_apply(-apply => -all);
    }else
    {
      RunLoop->shared_loop->notify_msg("- auto-check on load");
      $this->_apply(-check);
    }
  };
  if( $@ )
  {
    RunLoop->shared_loop->notify_error("$@");
  }

  return $this;
}

# -----------------------------------------------------------------------------
# $obj->message_arrived($msg, $sender).
#
sub message_arrived
{
  my ($this, $msg, $sender) = @_;

  if( !$sender->isa('IrcIO::Client') )
  {
    return $msg;
  }

  my $cmd = uc($this->config->command || 'livepatch');

  if( $msg->command ne $cmd )
  {
    return $msg;
  }

  $msg->remark('do-not-send-to-servers', 1);

  eval
  {
    my $params = $msg->params;
    $params = [@$params]; # sharrow-copy.
    my $param0 = shift @$params || 'help';
    if( $param0 eq 'check' )
    {
      $this->_apply(-check);
    }elsif( $param0 eq 'apply' )
    {
      if( @$params==0 )
      {
        $this->_apply(-apply => -all);
      }else
      {
        RunLoop->shared_loop->notify_msg("too many params for $param0");
      }
    }elsif( $param0 eq 'help' )
    {
      $this->_show_usage();
    }elsif( $param0 eq 'history' )
    {
      $this->_show_history($params);
    }elsif( $param0 eq 'version' )
    {
      $this->_show_version();
    }else
    {
      RunLoop->shared_loop->notify_msg("unknown subcommand: $param0");
    }
  };
  if( $@ )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."#message_arrived, $@");
  }

  return $msg;
}

# -----------------------------------------------------------------------------
# $obj->_show_history($params).
#
sub _show_history
{
  my $this   = shift;
  my $params = shift;
  my $history = $this->{bbs_val}{history};
  my $runloop = $this->_runloop;

  my $nr_history = @$history;
  $runloop->notify_msg(__PACKAGE__.", $nr_history ".($nr_history==1?'entry':'entries')." in history");

  my $base  = shift @$params;
  my $limit = 5;
  if( !defined($base) || $base !~ /^0*\d+\z/ )
  {
    $base = @$history - $limit + 1;
  }
  $base < 1 and $base = 1;

  if( $base > @$history )
  {
    return;
  }
  my $last = $base + $limit - 1;
  if( $last > @$history )
  {
    $last = @$history;
  }
  foreach my $i ($base .. $last)
  {
    my $entry = $history->[$i-1];
    my @tm = localtime($entry->{time});
    $tm[5] += 1900;
    $tm[4] += 1;
    my $time = sprintf('%04d/%02d/%02x %02d:%02d:%02d', reverse @tm[0..5]);
    $runloop->notify_msg("[$i] -");
    $runloop->notify_msg("[$i] package $entry->{pkg}");
    $runloop->notify_msg("[$i] subname $entry->{subname}");
    $runloop->notify_msg("[$i] mode    $entry->{mode}");
    $runloop->notify_msg("[$i] result  $entry->{result}");
    $runloop->notify_msg("[$i] time    ".$time);
  }
}

# -----------------------------------------------------------------------------
# $obj->_show_usage().
#
sub _show_usage
{
  my $this = shift;
  my $runloop = $this->_runloop;

  $runloop->notify_msg("livepatch:");
  $runloop->notify_msg("  help    - show this usage");
  $runloop->notify_msg("  history - show patching history");
  $runloop->notify_msg("  check   - check only");
  $runloop->notify_msg("  apply   - apply patches");
  $runloop->notify_msg("  version - show vesrion");
  $runloop->notify_msg("(end of message)");
}

# -----------------------------------------------------------------------------
# $obj->_show_version().
#
sub _show_version
{
  my $this = shift;
  my $runloop = $this->_runloop;

  $runloop->notify_msg("livepatch VERSION $VERSION:");
}

# -----------------------------------------------------------------------------
# $plans = $pkg->_apply(-check).
# $pkg->_apply(-apply => $plans).
#
sub _apply
{
  my $this  = shift;
  my $mode  = shift || -check;
  my $plans = shift || [];

  my $patches = $this->{patches} or die "patches are not loaded";

  if( $mode eq -check )
  {
    $plans = []; # for output.
    foreach my $patch (@$patches)
    {
      push(@$plans, {
        pkg       => $patch->{pkg},
        subname   => $patch->{subname},
        installed => undef,
        install   => undef,
      });
    }
  }elsif( $mode eq -apply )
  {
    if( $plans eq -all )
    {
      $plans = []; # for output.
      foreach my $patch (@$patches)
      {
        push(@$plans, {
          pkg       => $patch->{pkg},
          subname   => $patch->{subname},
          installed => undef,
          install   => (reverse sort {$a<=>$b} keys %{$patch->{revs}})[0],
        });
      }
    }
    if( ref($plans) eq 'HASH' )
    {
      $plans = [$plans];
    }
  }else
  {
    die "unvalid mode: $mode";
  }

  require B;
  require B::Deparse;
  require Digest::MD5;
  my $deparse = B::Deparse->new();
  my $digest = sub{
    Digest::MD5::md5_hex($_[0]);
  };

  my $patches_hashref = {};
  foreach my $patch (@$patches)
  {
    my $pkg     = $patch->{pkg};
    my $subname = $patch->{subname};
    $patches_hashref->{$pkg}{$subname} = $patch;
  }

  $deparse->ambient_pragmas(
    strict   => 'all',
    warnings => 'all',
  );
  my $runloop = RunLoop->shared_loop;
  my $nr_plans = @$plans;
  my $idx = 0;
  $runloop->notify_msg("- mode = $mode");
  foreach my $plan (@$plans)
  {
    ++$idx;
    my $pkg      = $plan->{pkg};
    my $subname  = $plan->{subname};
    $runloop->notify_msg("- [$idx/$nr_plans]");
    $pkg     or $runloop->notify_msg("  no pkg on plan."),     next;
    $subname or $runloop->notify_msg("  no subname on plan."), next;

    my $patch = $patches_hashref->{$pkg}{$subname};
    $patch   or $runloop->notify_msg("  no such patch, [$pkg] [$subname]."), next;
    my @revs     = reverse sort {$a<=>$b} keys %{$patch->{revs}};
    $runloop->notify_msg("  pkg  => $pkg");
    $runloop->notify_msg("  sub  => $subname");
    $runloop->notify_msg("  revs => ".join(", ", map{"r$_"} @revs));
    my $filter;
    if( $patch->{constants} )
    {
      $runloop->notify_msg("  constants => ");
      foreach my $key (sort keys %{$patch->{constants}})
      {
        $runloop->notify_msg("    $key => $patch->{constants}{$key}");
      }
      my $keys = join('|', map{quotemeta($_)} keys %{$patch->{constants}});
      my $re   = qr/\b(?:$keys)\b/;
      $filter = sub{
        my $ref = shift;
        $$ref =~ s/($re)/$patch->{constants}{$1}/g;
      };
    }
    my $cursub = $pkg->can($patch->{subname});
    if( !defined(&$cursub) )
    {
      $runloop->notify_msg("  current => not loaded.");
      $this->_add_history($patch, $mode, 'not_loaded');
      next;
    }
    my $curtext = $deparse->coderef2text($cursub);
    $filter and $filter->(\$curtext, undef);
    my $curmd5  = $digest->($curtext);
    $runloop->notify_msg("  current => $curmd5");
    $DEBUG and print "<<current>>\n$curtext\n";
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
      $filter and $filter->(\$dump, $rev);
      $DEBUG and print "<<$rev>>\n$dump\n";
      my $md5 = $digest->($dump);
      $lastest ||= {rev=>$rev,'sub'=>$sub,md5=>$md5};
      if( $dump ne $curtext )
      {
        $runloop->notify_msg("  $rev => not match: $md5");
        next;
      }
      $found = $rev;
      if( $rev eq $lastest->{rev} )
      {
        $runloop->notify_msg("  $rev => match, lastest, no need to update.");
        $this->_add_history($patch, $mode, "lastest:$rev");
        if( $mode eq -check )
        {
          $plan->{installed} = $rev;
          $plan->{install}   = undef;
        }else
        {
          $plan->{installed} = $rev;
          $plan->{install}   = undef;
        }
      }else
      {
        if( $mode eq -check )
        {
          $runloop->notify_msg("  $rev => match, can update to $lastest->{rev} (not applied by mode$mode)");
          $this->_add_history($patch, $mode, "found:$rev");
          $plan->{installed} = $rev;
          $plan->{install}   = $lastest->{rev};
        }else
        {
          $runloop->notify_msg("  $rev => match, update to $lastest->{rev}, applied by mode$mode");
          my $lastest_sub = $lastest->{'sub'};
          my $ref = $pkg . '::' . $subname;
          {
            no strict 'refs';
            no warnings 'redefine';
            *$ref = $lastest_sub;
          }
          $this->_add_history($patch, $mode, "updated:$rev:$lastest->{rev}");
        }
      }
      last;
    }
    if( !$found )
    {
      $runloop->notify_msg("  current => unsupported version.");
      $this->_add_history($patch, $mode, 'not_found');
    }
  }

  $plans;
}

# -----------------------------------------------------------------------------
# $pkg->_load_history().
#
sub _load_history
{
  my $this = shift;

  my $BBS_KEY = __PACKAGE__.'/history';
  my $BBS_VAL = BulletinBoard->shared->get($BBS_KEY);
  if( !$BBS_VAL )
  {
    $this->_runloop->notify_msg(__PACKAGE__."#new, bbs[$BBS_KEY] initialize");
    $BBS_VAL = {
      inited_at => time,
      history   => [],
    };
    BulletinBoard->shared->set($BBS_KEY, $BBS_VAL);
  }

  $this->{bbs_val} = $BBS_VAL;
}

# -----------------------------------------------------------------------------
# $pkg->_add_history($patch, $mode, $result).
#
sub _add_history
{
  my $this  = shift;
  my $patch = shift;
  my $mode  = shift;
  my $result = shift;

  my $entry = {
    pkg     => $patch->{pkg},
    subname => $patch->{subname},
    mode    => $mode,
    result  => $result,
    'time'  => time(),
  };

  my $history = $this->{bbs_val}{history};
  my $last_hist;
  foreach my $hist (@$history)
  {
    $hist->{pkg}     eq $entry->{pkg}     or next;
    $hist->{subname} eq $entry->{subname} or next;
    $last_hist = $hist;
  }
  if( !$last_hist || $last_hist->{result} ne $entry->{result} )
  {
    push(@$history, $entry);
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
        3004 => <<'EOF',
# package ModuleManager.
# sub _reload_modules_if_modified_r8809.
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
        8809 => <<'EOF'
# package ModuleManager.
# sub _reload_modules_if_modified_r8809.
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
    {
      pkg => 'LinedINETSocket',
      subname => 'connect',
      revs => {
        3004 => <<'EOF',
# package LinedINETSocket
# sub _connect_r3004
no strict 'refs'; # by SelfLoader.
sub {
    # 接続先ホストとポートを指定して接続を行なう。
    my ($this, $host, $port) = @_;
    return if $this->connected;

    # ソケットを開く。開けなかったらundef。
    my $sock = new IO::Socket::INET(PeerAddr => $host,
				    PeerPort => $port,
				    Proto => 'tcp',
				    Timeout => 5);
    $this->attach($sock);
}
EOF
        8930 => <<'EOF',
# package LinedINETSocket
# sub _connect_r8930
no strict 'refs'; # by SelfLoader.
sub {
    # 接続先ホストとポートを指定して接続を行なう。
    my ($this, $host, $port) = @_;
    return if $this->connected;

    # ソケットを開く。開けなかったらundef。
    my $sock = new IO::Socket::INET(PeerAddr => $host,
				    PeerPort => $port,
				    Proto => 'tcp',
				    Timeout => 5);
    if( $sock )
    {
      $this->attach($sock);
    }else
    {
      undef;
    }
}
EOF
      },
    },
    {
      pkg => 'Configuration::Block',
      subname => 'equals',
      constants => {
        BLOCK_NAME => Configuration::Block::BLOCK_NAME(),
        TABLE      => Configuration::Block::TABLE(),
      },
      revs => {
        3004 => <<'EOF',
sub {
    # 二つのConfiguration::Blockが完全に等価なら1を返す。
    my ($this,$that) = @_;
    # ブロック名
    if ($this->[BLOCK_NAME] ne $that->[BLOCK_NAME]) {
	return undef;
    }
    # キーの数
    my @this_keys = keys %{$this->[TABLE]};
    my @that_keys = keys %{$that->[TABLE]};
    if (@this_keys != @that_keys) {
	return undef;
    }
    # 各要素
    my $size = @this_keys;
    for (my $i = 0; $i < $size; $i++) {
	# キー
	if ($this_keys[$i] ne $that_keys[$i]) {
	    return undef;
	}
	# 値の型
	my $this_value = $this->[TABLE]->{$this_keys[$i]};
	my $that_value = $that->[TABLE]->{$that_keys[$i]};
	if (ref($this_value) ne ref($that_value)) {
	    return undef;
	}
	# 値
	if (ref($this_value) eq 'ARRAY') {
	    # 配列なので要素数と全要素を比較。
	    if (@$this_value != @$that_value) {
		return undef;
	    }
	    my $valsize = @$this_value;
	    for (my $j = 0; $j < $valsize; $j++) {
		if ($this_value->[$j] ne $that_value->[$j]) {
		    return undef;
		}
	    }
	}
	elsif (UNIVERSAL::isa($this_value,'Configuration::Block')) {
	    # ブロックなので再帰的に比較。
	    return $this_value->equals($that_value);
	}
	else {
	    if ($this_value ne $that_value) {
		return undef;
	    }
	}
    }
    return 1;
}
EOF
        11868 => <<'EOF',
sub {
    # 二つのConfiguration::Blockが完全に等価なら1を返す。
    my ($this,$that) = @_;
    # ブロック名
    if ($this->[BLOCK_NAME] ne $that->[BLOCK_NAME]) {
	return undef;
    }
    # キーの数
    my @this_keys = keys %{$this->[TABLE]};
    my @that_keys = keys %{$that->[TABLE]};
    if (@this_keys != @that_keys) {
	return undef;
    }
    # 各要素
    my $size = @this_keys;
    for (my $i = 0; $i < $size; $i++) {
	# キー
	if ($this_keys[$i] ne $that_keys[$i]) {
	    return undef;
	}
	# 値の型
	my $this_value = $this->[TABLE]->{$this_keys[$i]};
	my $that_value = $that->[TABLE]->{$that_keys[$i]};
	if (ref($this_value) ne ref($that_value)) {
	    return undef;
	}
	# 値
	if (ref($this_value) eq 'ARRAY') {
	    # 配列なので要素数と全要素を比較。
	    if (@$this_value != @$that_value) {
		return undef;
	    }
	    my $valsize = @$this_value;
	    for (my $j = 0; $j < $valsize; $j++) {
		if ($this_value->[$j] ne $that_value->[$j]) {
		    return undef;
		}
	    }
	}
	elsif (UNIVERSAL::isa($this_value,'Configuration::Block')) {
	    # ブロックなので再帰的に比較。
	    my $ret = $this_value->equals($that_value);
	    if (!$ret) {
		return undef;
	    }
	}
	else {
	    if ($this_value ne $that_value) {
		return undef;
	    }
	}
    }
    return 1;
}
EOF
      },
    },
#    {
#      pkg => 'Tiarra::XXX',
#      subname => 'xxx',
#      #filter => sub {},
#      revs => {
#        3004 => <<'EOF',
#EOF
#        9999 => <<'EOF',
#EOF
#      },
#    },
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

package System::LivePatch;

=begin tiarra-doc

info:    Live Patch.
default: off
#section: important

# main/* に対する実行時パッチ
# 起動/ロード時に確認は行われるが, 実際の適用は指示があるまで行われない.

# 対応している箇所.
# ModuleManager / reload_modules_if_modified / r3004 => r8809
# LinedINETSocket / connect / r3004 => r8930
# Configuration::Block / equals / r3004 => r11868

# /livepatch check で確認.
# /livepatch apply で適用.
command: livepatch

=end tiarra-doc

=cut
