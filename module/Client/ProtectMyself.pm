# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::ProtectMyself;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use RunLoop;
use IRCMessage;

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my $runloop = RunLoop->shared_loop;
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
    my $runloop = RunLoop->shared_loop;
    my $current_nick = $runloop->current_nick;

    if ($runloop->multi_server_mode_p &&
	    $io->client_p &&
		$type eq 'out' &&
		    $msg->remark('message-send-by-other') &&
			defined $msg->nick &&
			    $msg->nick eq $current_nick) {
	my ($msg_tmpl, @affected);
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
	    $msg_tmpl = IRCMessage->new(
		Command => 'DUMMY', # set later
		Params => [
		    undef, # set later
		    join(' ',
			 'Nick changed',
			 $msg->nick,
			 '->',
			 $msg->param(0),
			)],
	       );
	    $set_affected_by_remark->();
	} elsif ($msg->command eq 'PART') {
	    $msg_tmpl = IRCMessage->new(
		Command => 'DUMMY', # set later
		Params => [
		    undef, # set later
		    join(' ',
			 'Part',
			 $msg->nick,
			 '('.$msg->param(1).')',
			)],
	       );
	    @affected = $msg->param(0);
	} elsif ($msg->command eq 'QUIT') {
	    $msg_tmpl = IRCMessage->new(
		Command => 'DUMMY', # set later
		Params => [
		    undef, # set later
		    join(' ',
			 'Quit',
			 $msg->nick,
			 '('.$msg->param(0).')',
			)],
	       );
	    $set_affected_by_remark->();
	} elsif ($msg->command eq 'JOIN') {
	    $msg_tmpl = IRCMessage->new(
		Command => 'DUMMY', # set later
		Params => [
		    undef, # set later
		    join(' ',
			 'Join',
			 $msg->nick,
			 'to',
			 $msg->param(0),
			)],
	       );
	    @affected = $msg->param(0);
	}
	if (@affected) {
	    my $new_msg;
	    $msg_tmpl->prefix(
		$runloop->sysmsg_prefix(qw(system fake::system)));
	    $msg_tmpl->command('NOTICE');
	    return map {
		$new_msg = $msg_tmpl->clone;
		$new_msg->param(0, $_);
		$new_msg;
	    } @affected;
	}
    }
    return $msg;
}

1;
=pod
info: IRC メッセージにちょっと変更を加えて、クライアントのバグを抑制する
default: off

# オプションはありません。

=cut
