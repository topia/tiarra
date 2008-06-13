# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# confやモジュールのリロードの引き金。
# -----------------------------------------------------------------------------
package ReloadTrigger;
use strict;
use warnings;
use RunLoop;
use Timer;

sub reload_conf_if_updated {
    # confファイルが更新されていたらリロードし、
    # Tiarra内のそれぞれのクラスにconfの更新を通知する。
    # モジュール側で更新された場合になにかの処理をするには、
    # Configuration::Hook の reloaded を使ってください。
    my $runloop = shift;
    unless (ref($runloop) && $runloop->isa('RunLoop')){
	$runloop = RunLoop->shared_loop;
    }
    if ($runloop->config->check_if_updated) {
	$runloop->config->load;
	$runloop->update_networks;
	$runloop->mod_manager->update_modules;
    }
}

sub reload_mods_if_updated {
    my $runloop = shift;
    unless (ref($runloop) && $runloop->isa('RunLoop')){
	$runloop = RunLoop->shared_loop;
    }
    $runloop->mod_manager->reload_modules_if_modified;
}

sub reload_all_if_updated {
    my $runloop = shift;
    unless (ref($runloop) && $runloop->isa('RunLoop')){
	$runloop = RunLoop->shared_loop;
    }
    if ($runloop->config->check_if_updated) {
	$runloop->config->load;
	$runloop->update_networks;
    }
    $runloop->mod_manager->update_modules(
	check_module_update => 1,
       );
}

sub _install_reload_timer {
    my $runloop = shift;
    unless (ref($runloop) && $runloop->isa('RunLoop')){
	$runloop = RunLoop->shared_loop;
    }
    Timer->new(
	Name => __PACKAGE__.'/reload',
	After => 0,
	Code => sub {
	    reload_all_if_updated;
	}
       )->install($runloop);
}

1;
