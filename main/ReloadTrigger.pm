# -----------------------------------------------------------------------------
# $Id: ReloadTrigger.pm,v 1.3 2004/07/08 15:13:13 topia Exp $
# -----------------------------------------------------------------------------
# conf��⥸�塼��Υ���ɤΰ����⡣
# -----------------------------------------------------------------------------
package ReloadTrigger;
use strict;
use warnings;
use RunLoop;
use Configuration;
use ModuleManager;

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

1;
