# -*- cperl -*-
# $Clovery: tiarra/module/Debug/AliasTest.pm,v 1.1 2003/03/04 09:06:21 topia Exp $
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

  # �����С�����Υ�å���������
  if ($sender->isa('IrcIO::Server')) {
    # PRIVMSG����
    if ($msg->command eq 'PRIVMSG') {
      my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

      my ($req, $str) = split(/\s+/, $msg->param(1), 2);
      if (Mask::match_array([$this->config->request('all')], $req, 1)) {
	# ���פ��Ƥ�����
	if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix,$get_ch_name->())) {
	  $reply_anywhere->(join('', ($this->config->prefix||''), $str, ($this->config->suffix||'')));
	}
      }
    }
  }

  return @result;
}

1;
