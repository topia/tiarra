# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Outputz;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::AliasDB Tools::HTTPClient Auto::Utils);
use Auto::AliasDB;
use Tools::HTTPClient; # >= r11345
use Auto::Utils;
use HTTP::Request::Common;

sub new {
  my ($class) = shift;
  my $this = $class->SUPER::new(@_);

  $this->config_reload(undef);

  return $this;
}

sub config_reload {
  my ($this, $old_config) = @_;

  if (!$this->config->key) {
      die __PACKAGE__.": key must be filled.";
  }

  foreach ($this->config->channel('all')) {
      my ($dirname,$mask) = split /\s+/;
      if (!defined($dirname) || $dirname eq '' ||
	      !defined($mask) || $mask eq '') {
	  die 'Illegal definition in '.__PACKAGE__."/channel : $_\n";
      }
      push @{$this->{channels}},[$dirname,$mask];
  }
  $this->{matching_cache} = {};

  my $cmds;
  if ($this->config->commands) {
      $cmds = join('|', map quotemeta, split /\s+/, $this->config->commands);
  } else {
      $cmds = 'PRIVMSG';
  }
  $this->{commands} = qr/^$cmds$/;

  return $this;
}

## from Log::Channel
sub _mangle_string {
    my ($this, $str) = @_;

    $str =~ s/![0-9A-Z]{5}/!/;
    $str =~ s{([^-\w@#%!+&.\x80-\xff])}{
	sprintf('=%02x', unpack("C", $1));
    }ge;

    $str;
}

sub _channel_match {
    # 指定されたチャンネル名にマッチするログ保存ファイルのパターンを定義から探す。
    # 一つもマッチしなければundefを返す。
    # このメソッドは検索結果を$this->{matching_cache}に保存して、後に再利用する。
    my ($this,$channel,$chan_short,$network) = @_;

    my $cached = $this->{matching_cache}->{$channel};
    if (defined $cached) {
	if ($cached eq '') {
	    # マッチするエントリは存在しない、という結果がキャッシュされている。
	    return undef;
	}
	else {
	    return $cached;
	}
    }

    foreach my $ch (@{$this->{channels}}) {
	if (Mask::match($ch->[1],$channel)) {
	    my $name = Tools::HashTools::replace_recursive(
		$ch->[0], [{channel => $this->_mangle_string($channel),
		            channel_short => $this->_mangle_string($chan_short),
		            network => $this->_mangle_string($network)}]);

	    $this->{matching_cache}->{$channel} = $name;
	    return $name;
	}
    }
    $this->{matching_cache}->{$channel} = '';
    undef;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;

  # クライアントからのメッセージか？
  if ($sender->isa('IrcIO::Client')) {
      if ($msg->command =~ $this->{commands}) {
	  my $text = $msg->param(1);
	  my $full_ch_name = $msg->param(0);
	  my ($target, $network) = Multicast::detach($full_ch_name);
	  if (Multicast::nick_p($target)) {
	      $target = 'priv';
	      $full_ch_name = Multicast::attach($target, $network);
	  }

	  # calc size
	  my $len = $text =~ tr/\x00-\x7f\xc0-\xf7/\x00-\x7f\xc0-\xf7/;

	  my $name = $this->_channel_match($full_ch_name, $target, $network);
	  if ($name) {
	      my $url = "http://outputz.com/api/post/";
	      my @data = (key => $this->config->key,
			  uri => $name,
			  size => $len);
	      my $runloop = $this->_runloop;
	      Tools::HTTPClient->new(
		  Request => POST($url, \@data),
		 )->start(
		     Callback => sub {
			 my $stat = shift;
			 $runloop->notify_warn(__PACKAGE__." post failed: $stat")
			     unless ref($stat);
			 ## FIXME: check response (should check 'error')
		     },
		    );
	  }
      }
  }

  return $msg;
}

1;

=pod
info: チャンネルの発言文字数を outputz に送信する
default: off

# 復活の呪文。
key: some secret

# 各チャンネルのURIの設定。
# 記述された順序で検索されるので、全てのチャンネルにマッチする"*"などは最後に書かなければならない。
# フォーマットは次の通り。
# channel: <URI> (<チャンネル名> / 'priv')@<ネットワーク名>
# #(channel) はチャンネル名に、 #(channel_short) はネットワークなしの
# チャンネル名に、 #(network) はネットワーク名にそれぞれ置き換えられる。
# また、危険な文字は自動的にエスケープされる。
channel: http://irc.example.com/#(network)/#(channel_short) *

=cut
