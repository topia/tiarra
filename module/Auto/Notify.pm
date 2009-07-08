# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Notify;
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

  my $regex = join '|', (
    (map { "(?:$_)" } $this->config->regex_keyword('all')),
    (map { "(?i:\Q$_\E)" } map { split /,/ } $this->config->keyword('all')),
   );
  eval {
    $this->{regex} = qr/$regex/;
  }; if ($@) {
    $this->_runloop->notify_error($@);
  }

  $this->{blocks} = [];
  foreach my $blockname (map {split /\s+/} $this->config->blocks('all')) {
      my $block = $this->config->get($blockname, 'block');
      if (!defined $block) {
	  die "not found block: $blockname";
      }
      my $type = $block->type;
      if (!defined $type) {
	  die "type definition not found in block";
      }
      my $meth = $this->can('config_'.$type);
      if (!defined $meth) {
	  die "unknown type: $type";
      }
      $this->$meth($block);
      push(@{$this->{blocks}}, $block);
  }

  return $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # サーバーからのメッセージか？
  if ($sender->isa('IrcIO::Server')) {
      # PRIVMSGか？
      if ($msg->command eq 'PRIVMSG') {
	  my $text = $msg->param(1);
	  my $full_ch_name = $msg->param(0);

	  if ($text =~ $this->{regex} && Mask::match_deep_chan(
	      [Mask::array_or_all_chan($this->config->mask('all'))],
	      $msg->prefix,$full_ch_name)) {

	      foreach my $block (@{$this->{blocks}}) {
		  my $type = $block->type;
		  my $meth = $this->can('send_'.$type);
		  eval {
		      $this->$meth($block, $text, $msg, $sender, $full_ch_name);
		  }; if ($@) {
		      $this->_runloop->notify_warn(__PACKAGE__." send failed: $@");
		  }
	      }

	  }
      }
  }

  return @result;
}

sub config_im_kayac {
    my ($this, $config) = @_;

    if ($config->secret) {
	# signature required
	require Digest::SHA;
    }

    1;
}

sub send_im_kayac {
    my ($this, $config, $text, $msg, $sender, $full_ch_name) = @_;

    my $url = "http://im.kayac.com/api/post/" . $config->user;
    $text = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->format || $this->config->format || '[tiarra][#(channel):#(nick.now)] #(text)',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    my @data = (message => $text);
    if ($config->secret) {
	push(@data, sig => Digest::SHA->new(1)
		 ->add($text . $config->secret)->hexdigest);
    } elsif ($config->password) {
	push(@data, password => $config->password);
    }
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


sub config_prowl {
    my ($this, $config) = @_;

    require Crypt::SSLeay; # https support
    require URI;

    my $url = URI->new("https://prowl.weks.net/publicapi/verify");
    $url->query_form(apikey => $config->apikey);
    my $runloop = $this->_runloop;
    Tools::HTTPClient->new(
	Request => GET($url->as_string()),
       )->start(
	   Callback => sub {
	       my $stat = shift;
	       $runloop->notify_warn(__PACKAGE__." verify failed: $stat")
		   unless ref($stat);
	       ## FIXME: check response (should check 'error')
	   },
	  );
}

sub send_prowl {
    my ($this, $config, $text, $msg, $sender, $full_ch_name) = @_;

    my $url = URI->new("https://prowl.weks.net/publicapi/add");
    $text = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->format || $this->config->format || '[tiarra][#(channel):#(nick.now)] #(text)',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    my @data = (apikey => $config->apikey,
		priority => $config->priority || 0,
		application => $config->application || 'tiarra',
		event => $config->event || 'keyword',
		description => $text);
    $url->query_form(@data);

    my $runloop = $this->_runloop;
    Tools::HTTPClient->new(
	Request => GET($url->as_string()),
       )->start(
	   Callback => sub {
	       my $stat = shift;
	       $runloop->notify_warn(__PACKAGE__." send failed: $stat")
		   unless ref($stat);
	       ## FIXME: check response (should check 'error')
	   },
	  );
}

1;

=pod
info: 名前が呼ばれると、その発言をim.kayac.comに送信する
default: off

# 反応する人のマスクを指定します。
# 省略すると全員に反応します。
mask: * *!*@*

# 反応するキーワードを正規表現で指定します。
# 複数指定したい時は複数行指定してください。
-regex-keyword: (?i:fugahoge)

# 反応するキーワードを指定します。
# 複数指定したい時は,(コンマ)で区切るか、複数行指定してください。
keyword: hoge

# im.kayac.com に送るメッセージのフォーマットを指定します。
# デフォルト値: [tiarra][#(channel):#(nick.now)] #(text)
# #(channel) のかわりに #(raw_channel) を利用するとネットワーク名がつきません。
format: [tiarra][#(channel):#(nick.now)] #(text)

# 使用するブロックを指定します
-blocks: im prowl

im {

# 通知先のタイプを指定します。
type: im_kayac

# im.kayac.comで登録したユーザ名を入力します。
# im.kayac.comについては http://im.kayac.com/#docs を参考にしてください。
user: username

# im.kayac.comで秘密鍵認証を選択した場合は設定してください。
# 省略すると認証なしになります。
-secret: some secret

# im.kayac.comでパスワード認証を選択した場合は設定してください。
# 省略すると認証なしになります。
# secret と両方指定した場合は secret が優先されています。
-password: some password

}

prowl {

# 通知先のタイプを指定します。
type: prowl

# 通知先ごとにフォーマットを指定できます。
# この例では先頭に時刻を追加しています。
-format: #(date:%H:%M:%S) [#(channel):#(nick.now)] #(text)

# Prowl で表示された apikey を入力します。
# Prowl については http://prowl.weks.net/ を参考にしてください。
-apikey: XXXXXX

# http://forums.cocoaforge.com/viewtopic.php?f=45&t=20339
priority: 0
application: tiarra
event: keyword

}


=cut
