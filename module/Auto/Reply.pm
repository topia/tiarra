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
	    my $key = (_search($block, $msg->param(1), 1, $block->{rate}))[0];
	    if (defined $key) {
		$reply_anywhere->($block->{database}->get_value_random($key));
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
