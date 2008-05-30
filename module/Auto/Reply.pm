# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
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

our $DEFAULT_BLOCK_NAME = 'std';
our $DEFAULT_MUILTILINE_LIMIT = 10;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{config} = [];

    eval{
      $this->_load;
    };
    if( $@ )
    {
      $this->_error("$@");
    }
    return $this;
}

sub _error
{
  my $this = shift;
  my $msg  = shift;

  $this->_runloop->notify_error(__PACKAGE__." -- ".$msg);
}

sub _load {
    my $this = shift;

    my $BLOCKS_NAME = 'blocks';
    my @block_names = $this->config->get($BLOCKS_NAME, 'all');
    if( !@block_names )
    {
      @block_names = $DEFAULT_BLOCK_NAME;
      if( !$this->config->get($DEFAULT_BLOCK_NAME) )
      {
        $this->_("Both blocks: records and std block are not defined");
        return;
      }
    }

    foreach my $blockname (@block_names) {
	if( $blockname eq $BLOCKS_NAME )
	{
	  $this->_error("block name $blockname is reserved!");
	  next;
	}
	my $block = $this->config->get($blockname);
	if( !$block )
	{
	  $this->_error("block $blockname is not defined");
	  next;
	}
	if( !UNIVERSAL::isa($block, 'Configuration::Block') )
	{
	  $this->_error("$blockname isn't block!");
	  next;
	}
	push(@{$this->{config}}, {
	    mask           => [Mask::array_or_all_chan($block->mask('all'))],
	    request        => [$block->request('all')],
	    reply_format   => [$block->reply_format('all')],
	    max_reply      => $block->max_reply,
	    rate           => $block->rate,
	    count_query    => [$block->count_query('all')],
	    count_format   => [$block->count_format('all')],
	    add            => [$block->get('add', 'all')],
	    added_format   => [$block->added_format('all')],
	    remove         => [$block->remove('all')],
	    removed_format => [$block->removed_format('all')],
	    modifier       => [$block->modifier('all')],
	    use_re         => $block->use_re,
	    multivalue     => $block->multivalue,
	    multivalue_limit => $block->multivalue_limit,
	    multivalue_seq   => 0, # updated internally.
	    database       => Tools::HashDB->new(
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
		    $reply_anywhere->($block->{count_format}, 'count' => $count);
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
			    $reply_anywhere->($block->{reply_format},
					      'key' => $key,
					      'message' => $message);
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
			    $reply_anywhere->($block->{added_format}, 'key' => $key, 'message' => $param);
			}
			return $return_value->();
		    } elsif (Mask::match_deep($block->{remove}, $keyword)) {
			# 発言の削除
			# この人は削除を許可されている。
			if (defined $key) {
			    my $count = $block->{database}->del_value($key, $param);
			    $reply_anywhere->(
				$block->{removed_format},
				'key' => $key,
				'message' => $param,
				'count' => $count);
			}
			return $return_value->();
		    }
		}
	    }

	    # match
	    if (Mask::match_deep_chan($block->{mask}, $msg->prefix, $get_full_ch_name->())) {
		my $key = (_search($block, $msg->param(1), 1, $block->{rate}))[0];
		if (defined $key) {
		  my $multivalue = $block->{multivalue} || 'random';
		  if( $multivalue eq 'all' )
		  {
		    my $limit = $block->{multivalue_limit} || $DEFAULT_MUILTILINE_LIMIT;
		    my $values = $block->{database}->get_array($key);
		    if( @$values > $limit )
		    {
		      $values = [ @$values[0..$limit-1] ];
		    }
		    $reply_anywhere->($values);
		  }elsif( $multivalue eq 'seq' || $multivalue eq 'sequence' )
		  {
		    my $values = $block->{database}->get_array($key);
		    my $seq = $block->{multivalue_seq} || 0;
		    if( $seq < 0 || $seq >= @$values )
		    {
		      $seq = 0;
		    }
		    $reply_anywhere->($values->[$seq]);
		    $block->{multivalue_seq} = ($seq + 1) % @$values;
		  }else
		  {
		    my $value = $block->{database}->get_value_random($key);
		    $reply_anywhere->($value);
		  }
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
# 省略すると std を使用.
# 複数個の blocks の指定も可能.
blocks: std

std {
  # 1つの応答ブロックの定義.
  # 一応全ての項目が省略可能ではあるけれど,
  # 通常は最低限 file と file-encoding を使用する.
  # IRCで応答の追加削除等を行いたいときにはそれに更に設定を追加する形.
  # (IRC上で応答の追加削除は行うが保存はしない時に限ってfileを省略可能.)

  # 機能:
  # - 通常応答(mask)
  # - 登録数確認(count-query/mask)
  # - 反応確認(request/modifier)
  # - 反応追加(add/modifier)
  # - 反応削除(remove/modifier)
  # 通常応答以外は設定を省略することで機能を無効にできます。

  # データファイルと文字コードを指定します。
  # ファイルの中では一行に一つの"反応マスク:メッセージ"を書いて下さい。
  file: reply.txt
  file-encoding: euc

  # １つの発言で複数の反応マスクにマッチする場合, 
  # どれにマッチするかは未定義です.
  # ただ, どちらか1つにのみマッチします.

  # 同じ反応マスクに複数個のメッセージが記述してあった場合の処理.
  # multivalue: random #==> ランダムに1つ選択.
  # multivalue: all    #==> 全て返す.
  # multivalue: seq    #==> 順番に1つずつ返す.
  # 省略時及び認識できなかったときは random.
  -multivalue: random
  # 返す最大行数.
  # multivalue: all の時のみ有効.
  # (それ以外の時は1行しか返さない)
  # デフォルトは 5 行まで.
  -multivalue-limit: 5

  # 反応する人のマスク。
  # 通常応答と登録数の返答時にチェックされる。
  mask: * *!*@*
  # plum: mask: *!*@*

  # このブロックが発言に反応する確率を指定します。
  # 百分率です。省略された場合は100と見做されます。
  rate: 100

  # メッセージの登録数を返答するキーワードを指定します。
  # 省略するとこの機能は無効になります。
  # 指定したときだけこの機能が有効になります。
  # mask で許可された人(通常応答を返す人)が使えます。
  count-query: 反応登録数

  # メッセージの登録数を返答するときの反応を指定します。
  # formatで指定できるものと同じです。#(count)は登録数になります。
  # count-query を指定したときのみ必要。
  count-format: 反応は#(count)件登録されています。

  # メッセージを追加するキーワードを指定します。
  # ここで指定したキーワードを発言すると、新しいメッセージを追加します。
  # 実際の追加方法は「<addで指定したキーワード> <追加するメッセージ>」です。
  # 省略するとこの機能は無効になります。
  # 指定したときだけこの機能が有効になります。
  # modifier で許可された人だけ使えます。
  -add: 反応追加

  # 反応が追加されたときの反応を指定します。
  # formatで指定できるものと同じです。#(message)は追加されたメッセージになります。
  added-format: #(name|nick.now): #(key) に対する反応 #(message) を追加しました。

  # メッセージを削除するキーワードを指定します。
  # 実際の削除方法は「<removeで指定したキーワード> <削除するキーワード>」です。
  # 省略するとこの機能は無効になります。
  # 指定したときだけこの機能が有効になります。
  # modifier で許可された人だけ使えます。
  -remove: 反応削除

  # メッセージが削除されたときの反応を指定します。
  # formatで指定できるものと同じです。#(message)は削除されたメッセージになります。
  removed-format: #(name|nick.now): #(key) #(message;に対する反応 %s|;) を #(count) 件削除しました。

  # 反応の確認を行うためのキーワードを指定します。
  # 通常応答と違って, multivalue-limit の制限を受けずに全てのマッチした応答を返します。
  # 実際の指定方法は、「<requestで指定したキーワード> <チェックしたい発言>」です。
  # 省略するとこの機能は無効になります。
  # 指定したときだけこの機能が有効になります。
  # modifier で許可された人だけ使えます。
  request: 反応チェック

  # request に反応するときのフォーマットを指定します。
  # #(key) がキーワード、 #(message) が発言に置換されます。
  # request を指定したときのみ必要。
  reply-format: 「#(key)」という発言に「#(message)」と反応します。

  # request に反応する最大個数(反応マスクの数)を指定します。
  # (１つの反応マスクに対応するメッセージの数は制限されません。)
  # あまり大きな値を指定すると、アタックが可能になったり、ログが流れて邪魔なので注意してください。
  # 通常の反応には関与しません。また、応答の行数ではありません。
  max-reply: 5

  # 編集系コマンド, add とremove と request を許可する人。
  # 省略された場合は「* *!*@*」(全員許可)と見做します。
  modifier: * *!*@*

  # 正規表現拡張を許可するか。省略された場合は禁止します。
  use-re: 1
}
=cut
