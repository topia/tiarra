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
	  # �������ȯ����Ԥʤ���
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
	  # ��Ͽ�������
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
	    # ȯ�����ɲ�
	    # ���οͤ��ѹ�����Ĥ���Ƥ��롣
	    if ($param ne '') {
	      $block->{database}->add_value($param);
	      map {
		$reply_anywhere->($_, 'message' => $param);
	      } @{$block->{added_format}};
	    }
	  }
	} elsif (Mask::match_deep($block->{remove}, $keyword) &&
		 $msg_from_modifier_p->()) {
	  # ȯ���κ��
	  # ���οͤϺ������Ĥ���Ƥ��롣
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
info: �����ȯ����ȿ�����ƥ������ȯ���򤷤ޤ���
default: off

# Auto::Alias��ͭ���ˤ��Ƥ���С������ꥢ���ִ���Ԥʤ��ޤ���

# ���Ѥ���֥�å��������
blocks: wimikuji

wimikuji {
  # �������ȯ�������å������ν񤫤줿�ե�����ȡ�����ʸ�������ɤ���ꤷ�ޤ���
  # �ե��������Ǥϰ�Ԥ˰�ĤΥ�å�������񤤤Ʋ�������
  file: random.txt
  file-encoding: euc

  # ȿ������ȯ����ɽ���ޥ�������ꤷ�ޤ���
  request: ��ߤ���

  # ��å���������Ͽ�����������륭����ɤ���ꤷ�ޤ���
  count-query: ��ߤ�����Ͽ��

  # ��å���������Ͽ������������Ȥ���ȿ������ꤷ�ޤ���
  # format�ǻ���Ǥ����Τ�Ʊ���Ǥ���#(count)����Ͽ���ˤʤ�ޤ���
  count-format: ��ߤ�����#(count)����Ͽ����Ƥ��ޤ���

  # ������ʥ�å�������ȯ������ݤΥե����ޥåȤ���ꤷ�ޤ���
  # �����ꥢ���ִ���ͭ���Ǥ���#(message)��#(nick.now)��#(channel)��
  # ���줾���å��������ơ�����nick�������ͥ�̾���ִ�����ޤ���
  # ������Ͽ����Ƥ��ʤ��Ȥ��Τ���ˡ�#(message|;̵��Ͽ)�Τ褦�˻��ꤹ����ɤ��Ǥ��礦��
  format: #(name|nick.now)�α�̿��#(message)

  # ȿ������ͤΥޥ�����
  mask: * *!*@*
  # plum: mask: *!*@*

  # ��å��������ɲä��줿�Ȥ���ȿ������ꤷ�ޤ���
  # format�ǻ���Ǥ����Τ�Ʊ���Ǥ���#(message)���ɲä��줿��å������ˤʤ�ޤ���
  added-format: #(name|nick.now): ��ߤ��� #(message) ���ɲä��ޤ�����

  # ��å�������������줿�Ȥ���ȿ������ꤷ�ޤ���
  # format�ǻ���Ǥ����Τ�Ʊ���Ǥ���#(message)�Ϻ�����줿��å������ˤʤ�ޤ���
  removed-format: #(name|nick.now): ��ߤ��� #(message) �������ޤ�����

  # ȯ����ȿ�������Ψ����ꤷ�ޤ���ɴʬΨ�Ǥ�����ά���줿����100�ȸ�������ޤ���
  rate: 100

  # ��å��������ɲä��륭����ɤ���ꤷ�ޤ���
  # �����ǻ��ꤷ��������ɤ�ȯ������ȡ���������å��������ɲä��ޤ���
  # �ºݤ��ɲ���ˡ�ϡ�<add�ǻ��ꤷ���������> <�ɲä����å�����>�פǤ���
  add: ��ߤ����ɲ�

  # ��å������������륭����ɤ���ꤷ�ޤ���
  # �ºݤκ����ˡ�ϡ�<remove�ǻ��ꤷ���������> <������륭�����>�פǤ���
  remove: ��ߤ������

  # add��remove����Ĥ���͡���ά���줿����ï���ѹ��Ǥ��ޤ���
  modifier: * *!*@*
  # plum: modifier: *!*@*
}
=cut
