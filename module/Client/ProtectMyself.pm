# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::ProtectMyself;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use Auto::AliasDB;
use Tiarra::Utils;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my $runloop = $this->_runloop;
    my $current_nick = $runloop->current_nick;

    if ($runloop->multi_server_mode_p &&
	    $sender->isa('IrcIO::Server') &&
		defined $msg->nick &&
		    $msg->nick eq $current_nick) {
	if ($msg->command =~ /^(NICK|QUIT|PART)$/) {
	    $msg->remark(__PACKAGE__ . '/network-name', $sender->network_name);
	}
    }
    return $msg;
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;
    my $runloop = $this->_runloop;
    my $current_nick = $runloop->current_nick;

    if ($runloop->multi_server_mode_p &&
	    $io->client_p &&
		$type eq 'out' &&
		    $msg->remark('message-send-by-other') &&
			defined $msg->nick &&
			    $msg->nick eq $current_nick) {
	my ($msg_tmpl, %additional_replaces, @affected);
	my $attach_for_client = sub {
	    my $network_name = $msg->remark(__PACKAGE__ . '/network-name');
	    $network_name = $runloop->default_network
		unless defined $network_name;
	    return map {
		Multicast::attach_for_client($_, $network_name);
	    } @_;
	};
	my $set_affected_by_remark = sub {
	    if (defined $msg->remark('affected-channels')) {
		@affected = $attach_for_client->(
		    @{$msg->remark('affected-channels')});
	    } else {
		@affected = $runloop->current_nick;
	    }
	};
	if ($msg->command eq 'NICK') {
	    $msg_tmpl = utils->get_first_defined(
		$this->config->nick_format,
		'Nick changed #(nick.now) -> #(nick.new)');
	    $additional_replaces{'nick.new'} = $msg->param(0);
	    $set_affected_by_remark->();
	} elsif ($msg->command eq 'PART') {
	    $msg_tmpl = utils->get_first_defined(
		$this->config->part_format,
		'Part #(nick.now) (#(message)) from #(target)');
	    $additional_replaces{'message'} = $msg->param(1);
	    @affected = $msg->param(0);
	} elsif ($msg->command eq 'QUIT') {
	    $msg_tmpl = utils->get_first_defined(
		$this->config->quit_format,
		'Quit #(nick.now) (#(message))');
	    $additional_replaces{'message'} = $msg->param(0);
	    $set_affected_by_remark->();
	} elsif ($msg->command eq 'JOIN') {
	    $msg_tmpl = utils->get_first_defined(
		$this->config->join_format,
		'Join #(nick.now) (#(prefix.now)) to #(target)');
	    @affected = $msg->param(0);
	}
	if (@affected) {
	    my $aliasdb = Auto::AliasDB->shared;
	    my $msg_skel = $this->construct_irc_message(
		Prefix => $runloop->sysmsg_prefix(qw(system fake::system)),
		Command => 'NOTICE',
		Params => [undef, undef]);
	    return map {
		my $new_msg = $msg_skel->clone;
		$new_msg->param(0, $_);
		$new_msg->param(1, $aliasdb->stdreplace(
		    $msg->prefix, $msg_tmpl, $msg, undef,
		    target => $_,
		    %additional_replaces,
		   ));
		$new_msg;
	    } @affected;
	}
    }
    return $msg;
}

1;
=pod
info: 意図せず自分のニックが変わってしまうのを防止する
default: off

# {nick,part,quit,join}-format: それぞれのメッセージのフォーマットを指定します。
# {nick,user,host,prefix}.now などはどこでも使えます。
# そのほかには
#  target   : 表示するチャンネル(またはニック)。
#  nick.new : nick-format のみ。新しいニック。
#  message  : part と quit 。メッセージ。

nick-format: Nick changed #(nick.now) -> #(nick.new)
part-format: Part #(nick.now) (#(message)) from #(target)
quit-format: Quit #(nick.now) (#(message))
join-format: Join #(nick.now) (#(prefix.now)) to #(target)

=cut
