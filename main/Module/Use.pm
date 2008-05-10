# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# 全てのTiarraモジュールは@ISAにModuleを登録する必要があるが、
# そのモジュールがmodule下の他のperlモジュールをuseしている場合は
# use Module::Use qw(Mod1 Mod2 ...) のようにuseするモジュールを登録しなければならない。
# useされたモジュールが更新された時に、それを参照するTiarraモジュールを再起動させるためである。
# -----------------------------------------------------------------------------
package Module::Use;
use strict;
use warnings;
use ModuleManager;

sub import {
    my ($class,@modules) = @_;
    my ($caller_pkg) = caller;

    # use元の@USEに@modulesを設定。これは到達可能性のトレースに用いられる。
    eval qq{ push(\@${caller_pkg}::USE, \@modules); };

    # use先のUSEDにuse元のクラス名を追加。これはサブモジュール更新時の影響範囲の特定に用いられる。
    foreach (@modules) {
	eval qq{ \$${_}::USED{\$caller_pkg} = 1; };
    }

    if (ModuleManager->__initialized) {
	# ModuleManager が存在していれば、 ModuleManagerにuse先を登録。
	# 存在していなければ RunLoop 経由で起動されていないと思うので無視。
	my $mod_manager = ModuleManager->shared_manager;
	foreach (@modules) {
	    $mod_manager->timestamp($_,time);
	}
    }
}

1;
