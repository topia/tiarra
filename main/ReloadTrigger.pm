# -----------------------------------------------------------------------------
# $Id: ReloadTrigger.pm,v 1.3 2004/07/08 15:13:13 topia Exp $
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
    # モジュール側で更新された場合になにかの処理をするには、
    # Configuration::Hook の reloaded を使ってください。
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
