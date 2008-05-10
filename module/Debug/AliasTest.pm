# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Debug::AliasTest;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # サーバーからのメッセージか？
  if ($sender->isa('IrcIO::Server')) {
    # PRIVMSGか？
    if ($msg->command eq 'PRIVMSG') {
      my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

      my ($req, $str) = split(/\s+/, $msg->param(1), 2);
      if (Mask::match_array([$this->config->request('all')], $req, 1)) {
	# 一致していた。
	if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix,$get_ch_name->())) {
	  $reply_anywhere->(join('', ($this->config->prefix||''), $str, ($this->config->suffix||'')));
	}
      }
    }
  }

  return @result;
}

1;
