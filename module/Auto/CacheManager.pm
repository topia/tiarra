# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# ���Υ��饹�϶��̤Υ��󥹥��󥹤�����ޤ���
# ����å��奵������ͭ�����¤ʤɤ������Auto::Cache���Ԥʤ��ޤ���
#
# �ºݤΥ����ͥ�δ��������ݤʤΤǡ�����å������Τ�
# ChannelInfo��remarks/cache-of-auto-modules����¸���ޤ���
#
# cache-of-auto-modules: ARRAY
# ����: [ȯ������,ȯ������]
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
	size => 0, # �ǥե���ȤΥ���å��奵������
	expire => 600, # �ǥե���Ȥ�ͭ�����¡�ñ�̤��á�
    };
    bless $this,$class;
}

sub cached_p {
    # ch: ChannelInfo
    # str: SCALAR
    # ����å��夵��Ƥ�����1���֤��ޤ���
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
    
    # ����å�����ɲ�
    push @$cache,[$str,time];
    # ����å��奵���������줿ʬ�Ϻ��
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
    # �ޤ���expire�������ܤ���ĤǤ⤢�뤫�ɤ�����Ĵ�٤롣
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
	# ����å����ƹ���
	@$cache = grep {
	    $_->[1] >= $limit;
	} @$cache;
    }
}

1;
