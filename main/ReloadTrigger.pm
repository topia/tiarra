# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# conf��⥸�塼��Υ���ɤΰ����⡣
# -----------------------------------------------------------------------------
package ReloadTrigger;
use strict;
use warnings;
use RunLoop;
use Configuration;
use ModuleManager;
use Timer;

sub reload_conf_if_updated {
    # conf�ե����뤬��������Ƥ��������ɤ���
    # Tiarra��Τ��줾��Υ��饹��conf�ι��������Τ��롣
    # �⥸�塼��¦�ǹ������줿���ˤʤˤ��ν����򤹤�ˤϡ�
    # Configuration::Hook �� reloaded ��ȤäƤ���������
    if (Configuration->shared_conf->check_if_updated) {
	Configuration->shared_conf->load;
	RunLoop->shared_loop->update_networks;
	ModuleManager->shared_manager->update_modules;
    }
}

sub reload_mods_if_updated {
    ModuleManager->shared_manager->reload_modules_if_modified;
}

sub _install_reload_timer {
    Timer->new(
	Name => __PACKAGE__.'/reload',
	After => 0,
	Code => sub {
	    reload_conf_if_updated;
	    reload_mods_if_updated;
	}
       )->install;
}

1;
