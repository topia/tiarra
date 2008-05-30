# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Tools::Reload.
# -----------------------------------------------------------------------------
package Tools::Reload;
use strict;
use warnings;
use BulletinBoard;
use Timer;

# -----------------------------------------------------------------------------
# とりあえずサンプル.
# うごくかわかんない.
# -----------------------------------------------------------------------------

our $VERSION = '0.01';
our $BBS_KEY = __PACKAGE__;

our $DEFAULT_EXPIRE = 300; # seconds.

1;

# -----------------------------------------------------------------------------
# (private)
# $bbs_val = $pkg->_get().
# $bbs_val = $pkg->_get(-no_create).
# 全部の情報が入ってるハッシュを取得.
#
sub _get
{
  my $this = shift;
  my $no_create = shift;

  my $bbs_val = BulletinBoard->shared->get($BBS_KEY);
  if( !$bbs_val && !$no_create )
  {
    #$runloop->notify_msg(__PACKAGE__."#_get, bbs[$BBS_KEY] initialize");
    $bbs_val = {
      inited_at   => time,
      data        => {},
    };
    BulletinBoard->shared->set($BBS_KEY, $bbs_val);
  }
  $bbs_val;
}

# -----------------------------------------------------------------------------
# Reload->store($my_key, $value).
#
sub store
{
  my $this  = shift;
  my $opts;
  if( @_ >= 2 )
  {
    my $key   = shift;
    my $value = shift;
    $opts = {
      Key    => $key,
      Value  => $value,
      Expire => $DEFAULT_EXPIRE,
    };
  }else
  {
    $opts = shift;
  }

  my $key    = $opts->{Key}   or die __PACKAGE__."#store, no Key";
  my $value  = $opts->{Value} or die __PACKAGE__."#store, no Value";
  my $expire = $opts->{Expire} || $DEFAULT_EXPIRE;

  my $bbs_val = $this->_get();

  my $ref = ref($key) || "$key";
  my $timer = Timer->new(
    After => $expire,
    Code  => sub{
      if( $bbs_val->{data} )
      {
        delete $bbs_val->{data}{$ref};
      }
    },
  )->install;

  my $entry = {
    key    => $ref,
    value  => $value,
    timer  => $timer,
    after  => $expire,
  };

  $bbs_val->{data}{$ref} = $entry;
  $value;
}

# -----------------------------------------------------------------------------
# my $value = Reload->get($my_key).
#
sub get
{
  my $this = shift;
  my $key  = shift;

  $key or die __PACKAGE__."#get, no key";

  my $bbs_val = $this->_get();

  my $ref = ref($key) || "$key";
  $bbs_val->{data}{$ref} && $bbs_val->{data}{$ref}{value};
}

# -----------------------------------------------------------------------------
# my $existence = Reload->exists($my_key).
#
sub exists
{
  my $this = shift;
  my $key  = shift;

  $key or die __PACKAGE__."#exists, no key";

  my $bbs_val = $this->_get();

  my $ref = ref($key) || "$key";
  CORE::exists($bbs_val->{data}{$ref});
}

=head1 NAME

Tools::Reload - save data for reloading.

=head1 SYNOPSIS

 $my_key = __PACKAGE__;

 # At destruct().
 Tools::Reload->store($my_key, $value);

 # At new().
 my $value = Tools::Reload->fetch($my_key);
 if( !$value )
 {
   # new loading.
 }else
 {
   # reloading.
 }

=head1 DESCRIPTION

リロード用にデータの一時保存.
リロードじゃなくてアンロードだった場合は, 
タイマーで既定秒後に削除される.

=cut

