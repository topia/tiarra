# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Random;
use strict;
use warnings;
use Unicode::Japanese;
use base qw(Module);
use Module::Use qw(Auto::Utils Tools::FileCache);
use Auto::Utils;
use Tools::FileCache;
use Mask;

sub new {
  my ($class) = @_;
  my $this = $class->SUPER::new;
  $this->{config} = [];

  $this->_load();
  return $this;
}

sub _load {
  my ($this) = @_;

  my ($BLOCKS_NAME) = 'blocks';

  foreach my $blockname ($this->config->get($BLOCKS_NAME, 'all')) {
    die "$blockname block name is reserved!" if $blockname eq $BLOCKS_NAME;
    my $block = $this->config->get($blockname);
    die "$blockname isn't block!" unless UNIVERSAL::isa($block, 'Configuration::Block');
    push(@{$this->{config}},
	 {
	  mask => [Mask::array_or_all_chan($block->mask('all'))],
	  request => [$block->request('all')],
	  rate => $block->rate,
	  format => [$block->format('all')],
	  count_query => [$block->count_query('all')],
	  count_format => [$block->count_format('all')],
	  add => [$block->get('add', 'all')],
	  added_format => [$block->added_format('all')],
	  remove => [$block->remove('all')],
	  removed_format => [$block->removed_format('all')],
	  modifier => [$block->modifier('all')],
	  database => Tools::FileCache->shared->register($block->file,
							 'std',
							 $block->file_encoding),
	 });
  }
}

sub destruct {
  my ($this) = @_;

  map {
    $_->{database}->unregister();
  } @{$this->{config}};

  return $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  my (undef,undef,undef,$reply_anywhere,$get_full_ch_name)
    = Auto::Utils::generate_reply_closures($msg,$sender,\@result);

  if ($msg->command eq 'PRIVMSG') {
    foreach my $block (@{$this->{config}}) {
      if (Mask::match_deep($block->{request}, $msg->param(1))) {
	if (Mask::match_deep_chan($block->{mask}, $msg->prefix, $get_full_ch_name->())) {
	  # ランダムな発言を行なう。
	  my $rate_rand = int(rand() * hex('0xffffffff')) % 100;
	  if ($rate_rand < ($block->{rate} || 100)) {
	    my $reply_str = $block->{database}->get_value() || undef;
	    map {
	      $reply_anywhere->($_, 'message' => $reply_str);
	    } @{$block->{format}};
	  }
	}
      } elsif (Mask::match_deep($block->{count_query}, $msg->param(1))) {
	if (Mask::match_deep_chan($block->{mask}, $msg->prefix, $get_full_ch_name->())) {
	  # 登録数を求める
	  my $count = $block->{database}->length();
	  map {
	    $reply_anywhere->($_, 'count' => $count);
	  } @{$block->{count_format}};
	}
      } else {
	my $msg_from_modifier_p = sub {
	  !defined $msg->prefix ||
	    Mask::match_deep_chan($block->{modifier}, $msg->prefix, $get_full_ch_name->());
	};
	my ($keyword,$param) = $msg->param(1) =~ /^\s*(.+?)\s+(.+?)\s*$/;
	if (defined $keyword && defined $param) {
	  if (Mask::match_deep($block->{add}, $keyword) &&
	      $msg_from_modifier_p->()) {
	    # 発言の追加
	    # この人は変更を許可されている。
	    if ($param ne '') {
	      $block->{database}->add_value($param);
	      map {
		$reply_anywhere->($_, 'message' => $param);
	      } @{$block->{added_format}};
	    }
	  }
	} elsif (Mask::match_deep($block->{remove}, $keyword) &&
		 $msg_from_modifier_p->()) {
	  # 発言の削除
	  # この人は削除を許可されている。
	  my $count = $block->{database}->del_value($param);
	  map {
	    $reply_anywhere->($_, 'message' => $param, 'count' => $count);
	  } @{$block->{removed_format}};
	}
      }
    }
  }

  return @result;
}

1;

=pod
info: 特定の発言に反応してランダムな発言をします。
default: off

# Auto::Aliasを有効にしていれば、エイリアス置換を行ないます。

# 使用するブロックの定義。
blocks: wimikuji

wimikuji {
  # ランダムに発言するメッセージの書かれたファイルと、その文字コードを指定します。
  # ファイルの中では一行に一つのメッセージを書いて下さい。
  file: random.txt
  file-encoding: euc

  # 反応する発言を表すマスクを指定します。
  request: ゐみくじ

  # メッセージの登録数を返答するキーワードを指定します。
  count-query: ゐみくじ登録数

  # メッセージの登録数を返答するときの反応を指定します。
  # formatで指定できるものと同じです。#(count)は登録数になります。
  count-format: ゐみくじは#(count)件登録されています。

  # ランダムなメッセージを発言する際のフォーマットを指定します。
  # エイリアス置換が有効です。#(message)、#(nick.now)、#(channel)は
  # それぞれメッセージ内容、相手のnick、チャンネル名に置換されます。
  # 何も登録されていないときのために、#(message|;無登録)のように指定すると良いでしょう。
  format: #(name|nick.now)の運命は#(message)

  # 反応する人のマスク。
  mask: * *!*@*
  # plum: mask: *!*@*

  # メッセージが追加されたときの反応を指定します。
  # formatで指定できるものと同じです。#(message)は追加されたメッセージになります。
  added-format: #(name|nick.now): ゐみくじ #(message) を追加しました。

  # メッセージが削除されたときの反応を指定します。
  # formatで指定できるものと同じです。#(message)は削除されたメッセージになります。
  removed-format: #(name|nick.now): ゐみくじ #(message) を削除しました。

  # 発言に反応する確率を指定します。百分率です。省略された場合は100と見做されます。
  rate: 100

  # メッセージを追加するキーワードを指定します。
  # ここで指定したキーワードを発言すると、新しいメッセージを追加します。
  # 実際の追加方法は「<addで指定したキーワード> <追加するメッセージ>」です。
  add: ゐみくじ追加

  # メッセージを削除するキーワードを指定します。
  # 実際の削除方法は「<removeで指定したキーワード> <削除するキーワード>」です。
  remove: ゐみくじ削除

  # addとremoveを許可する人。省略された場合は誰も変更できません。
  modifier: * *!*@*
  # plum: modifier: *!*@*
}
=cut
