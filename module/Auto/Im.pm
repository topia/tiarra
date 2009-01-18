# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Im;
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

  if ($this->config->secret) {
    # signature required
    require Digest::SHA;
  }

  my $regex = join '|', (
    (map { "(?:$_)" } $this->config->regex_keyword('all')),
    (map { "(?i:\Q$_\E)" } map { split /,/ } $this->config->keyword('all')),
   );
  eval {
    $this->{regex} = qr/$regex/;
  }; if ($@) {
    $this->_runloop->notify_error($@);
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

	      my $url = "http://im.kayac.com/api/post/" . $this->config->user;
	      my $text = Auto::AliasDB->stdreplace(
		  $msg->prefix,
		  $this->config->format || '[tiarra][#(channel):#(nick.now)] #(text)',
		  $msg, $sender,
		  channel => $full_ch_name,
		  raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
		  text => $text,
		 );
	      my @data = (message => $text);
	      if ($this->config->secret) {
		  push(@data, sig => Digest::SHA->new(1)
			   ->add($text . $this->config->secret)->hexdigest);
	      } elsif ($this->config->password) {
		  push(@data, password => $this->config->password);
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
      }
  }

  return @result;
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

=cut
