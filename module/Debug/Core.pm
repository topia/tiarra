## ----------------------------------------------------------------------------
#  Debug::Core.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Debug::Core;
use strict;
use warnings;
use base qw(Module);

our $DEFAULT_COMMAND = 'debugcore';

1;

# -----------------------------------------------------------------------------
# $pkg->new().
#
sub new
{
  my $class = shift;
  my $this = $class->SUPER::new(@_);

  $this->{command} = uc($this->config->command || $DEFAULT_COMMAND);

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

  if( $msg->command ne $this->{command} )
  {
    return $msg;
  }

  $msg->remark('do-not-send-to-servers', 1);

  my $params = $msg->params;
  $params    = [@$params]; # sharrow-copy.
  my $param0 = shift @$params || 'help';
  eval
  {
    $this->_dispatch($params, $param0, $msg, $sender);
  };
  if( $@ )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."#message_arrived: $@");
  }

  return $msg;
}

# -----------------------------------------------------------------------------
# $obj->_dispatch($params, $name, $msg, $sender).
#
sub _dispatch
{
  my ($this, $params, $name, $msg, $sender) = @_;

  my $subname = "_debugcore_".$name;
  $subname =~ tr/-/_/;

  my $sub = $this->can($subname);
  if( !$sub )
  {
    $this->_runloop->notify_msg("unknown command: $name");
    return;
  }

  $this->$sub($params, $name, $msg, $sender);
}

# -----------------------------------------------------------------------------
# $obj->_debugcore_help($params, $name, $msg, $sender).
# (impl:debugcore)
#
sub _debugcore_help
{
  my $this   = shift;
  my $params = shift;

  $this->_runloop->notify_msg("debugcore:");
  $this->_runloop->notify_msg("  help   - show this usage.");
  $this->_runloop->notify_msg("  bbs    - show BulletinBoard info.");
  $this->_runloop->notify_msg("  socket - show internal sockets.");
  $this->_runloop->notify_msg("  module - show module info.");
  $this->_runloop->notify_msg("(end of message)");
}

# -----------------------------------------------------------------------------
# $obj->_debugcore_bbs($params, $name, $msg, $sender).
# (impl:debugcore)
#
sub _debugcore_bbs
{
  my $this   = shift;
  my $params = shift;

  my $runloop = $this->_runloop;
  my $subcmd = shift @$params || 'keys';

  if( !BulletinBoard->can("shared") && $subcmd ne 'help' )
  {
    $runloop->notify_msg("bbs - not loaded");
    return;
  }

  if( $subcmd eq 'help' )
  {
    $this->_runloop->notify_msg("bbs:");
    $this->_runloop->notify_msg("  keys - show keys in BulletinBoard.");
    $this->_runloop->notify_msg("(end of message)");
  }elsif( $subcmd eq 'keys' )
  {
    my $keys = [BulletinBoard->shared->keys];
    @$keys = sort @$keys;
    my $nr_keys  = @$keys;
    $runloop->notify_msg("bbs - $nr_keys ".($nr_keys==1 ? 'key exists' : 'keys exist'));

    my $base  = shift @$params || 0;
    my $limit = 5;
    $base =~ /^0*\d+\z/ or $base = 0;

    if( $base >= @$keys )
    {
      return;
    }
    my $last = $base + $limit - 1;
    if( $last > $#$keys )
    {
      $last = $#$keys;
    }
    foreach my $i ($base .. $last)
    {
      my $key = $keys->[$i];
      my $val = BulletinBoard->get($key);

      if( my $ref = ref($val) )
      {
        if( UNIVERSAL::isa($val, 'ARRAY') )
        {
          my $n = @$val;
          my $elms = $n==1 ? 'elm' : 'elms';
          $val = "[ARRAY/$n $elms] $val";
        }elsif( UNIVERSAL::isa($val, 'HASH') )
        {
          my $n = keys %$val;
          my $keys = $n==1 ? 'key' : 'keys';
          $val = "[HASH/$n $keys] $val";
        }else
        {
          $val = "[REF] $val";
        }
      }else
      {
        if( defined($val) )
        {
          $val = "[SCALAR] $val";
        }else
        {
          $val = "[UNDEF]";
        }
      }
      if( length($val) > 40 )
      {
        substr($val, 37) = '...';
      }

      $runloop->notify_msg("bbs - [$i] $key = $val");
    }
  }else
  {
    $runloop->notify_msg("bbs - unknown subcommand: $subcmd");
  }
}

# -----------------------------------------------------------------------------
# $obj->_debugcore_socket($params, $name, $msg, $sender).
# (impl:debugcore)
#
sub _debugcore_socket
{
  my $this   = shift;
  my $params = shift;

  my $runloop = $this->_runloop;
  my $subcmd  = shift @$params || 'list';

  my $get_socket = sub{
    my $i = shift;
    if( !defined($i) )
    {
      $runloop->notify_msg("socket - $subcmd: require param");
      return;
    }
    if( $i !~ /^\d+\z/ )
    {
      $runloop->notify_msg("socket - $subcmd: invalid index: $i");
      return;
    }
    my $sockets = $this->_runloop->{sockets};
    if( $i > $#$sockets )
    {
      $runloop->notify_msg("socket - $subcmd: $i is out of range, max=$#$sockets");
      return;
    }
    my $socket = $sockets->[$i];
    if( !$socket )
    {
      $runloop->notify_msg("socket - [$i] ".(defined($socket)?"false:$socket":"undef"));
    }
    $socket;
  };

  if( $subcmd eq 'help' )
  {
    $this->_runloop->notify_msg("socket:");
    $this->_runloop->notify_msg("  help      - show this usage.");
    $this->_runloop->notify_msg("  list      - show installed socket.");
    $this->_runloop->notify_msg("  get       - show socket in detail.");
    $this->_runloop->notify_msg("  uninstall - uninstall detached socket.");
    $this->_runloop->notify_msg("(end of message)");
  }elsif( $subcmd eq 'list' )
  {
    my $sockets = $this->_runloop->{sockets};
    $sockets = [@$sockets]; # sharrow-copy.
    my $nr_sockets  = @$sockets;
    $runloop->notify_msg("socket - $nr_sockets ".($nr_sockets==1 ? 'sockets exists' : 'sockets exist'));

    my $base  = shift @$params || 0;
    my $limit = 5;
    $base =~ /^0*\d+\z/ or $base = 0;

    if( $base >= @$sockets )
    {
      return;
    }
    my $last = $base + $limit - 1;
    if( $last > $#$sockets )
    {
      $last = $#$sockets;
    }
    foreach my $i ($base .. $last)
    {
      my $socket = $sockets->[$i];
      my $sockref = ref($socket->sock) || '-';
      my $ref = ref($socket);

      foreach ($ref, $sockref)
      {
        s/^IrcIO::Server(?=::|$)/IrcIO::S/;
        s/^IrcIO::Client(?=::|$)/IrcIO::C/;
        s/^Tools::/T::/;
        s/^IO::Socket::/IO::S::/;
      }
      my $val = "$ref ($sockref) ".$socket->name;

      if( length($val) > 40 )
      {
        substr($val, 37) = '...';
      }

      $runloop->notify_msg("socket - [$i] $val");
    }
  }elsif( $subcmd eq 'get' )
  {
    my $i = shift @$params;
    my $socket = $get_socket->($i);
    $socket or return;

    my ($cls,$ptr)  = split(/=/, $socket);
    $ptr ||= '-';
    $runloop->notify_msg("socket - [$i] $cls");
    $runloop->notify_msg("socket - [$i] ptr:  ($ptr)");

    my $sock = $socket->sock;
    my ($scls,$sptr)  = split(/=/, $sock || '-');
    $sptr ||= '-';
    my $fd = $sock ? fileno($sock) : undef;
    defined($fd) or $fd = '-';
    $runloop->notify_msg("socket - [$i] name: ".($socket->name||'-'));
    $runloop->notify_msg("socket - [$i] sock: $scls");
    $runloop->notify_msg("socket - [$i] sock.ptr: $sptr");
    $runloop->notify_msg("socket - [$i] sock.fd:  $fd");
  }elsif( $subcmd eq 'uninstall' )
  {
    my $i = shift @$params;
    my $socket = $get_socket->($i);
    $socket or return;

    if( $socket->sock )
    {
      $runloop->notify_msg("socket - uninstall [$i] socket is still attached, not uninstalled");
      return;
    }

    my ($cls,$ptr)  = split(/=/, $socket);
    $ptr ||= '-';
    $runloop->notify_msg("socket - [$i] $cls");
    $runloop->notify_msg("socket - [$i] ptr:  ($ptr)");

    my $sock = $socket->sock;
    my ($scls,$sptr)  = split(/=/, $sock || '-');
    $sptr ||= '-';
    my $fd = $sock ? fileno($sock) : undef;
    defined($fd) or $fd = '-';
    $runloop->notify_msg("socket - [$i] name: ".($socket->name||'-'));
    $runloop->notify_msg("socket - [$i] sock: $scls");
    $runloop->notify_msg("socket - [$i] sock.ptr: $sptr");
    $runloop->notify_msg("socket - [$i] sock.fd:  $fd");
    $runloop->notify_msg("socket - [$i] uninstall ...");
    eval{ $runloop->uninstall_socket($socket); };
    if( $@ )
    {
      $runloop->notify_msg("socket - [$i] uninstall failed: $@");
      return;
    }
    $runloop->notify_msg("socket - [$i] uninstall success");
  }else
  {
    $runloop->notify_msg("socket - unknown subcommand: $subcmd");
  }
}

# -----------------------------------------------------------------------------
# $obj->_debugcore_module($params, $name, $msg, $sender).
# (impl:debugcore)
#
sub _debugcore_module
{
  my $this   = shift;
  my $params = shift;

  my $runloop = $this->_runloop;
  my $subcmd = shift @$params || 'summary';

  if( $subcmd eq 'help' )
  {
    $this->_runloop->notify_msg("module:");
    $this->_runloop->notify_msg("  help    - show this usage.");
    $this->_runloop->notify_msg("  summary - show module summary.");
    $this->_runloop->notify_msg("  list    - show module list in detail.");
    $this->_runloop->notify_msg("  dep     - show module dependency.");
    $this->_runloop->notify_msg("(end of message)");
  }elsif( $subcmd eq 'summary' )
  {
    my $mman    = $runloop->_mod_manager;
    my $modlist = $mman->get_modules('even-if-blacklisted');
    my $nr_mods = @$modlist;

    $runloop->notify_msg($nr_mods.(@$modlist==1?' module is':' modules are').' loaded');
    my ($mlen) = sort{$b<=>$a} map{length(ref($_))} @$modlist;
    foreach my $i (0 .. $nr_mods-1)
    {
      my $mod = $modlist->[$i];
      my ($mref,$mptr) = split(/=/, $mod);
      my $black = $mman->check_blacklist($mref) ? '*' : '-';
      $mref = sprintf('%-*s', $mlen, $mref);
      my $prefix = sprintf('module - [%02d] ', $i);
      $runloop->notify_msg($prefix."$mref $black $mptr");
    }
    my %coms = map{ ref($_)=>$_ } @$modlist;;
 
    my $submodlist = [sort grep{!$coms{$_}} keys %{$mman->{mod_timestamps}}];
    my $nr_submods = @$submodlist;
    $runloop->notify_msg("$nr_submods sub".(@$modlist==1?' module is':' modules are').' loaded');
    foreach my $i (0 .. $#$submodlist)
    {
      my $mref = $submodlist->[$i];
      my $prefix = sprintf('module - [%02d] ', $i);
      $runloop->notify_msg($prefix.$mref);
    }
  }elsif( $subcmd eq 'list' )
  {
    my $mman    = $runloop->_mod_manager;
    my $modlist = $mman->get_modules('even-if-blacklisted');
    my $nr_mods = @$modlist;

    $runloop->notify_msg($nr_mods.(@$modlist==1?' module is':' modules are').' loaded');

    my $base  = shift @$params || 0;
    my $limit = 5;
    $base =~ /^0*\d+\z/ or $base = 0;

    if( $base >= @$modlist )
    {
      return;
    }
    my $last = $base + $limit - 1;
    if( $last > $#$modlist )
    {
      $last = $#$modlist;
    }
    my ($mlen) = sort{$b<=>$a} map{length(ref($modlist->[$_]))} $base .. $last;
    foreach my $i ($base .. $last)
    {
      my $mod = $modlist->[$i];
      my ($mref,$mptr) = split(/=/, $mod);
      my $black = $mman->check_blacklist($mref);
      $mptr ||= '-';
      my $prefix = sprintf('module - [%02d] ', $i);
      $runloop->notify_msg($prefix."-");
      $runloop->notify_msg($prefix."$mref");
      $runloop->notify_msg($prefix."ptr:   ".$mptr);
      $runloop->notify_msg($prefix."black: ".($black?"YES":"-"));
    }
  }elsif( $subcmd eq 'dep' )
  {
    my $mod = shift @$params;
    if( !$mod )
    {
      $runloop->notify_msg("usage: module dep {module-name}");
      return;
    }
    my %var_cache;
    my $get_usevars = sub{
      my $mod = shift;
      if( my $pair = $var_cache{$mod} )
      {
        return @$pair;
      }
      if( $mod !~ /^([A-Z]\w*(?:::[A-Z]\w*)*)\z/ )
      {
        $runloop->notify_msg("invalid module name: $mod");
        return;
      }
      $mod = $1; # untaint.
      my $use_varname  = $mod . '::' . 'USE';
      my $used_varname = $mod . '::' . 'USED';
      my ($use, $used);
      {
        no strict 'refs';
        $use  = \@{$use_varname};
        $used = \%{$used_varname};
      }
      $var_cache{$mod} = [$use, $used];
      ($use, $used);
    };

    my ($use, $used) = $get_usevars->($mod);
    my $nr_use  = @$use;
    my $nr_used = keys %$used;
    $runloop->notify_msg("$mod uses $nr_use".($nr_use==1?' module':' modules'));
    $use = [sort @$use];
    foreach my $i (1..@$use)
    {
      $runloop->notify_msg("  USE[$i] = $use->[$i-1]");
    }
    $runloop->notify_msg("$mod is used from $nr_used".($nr_used==1?' module':' modules'));
    my $used_list = [sort keys %$used];
    foreach my $i (1..@$used_list)
    {
      $runloop->notify_msg("  USED[$i] = $used_list->[$i-1]");
    }

    my %deep_use;
    my @deep_use = @$use;
    while( @deep_use )
    {
      my $m = shift @deep_use;
      $deep_use{$m} and next;
      $deep_use{$m} = 1;
      my ($use, $used) = $get_usevars->($m);
      push(@deep_use, @$use);
    }
    delete @deep_use{@$use};
    @deep_use = sort keys %deep_use;
    my $nr_deep_use = @deep_use;
    $runloop->notify_msg("$mod has $nr_deep_use deeply use ".($nr_deep_use==1?'module':'modules'));
    foreach my $i (1..@deep_use)
    {
      $runloop->notify_msg("  DEEP_USE[$i] = $deep_use[$i-1]");
    }

    my %deep_used;
    my @deep_used = keys %$used;
    while( @deep_used )
    {
      my $m = shift @deep_used;
      $deep_used{$m} and next;
      $deep_used{$m} = 1;
      my ($use, $used) = $get_usevars->($m);
      push(@deep_used, keys %$used);
    }
    delete @deep_used{@$used_list};
    @deep_used = sort keys %deep_used;
    my $nr_deep_used = @deep_used;
    $runloop->notify_msg("$mod has $nr_deep_used deeply used ".($nr_deep_used==1?'module':'modules'));
    foreach my $i (1..@deep_used)
    {
      $runloop->notify_msg("  DEEP_USED[$i] = $deep_used[$i-1]");
    }
  }else
  {
    $runloop->notify_msg("module - unknown subcommand: $subcmd");
  }
}

# -----------------------------------------------------------------------------
# End of Module.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# End of File.
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

info:    Tiarra の内部構造の追跡.
default: off
#section: important

# Tiarra の内部構造を出力します.

# トリガー用コマンド.
# デフォルトは debugcore
command: debugcore

# [top commands]
# help   - show this usage.
# bbs    - show BulletinBoard info.
# socket - show internal sockets.
# module - show module info.

# [sub commands]
# help:
# bbs:
#   keys - show keys in BulletinBoard.
# socket:
#   help      - show this usage.
#   list      - show installed socket.
#   get       - show socket in detail.
#   uninstall - uninstall detached socket.
# module:
#   help    - show this usage.
#   summary - show module summary.
#   list    - show module list in detail.
#   dep     - show module dependency.

=end tiarra-doc

=cut
