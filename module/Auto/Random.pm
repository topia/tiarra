# -----------------------------------------------------------------------------
# $Id: Random.pm,v 1.6 2003/07/31 07:34:13 topia Exp $
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/Auto/Random.pm,v 1.12 2003/07/27 07:29:22 topia Exp $
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
