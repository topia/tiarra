# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 phonohawk <phonohawk@ps.sakura.ne.jp>. all rights reserved.
# copyright (C) 2004-2005 Topia <topia@clovery.jp>. all rights reserved.
package System::PrivTranslator;
use strict;
use warnings;
use base qw(Module);
use Multicast;

sub NICK_CACHE_EXPIRE_TIME (){ 5 * 60 }
sub NICK_CACHE_EXPIRE_KEY (){ __PACKAGE__ . '/nick-avails' }
sub REMARK_NICK_ATTACHED_KEY (){ __PACKAGE__ . '/nick-attached' }

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    if ($sender->isa('IrcIO::Server') &&
	    defined $msg->nick) {

	my $cmd = $msg->command;
	if (($cmd eq 'PRIVMSG' || $cmd eq 'NOTICE') &&
		!Multicast::channel_p($msg->param(0))) {
	    $msg->remark(REMARK_NICK_ATTACHED_KEY, [$msg->nick,
						    $sender->network_name]);
	    $msg->nick(Multicast::attach($msg->nick, $sender->network_name));
	}
    }
    $msg;
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client') &&
	    $type eq 'out') {
	my $remark = $io->remark(NICK_CACHE_EXPIRE_KEY) || {};
	if (my $info = $msg->remark(REMARK_NICK_ATTACHED_KEY)) {
	    $remark->{$info->[1]}->{$info->[0]} = time() + NICK_CACHE_EXPIRE_TIME;
	    $io->remark(NICK_CACHE_EXPIRE_KEY, $remark);
	} elsif ($msg->command eq 'NICK') {
	    if (defined $msg->generator) {
		if ($msg->generator->can('network_name')) {
		    my $network_name = $msg->generator->network_name;
		    my $nick = $msg->nick;
		    my $time = delete $remark->{$network_name}->{$nick};
		    if (defined $time &&
			    $time >= time()) {
			my $nick_to = $msg->param(0);

			# update expire place
			$remark->{$network_name}->{$nick_to} = $time;

			# duplicate nick message
			my $new_msg = $msg->clone;
			$new_msg->nick(Multicast::attach($nick, $network_name));
			$new_msg->param(0, Multicast::attach($nick_to, $network_name));
			return ($msg, $new_msg);
		    }
		}
	    }
	}
    }
    return $msg;
}


1;
=pod
info: クライアントからの個人的なprivが相手に届かなくなる現象を回避する。
default: off
section: important

# このモジュールは個人宛てのprivmsgの送信者のnickにネットワーク名を付加します。
# また、最後に声をかけられてから5分以内の nick 変更をクライアントに伝えます。
# 設定項目はありません。
=cut
