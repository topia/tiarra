# -*- cperl -*-
# $Clovery: tiarra/module/Auto/Response.pm,v 1.7 2003/07/27 07:09:52 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Auto::Response;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Auto::AliasDB::CallbackUtils Tools::GroupDB);
use Auto::Utils;
use Auto::AliasDB::CallbackUtils;
use Tools::GroupDB;
use Mask;
use Multicast;

sub new {
  my ($class) = @_;
  my $this = $class->SUPER::new;
  $this->{database} = Tools::GroupDB->new($this->config->file, 'pattern', $this->config->charset, 1, 1);

  return $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # サーバーからのメッセージか？
  if ($sender->isa('IrcIO::Server')) {
    # PRIVMSGか？
    if ($msg->command eq 'PRIVMSG') {
      my @matches = $this->{database}->find_groups_with_primary($msg->param(1));
      if (@matches) {
	my ($callbacks) = [];
	Auto::AliasDB::CallbackUtils::register_extcallbacks($callbacks, $msg, $sender);
	my (undef,undef,undef,$reply_anywhere,$get_full_ch_name)
	  = Auto::Utils::generate_reply_closures($msg, $sender, \@result, undef, $callbacks);

	if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix, $get_full_ch_name->())) {
	  # 一致していた。
	  foreach my $match (@matches) {
	    # maskが一致しなければ実行しない。飛ばす。
	    my $mask = Tools::GroupDB::get_array($match, 'mask');
	    next if ($mask && !Mask::match_deep_chan($mask, $msg->prefix, $get_full_ch_name->()));
	    # rate以下ならば実行しない。飛ばす。
	    my $rate = Tools::GroupDB::get_value($match, 'rate');
	    next unless !defined($rate) || (int(rand(100)) < $rate);
	    $reply_anywhere->(Tools::GroupDB::get_value_random($match, 'response'));
	  }
	}
      }
    }
  }

  return @result;
}

1;

=pod
info: データファイルの指定にしたがって反応する。
default: off

# 大量の反応データを定義するのに向いています。

# データファイルのフォーマット
# | pattern: re:^(こん(に)?ちは)
# | rate: 90
# | mask: * *!*@*
# | #plum: mask: *!*@*
# | response: こんにちは。
# | response: いらっしゃいませ。
# |
# | pattern: おやすみ
# | rate: 20
# | response: おやすみなさい。
# patternは一行しか書けません。(手抜き
# maskもrateも省略できます。省略した場合はmaskは全員、rateは100となります。
# responseは複数書いておけばランダムに選択されます。

# データファイル
file: response.txt

# 文字コード
charset: euc

# 使用を許可する人&チャンネルのマスク。
mask: * *!*@*
# plum: mask: +*!*@*
=cut
