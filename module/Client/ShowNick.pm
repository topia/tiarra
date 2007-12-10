# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::ShowNick;
use strict;
use warnings;
use base qw(Module);

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client')) {
	if ($type eq 'in' &&
		($msg->command eq 'WHOIS' || $msg->command eq 'WHO') &&
		    RunLoop->shared_loop->multi_server_mode_p) {
	    my $local_nick = RunLoop->shared_loop->current_nick;
	    if ($msg->param(0) eq $local_nick) {
		my $prefix = RunLoop->shared_loop->sysmsg_prefix(qw(priv system));
		map {
		    # ローカルnickとグローバルnickが食い違っていたらその旨を伝える。
		    # 接続しているネットワーク名を全部表示する
		    my $network_name = $_->network_name;
		    my $global_nick = $_->current_nick;
		    if ($global_nick ne $local_nick) {
			$io->send_message(
			    $this->construct_irc_message(Prefix => $prefix,
					   Command => 'NOTICE',
					   Params => [$local_nick,
						      "*** Your global nick in $network_name is currently '$global_nick'."]));
		    } else {
			$io->send_message(
			    $this->construct_irc_message(Prefix => $prefix,
					   Command => 'NOTICE',
					   Params => [$local_nick,
						      "*** Your global nick in $network_name is same as local nick."]));
		    }
		} RunLoop->shared_loop->networks_list;
	    }
	}
    }
    return $msg;
}

sub client_attached {
    my ($this,$client) = @_;

    if (RunLoop->shared_loop->multi_server_mode_p) {
	my $current_nick = RunLoop->shared_loop->current_nick;
	map {
	    # ローカルnickとグローバルnickが同じネットワークについてその旨を伝える。
	    # (接続しているチャンネルを表示する、程度の用途)
	    my $network_name = $_->network_name;
	    my $global_nick = $_->current_nick;
	    if ($global_nick eq $current_nick) {
		$client->send_message(
		    $this->construct_irc_message(
			Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv system)),
			Command => 'NOTICE',
			Params => [$current_nick,
				   "*** Your global nick in $network_name is same as local nick."]));
	    }
	} RunLoop->shared_loop->networks_list;
    }
}


1;
=pod
info: show network
default: off
=cut
