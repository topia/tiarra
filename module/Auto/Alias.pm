# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Alias;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::AliasDB Auto::Utils);
use Auto::AliasDB;
use Auto::Utils;
use Mask;

sub new {
  my $class = shift;
  my $this = $class->SUPER::new(@_);
  Auto::AliasDB::setfile($this->config->alias,
			 $this->config->alias_encoding);
  $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  if ($msg->command eq 'PRIVMSG') {

    if (Mask::match($this->config->confirm,$msg->param(1))) {
      # その人のエイリアスがあればprivで返す。
      my (undef,undef,$reply_as_priv,undef,undef)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result, 0); # Alias conversion disable.

      my $alias = Auto::AliasDB->shared->find_alias_prefix($msg->prefix);
      if (defined $alias) {
	while (my ($key,$values) = each %$alias) {
	  map {
	    $reply_as_priv->("$key: $_");
	  } @$values;
	}
      }
    }
    else {
      my (undef,undef,undef,$reply_anywhere,undef)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result, 1);

      my $msg_from_modifier_p = sub {
	  !defined $msg->prefix ||
	      Mask::match_deep([Mask::array_or_all($this->config->modifier('all'))],
			       $msg->prefix);
      };

      my ($temp) = $msg->param(1);
      $temp =~ s/^\s*(.+)\s*$/$1/;
      my ($keyword,$key,$value)
	= split(/\s+/, $temp, 3);

      if(Mask::match($this->config->get('add'),$keyword)) {
	if ($msg_from_modifier_p->() && defined $key && defined $value) {
	  if (Auto::AliasDB->shared->add_value_with_prefix($msg->prefix, $key, $value)) {
	    if (defined $this->config->added_format && $this->config->added_format ne '') {
	      $reply_anywhere->($this->config->added_format, 'key' => $key, 'value' => $value);
	    }
	  }
	}
      }
      elsif (Mask::match($this->config->get('remove'),$keyword)) {
	if ($msg_from_modifier_p->() && defined $key) {
	  my $count = Auto::AliasDB->shared->del_value_with_prefix($msg->prefix, $key, $value);
	  if ($count) {
	    if (defined $this->config->removed_format && $this->config->removed_format ne '') {
	      $reply_anywhere->($this->config->removed_format, 'key' => $key, 'value' => $value, 'count' => $count);
	    }
	  }
	}
      }
    }
  }
  return @result;
}

1;

=pod
info: ユーザエイリアス情報の管理を行ないます。
default: off

# エイリアスは基本的にname,userの二つのフィールドから成っており、
# それぞれユーザー名、ユーザーマスクを表します。

# エイリアス定義ファイルのパスと、そのエンコーディング。
# このファイルは次のようなフォーマットである。
# 1. それぞれの行は「<キー>: <値>」の形式である。
# 2. 空の行で、各ユーザーを区切る。
# 3. <値>はカンマで区切られて複数の値とされる。
#
# エイリアス定義ファイルの例:
#
# name: sample
# user: *!*sample@*.sample.net
#
# name: sample2,[sample2]
# user: *!sample2@*.sample.net,*!sample2@*.sample2.net
#
alias: alias.txt
alias-encoding: euc

# この発言をした人のエイリアスが登録されていれば、それをprivで送る。
confirm: エイリアス確認

# 「<addで指定したキーワード> user *!*user@*.user.net」のようにして情報を追加。
# 発言をした人のエイリアスが未登録だった場合は、userのみ受け付けて新規追加とする。
add: エイリアス追加

# 「<removeで指定したキーワード> name ユーザー」のようにして情報を削除。
# userを全て削除されたエイリアスは他の情報(name等)も含めて消滅する。
remove: エイリアス削除

# メッセージが追加されたときの反応を指定します。
# ランダムなメッセージを発言する際のフォーマットを指定します。
# エイリアス置換が有効です。#(nick.now)、#(channel)は
# それぞれ相手のnick、チャンネル名に置換されます。
# #(key)、#(value)は、追加されたキーと値に置換されます。
added-format: #(name|nick.now): エイリアス #(key) に #(value) を追加しました。

# メッセージが削除されたときの反応を指定します。
# added-formatで指定できるものと同じです。
removed-format: #(name|nick.now): エイリアス #(key) から #(value) を削除しました。

# エイリアスの追加や削除が許されている人。省略された場合は「*!*@*」と見做される。
modifier: *!*@*
=cut
