# -----------------------------------------------------------------------------
# $Id: ReloadTrigger.pm,v 1.2 2003/01/22 11:07:07 admin Exp $
# -----------------------------------------------------------------------------
# confやモジュールのリロードの引き金。
# -----------------------------------------------------------------------------
package ReloadTrigger;
use strict;
use warnings;
use RunLoop;
use Configuration;
use ModuleManager;

sub reload_conf_if_updated {
    # confファイルが更新されていたらリロードし、
    # Tiarra内のそれぞれのクラスにconfの更新を通知する。
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
