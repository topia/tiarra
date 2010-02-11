# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Freenode support.
# -----------------------------------------------------------------------------
# copyright (C) 2010 Topia <topia@clovery.jp>. all rights reserved.
package Network::Freenode;
use strict;
use warnings;
use NumericReply;
use base qw(Module);

sub config_reload {
    my ($this, $old_config) = @_;
    return $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	    ($sender->isupport->{NETWORK} || '') eq 'freenode') {
	my $cmd = $msg->command;
	if (($msg->prefix->prefix eq 'ChanServ!ChanServ@services.') &&
		$cmd =~ /^(?:PART|JOIN|MODE|TOPIC)$/) {
	    my $ch_name = $msg->param(0);
	    my $ch = $this->_runloop->channel($ch_name);
	    if (defined $ch) {
		$ch->remark('chanserv-controlled', 1);
	    }
	} elsif ($cmd eq RPL_ENDOFNAMES) {
	    my $ch_name = $msg->param(1);
	    my $ch = $this->_runloop->channel($ch_name);
	    if (defined $ch->names('ChanServ')) {
		$ch->remark('chanserv-controlled', 1);
	    }
	}
    }

    return $msg;
}

1;

=begin tiarra-doc

info: Freenode サポート
default: on
section: important

# 現状では ChanServ の検出以外の機能はありません。
# drop による状況の変化についてもサポートしていません。

# Channel::Rejoin では、このモジュールによってチャンネルが
# ChanServ の管理下にあると検出した時には Rejoin 動作を
# 行わなくなります。

# 設定はありません。
# また、 freenode 以外のネットワークでこのモジュールが
# 有効になっていても不都合はないはずです。

=end tiarra-doc

=cut
