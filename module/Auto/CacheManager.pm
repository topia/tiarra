# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# このクラスは共通のインスタンスを持ちます。
# キャッシュサイズや有効期限などの設定はAuto::Cacheが行ないます。
#
# 実際のチャンネルの管理は面倒なので、キャッシュ本体は
# ChannelInfoのremarks/cache-of-auto-modulesに保存します。
#
# cache-of-auto-modules: ARRAY
# 要素: [発言内容,発言時刻]
# -----------------------------------------------------------------------------
package Auto::CacheManager;
use strict;
use warnings;
our $_shared;

sub shared {
    if (!defined $_shared) {
	$_shared = Auto::CacheManager->_new;
    }
    $_shared;
}

sub _new {
    my ($class) = @_;
    my $this = {
	size => 0, # デフォルトのキャッシュサイズ。
	expire => 600, # デフォルトの有効期限。単位は秒。
    };
    bless $this,$class;
}

sub cached_p {
    # ch: ChannelInfo
    # str: SCALAR
    # キャッシュされていたら1を返します。
    my ($this,$ch,$str) = @_;
    my $cache = $this->get_cache($ch);
    $this->expire($cache);
    
    foreach (@$cache) {
	if ($_->[0] eq $str) {
	    return 1;
	}
    }
    undef;
}

sub cache {
    my ($this,$ch,$str) = @_;
    my $cache = $this->get_cache($ch);
    $this->expire($cache);
    
    # キャッシュに追加
    push @$cache,[$str,time];
    # キャッシュサイズから溢れた分は削除
    if (@$cache > $this->{size}) {
	splice @$cache,(@$cache - $this->{size});
    }
}

sub get_cache {
    my ($this,$ch) = @_;
    my $cache = $ch->remarks('cache-of-auto-modules');
    if (!defined $cache) {
	$cache = [];
	$ch->remarks('cache-of-auto-modules',$cache);
    }
    $cache;
}

sub expire {
    my ($this,$cache) = @_;
    # まずはexpireされる項目が一つでもあるかどうかを調べる。
    my $limit = time - $this->{expire};
    
    my $expired_some = sub {
	foreach (@$cache) {
	    if ($_->[1] < $limit) {
		return 1;
	    }
	}
	undef;
    }->();

    if ($expired_some) {
	# キャッシュを再構成
	@$cache = grep {
	    $_->[1] >= $limit;
	} @$cache;
    }
}

1;
