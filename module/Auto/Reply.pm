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
	    # count : ��Ͽ���η׻�
	    if (Mask::match_deep($block->{count_query}, $msg->param(1))) {
		if (Mask::match_deep_chan($block->{mask}, $msg->prefix, $get_full_ch_name->())) {
		    # ��Ͽ�������
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
		    # ���פ���ȿ����ꥹ�Ȥ���
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
			# ȯ�����ɲ�
			# ���οͤ��ѹ�����Ĥ���Ƥ��롣
			if (defined $key && defined $param) {
			    $block->{database}->add_value($key, $param);
			    map {
				$reply_anywhere->($_, 'key' => $key, 'message' => $param);
			    } @{$block->{added_format}};
			}
			return $return_value->();
		    } elsif (Mask::match_deep($block->{remove}, $keyword)) {
			# ȯ���κ��
			# ���οͤϺ������Ĥ���Ƥ��롣
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
    # key �򸡺�����ؿ���

    # $block	: �����оݤΥ֥�å�
    # $key	: �������륭��
    # $count	: ����ȯ���Ŀ�����ά��������ơ�
    # $rate	: ȯ�����Ƥ�������˺���(��)��Ψ(�ѡ������)����ά�����100%��
    my ($block, $str, $count, $rate) = @_;

    my @masks;
    foreach my $mask ($block->{database}->keys) { 
	if (Mask::match_array([$mask], $str, 1, $block->{use_re}, 0)) {
	    # match
	    if (!defined $rate || (int(rand() * hex('0xffffffff')) % 100) < $rate) {
		push(@masks, $mask);
		if (defined $count && $count <= scalar(@masks)) {
		    # $count ʬȯ�������Τǽ�λ��
		    last;
		}
	    }
	}
    }

    return @masks;
}

1;

=pod
info: �����ȯ����ȿ������ȯ���򤷤ޤ���
default: off

# Auto::Alias��ͭ���ˤ��Ƥ���С������ꥢ���ִ���Ԥʤ��ޤ���

# ���Ѥ���֥�å��������
blocks: std

std {
  # �ǡ����ե������ʸ�������ɤ���ꤷ�ޤ���
  # �ե��������Ǥϰ�Ԥ˰�Ĥ�"ȿ��:��å�����"��񤤤Ʋ�������
  file: reply.txt
  file-encoding: euc

  # ȿ�������å���Ԥ�������ɤ���ꤷ�ޤ���
  # �ºݤλ�����ˡ�ϡ���<request�ǻ��ꤷ���������> <�����å�������ȯ��>�פǤ���
  request: ȿ�������å�

  # request ��ȿ������Ȥ��Υե����ޥåȤ���ꤷ�ޤ���
  # #(key) ��������ɡ� #(message) ��ȯ�����ִ�����ޤ���
  reply-format: ��#(key)�פȤ���ȯ���ˡ�#(message)�פ�ȿ�����ޤ���

  # request ��ȿ���������Ŀ�����ꤷ�ޤ���
  # ���ޤ��礭���ͤ���ꤹ��ȡ������å�����ǽ�ˤʤä��ꡢ����ή��Ƽ���ʤΤ���դ��Ƥ���������
  max-reply: 5

  # ��å���������Ͽ�����������륭����ɤ���ꤷ�ޤ���
  count-query: ȿ����Ͽ��

  # ��å���������Ͽ������������Ȥ���ȿ������ꤷ�ޤ���
  # format�ǻ���Ǥ����Τ�Ʊ���Ǥ���#(count)����Ͽ���ˤʤ�ޤ���
  count-format: ȿ����#(count)����Ͽ����Ƥ��ޤ���

  # ȿ������ͤΥޥ�����
  mask: * *!*@*
  # plum: mask: *!*@*

  # ȿ�����ɲä��줿�Ȥ���ȿ������ꤷ�ޤ���
  # format�ǻ���Ǥ����Τ�Ʊ���Ǥ���#(message)���ɲä��줿��å������ˤʤ�ޤ���
  added-format: #(name|nick.now): #(key) ���Ф���ȿ�� #(message) ���ɲä��ޤ�����

  # ��å�������������줿�Ȥ���ȿ������ꤷ�ޤ���
  # format�ǻ���Ǥ����Τ�Ʊ���Ǥ���#(message)�Ϻ�����줿��å������ˤʤ�ޤ���
  removed-format: #(name|nick.now): #(key) #(message;���Ф���ȿ�� %s|;) �� #(count) �������ޤ�����

  # ȯ����ȿ�������Ψ����ꤷ�ޤ���ɴʬΨ�Ǥ�����ά���줿����100�ȸ�������ޤ���
  rate: 100

  # ��å��������ɲä��륭����ɤ���ꤷ�ޤ���
  # �����ǻ��ꤷ��������ɤ�ȯ������ȡ���������å��������ɲä��ޤ���
  # �ºݤ��ɲ���ˡ�ϡ�<add�ǻ��ꤷ���������> <�ɲä����å�����>�פǤ���
  add: ȿ���ɲ�

  # ��å������������륭����ɤ���ꤷ�ޤ���
  # �ºݤκ����ˡ�ϡ�<remove�ǻ��ꤷ���������> <������륭�����>�פǤ���
  remove: ȿ�����

  # add��remove����Ĥ���͡���ά���줿���ϡ�*!*@*�פȸ������ޤ���
  modifier: *!*@*

  # ����ɽ����ĥ����Ĥ��뤫����ά���줿���ϵ��Ĥ��ޤ���
  use-re: 1
}
=cut
