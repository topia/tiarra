# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Channel::Join::Invite;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Multicast;
use Mask;

sub message_arrived {
  my ($this, $msg, $sender) = @_;
  my @result = ($msg);

  if ($sender->isa('IrcIO::Server')) {
    if ($msg->command eq 'INVITE') {
      my ($callbacks) = [];
      Auto::AliasDB::CallbackUtils::register_extcallbacks($callbacks, $msg, $sender);
      my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg, $sender, \@result, undef, $callbacks, 1);
      if (Multicast::channel_p($get_ch_name->())) {
	if (Mask::match_deep_chan([$this->config->mask('all')], $msg->prefix, $get_ch_name->())) {
	  # match.
	  $sender->
	    send_message(IRCMessage->new(
					 Command => 'JOIN',
					 Params => [$get_ch_name->()]
					));
	  foreach my $reply ($this->config->message('all')) {
	    $reply_anywhere->($reply);
	  }
	}
      }
    }
  }

  return @result;
};


1;

=pod
info: 招待されたらそのチャンネルに入る。
default: off

# 許可するユーザ/チャンネルのマスク。
mask: * *!*@*
# plum: *!*@*

# 招待されたチャンネルに流すメッセージのフォーマット。
-message: こんばんわ〜。
=cut
