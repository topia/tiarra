# -----------------------------------------------------------------------------
# $Id: Use.pm,v 1.2 2003/01/22 11:07:08 admin Exp $
# -----------------------------------------------------------------------------
# ���Ƥ�Tiarra�⥸�塼���@ISA��Module����Ͽ����ɬ�פ����뤬��
# ���Υ⥸�塼�뤬module����¾��perl�⥸�塼���use���Ƥ������
# use Module::Use qw(Mod1 Mod2 ...) �Τ褦��use����⥸�塼�����Ͽ���ʤ���Фʤ�ʤ���
# use���줿�⥸�塼�뤬�������줿���ˡ�����򻲾Ȥ���Tiarra�⥸�塼���Ƶ�ư�����뤿��Ǥ��롣
# -----------------------------------------------------------------------------
package Module::Use;
use strict;
use warnings;
use ModuleManager;

sub import {
    my ($class,@modules) = @_;
    my ($caller_pkg) = caller;

    # use����@USE��@modules�����ꡣ�������ã��ǽ���Υȥ졼�����Ѥ����롣
    eval qq{ \@${caller_pkg}::USE = \@modules; };

    # use���USED��use���Υ��饹̾���ɲá�����ϥ��֥⥸�塼�빹�����αƶ��ϰϤ�������Ѥ����롣
    foreach (@modules) {
	eval qq{ \$${_}::USED{\$caller_pkg} = 1; };
    }

    # ModuleManager��use�����Ͽ��
    my $mod_manager = ModuleManager->shared_manager;
    foreach (@modules) {
	$mod_manager->timestamp($_,time);
    }
}

1;
