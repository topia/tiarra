# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Terminate Hook for write Portable Module
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::TerminateManager;
use strict;
use warnings;
use Carp;
use Hook;
use base qw(HookTarget);
use Tiarra::SharedMixin;
use Tiarra::Utils;
my $utils = Tiarra::Utils->shared;

sub _new {
    my $class = shift;

    my $this = {};
    bless $this, $class;
    $this;
}

sub terminate {
    my ($class_or_this, $name) = @_;
    my $this = $class_or_this->_this;

    $this->call_hooks($name);
}

package Tiarra::TerminateManager::Hook;
use FunctionalVariable;
use Hook;
use base qw(Hook);
our $HOOK_TARGET_NAME = 'Tiarra::TerminateManager';
our @HOOK_NAME_CANDIDATES = qw(main);
our $HOOK_NAME_DEFAULT = 'main';
our $HOOK_TARGET_DEFAULT;
FunctionalVariable::tie(
    \$HOOK_TARGET_DEFAULT,
    FETCH => sub {
	$HOOK_TARGET_NAME->shared;
    },
   );

1;
