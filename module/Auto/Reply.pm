# -*- cperl -*-
# $Clovery: tiarra/module/Auto/Reply.pm,v 1.4 2003/07/27 07:32:51 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Auto::Reply;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Auto::AliasDB::CallbackUtils Tools::HashDB);
use Auto::Utils;
use Auto::AliasDB::CallbackUtils;
use Tools::HashDB;
use Mask;

sub new {
    my ($class) = @_;
    my $this = $class->SUPER::new;
    $this->{config} = [];

    $this->_load;
    return $this;
}

sub _load {
    my $this = shift;

    my $BLOCKS_NAME = 'blocks';

    foreach my $blockname ($this->config->get($BLOCKS_NAME, 'all')) {
	die "$blockname block name is reserved!" if $blockname eq $BLOCKS_NAME;
	my $block = $this->config->get($blockname);
	die "$blockname isn't block!" unless UNIVERSAL::isa($block, 'Configuration::Block');
	push(@{$this->{config}}, {
	    mask => [Mask::array_or_all_chan($block->mask('all'))],
	    request => [$block->request('all')],
	    reply_format => [$block->reply_format('all')],
	    max_reply => $block->max_reply,
	    rate => $block->rate,
	    count_query => [$block->count_query('all')],
	    count_format => [$block->count_format('all')],
	    add => [$block->get('add', 'all')],
	    added_format => [$block->added_format('all')],
	    remove => [$block->remove('all')],
	    removed_format => [$block->removed_format('all')],
	    modifier => [$block->modifier('all')],
	    use_re => $block->use_re,
	    database => Tools::HashDB->new(
		$block->file,
		$block->file_encoding,
		$block->use_re,
		($block->ignore_comment ? undef : sub {0;})),
	});
    }
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my $return_value = sub {
	return @result;
    };

    my (undef,undef,undef,$reply_anywhere,$get_full_ch_name)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

    if ($msg->command eq 'PRIVMSG') {
	foreach my $block (@{$this->{config}}) {
	    # count : 登録数の計算
	    if (Mask::match_deep($block->{count_query}, $msg->param(1))) {
		if (Mask::match_deep_chan($block->{mask}, $msg->prefix, $get_full_ch_name->())) {
		    # 登録数を求める
		    my $count = scalar $block->{database}->keys;
		    map {
			$reply_anywhere->($_, 'count' => $count);
		    } @{$block->{count_format}};
		}
		return $return_value->();
	    }

	    my $msg_from_modifier_p = do {
		!defined $msg->prefix ||
		    Mask::match_deep_chan($block->{modifier}, $msg->prefix, $get_full_ch_name->());
	    };

	    my $tail = $msg->param(1);
	    $tail =~ s/^\s*(.*)\s*$/$1/;
	    my $keyword;
	    ($keyword, $tail) = split(/\s+/, $tail, 2);

	    if ($msg_from_modifier_p) {
		# request
		if (Mask::match_deep($block->{request}, $keyword)) {
		    # 一致する反応をリストする
		    foreach my $key (_search($block, $tail, $block->{max_reply})) {
			foreach my $message (@{$block->{database}->get_array($key)}) {
			    map {
				$reply_anywhere->($_, 'key' => $key, 'message' => $message);
			    } @{$block->{reply_format}};
			}
		    }
		    return $return_value->();
		}

		# add and remove
		if (defined $tail) {
		    my ($key, $param) = split(/\s+/, $tail, 2);
		    if (Mask::match_deep($block->{add}, $keyword)) {
			# 発言の追加
			# この人は変更を許可されている。
			if (defined $key && defined $param) {
			    $block->{database}->add_value($key, $param);
			    map {
				$reply_anywhere->($_, 'key' => $key, 'message' => $param);
			    } @{$block->{added_format}};
			}
			return $return_value->();
		    } elsif (Mask::match_deep($block->{remove}, $keyword)) {
			# 発言の削除
			# この人は削除を許可されている。
			if (defined $key) {
			    my $count = $block->{database}->del_value($key, $param);
			    map {
				$reply_anywhere->(
				    $_,
				    'key' => $key,
				    'message' => $param,
				    'count' => $count);
			    } @{$block->{removed_format}};
			}
			return $return_value->();
		    }
		}
	    }

	    # match
	    if (Mask::match_deep_chan($block->{mask}, $msg->prefix, $get_full_ch_name->())) {
		my $key = (_search($block, $msg->param(1), 1, $block->{rate}))[0];
		if (defined $key) {
		    $reply_anywhere->($block->{database}->get_value_random($key));
		}
	    }
	}
    }

    return @result;
}

sub _search {
    # key を検索する関数。

    # $block	: 検索対象のブロック
    # $key	: 検索するキー
    # $count	: 最大発見個数。省略すると全て。
    # $rate	: 発見してもランダムに忘れる(笑)確率(パーセント)。省略すると100%。
    my ($block, $str, $count, $rate) = @_;

    my @masks;
    foreach my $mask ($block->{database}->keys) { 
	if (Mask::match_array([$mask], $str, 1, $block->{use_re}, 0)) {
	    # match
	    if (!defined $rate || (int(rand() * hex('0xffffffff')) % 100) < $rate) {
		push(@masks, $mask);
		if (defined $count && $count <= scalar(@masks)) {
		    # $count 分発見したので終了。
		    last;
		}
	    }
	}
    }

    return @masks;
}

1;

=pod
info: 特定の発言に反応して発言をします。
default: off

# Auto::Aliasを有効にしていれば、エイリアス置換を行ないます。

# 使用するブロックの定義。
blocks: std

std {
  # データファイルと文字コードを指定します。
  # ファイルの中では一行に一つの"反応:メッセージ"を書いて下さい。
  file: reply.txt
  file-encoding: euc

  # 反応チェックを行うキーワードを指定します。
  # 実際の指定方法は、「<requestで指定したキーワード> <チェックしたい発言>」です。
  request: 反応チェック

  # request に反応するときのフォーマットを指定します。
  # #(key) がキーワード、 #(message) が発言に置換されます。
  reply-format: 「#(key)」という発言に「#(message)」と反応します。

  # request に反応する最大個数を指定します。
  # あまり大きな値を指定すると、アタックが可能になったり、ログが流れて邪魔なので注意してください。
  max-reply: 5

  # メッセージの登録数を返答するキーワードを指定します。
  count-query: 反応登録数

  # メッセージの登録数を返答するときの反応を指定します。
  # formatで指定できるものと同じです。#(count)は登録数になります。
  count-format: 反応は#(count)件登録されています。

  # 反応する人のマスク。
  mask: * *!*@*
  # plum: mask: *!*@*

  # 反応が追加されたときの反応を指定します。
  # formatで指定できるものと同じです。#(message)は追加されたメッセージになります。
  added-format: #(name|nick.now): #(key) に対する反応 #(message) を追加しました。

  # メッセージが削除されたときの反応を指定します。
  # formatで指定できるものと同じです。#(message)は削除されたメッセージになります。
  removed-format: #(name|nick.now): #(key) #(message;に対する反応 %s|;) を #(count) 件削除しました。

  # 発言に反応する確率を指定します。百分率です。省略された場合は100と見做されます。
  rate: 100

  # メッセージを追加するキーワードを指定します。
  # ここで指定したキーワードを発言すると、新しいメッセージを追加します。
  # 実際の追加方法は「<addで指定したキーワード> <追加するメッセージ>」です。
  add: 反応追加

  # メッセージを削除するキーワードを指定します。
  # 実際の削除方法は「<removeで指定したキーワード> <削除するキーワード>」です。
  remove: 反応削除

  # addとremoveを許可する人。省略された場合は「*!*@*」と見做します。
  modifier: *!*@*

  # 正規表現拡張を許可するか。省略された場合は許可します。
  use-re: 1
}
=cut
