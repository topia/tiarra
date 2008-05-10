# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Im;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::AliasDB Tools::HTTPClient);
use Auto::AliasDB;
use Tools::HTTPClient; # >= r11345
use HTTP::Request::Common;

sub new {
  my ($class) = shift;
  my $this = $class->SUPER::new(@_);

  if ($this->config->secret) {
      # signature required
      require Digest::SHA;
  }

  my $regex = join '|', (
      (map "(?:$_)", $this->config->regex_keyword('all')),
      (map "(?i:$_)", map quotemeta, split /,/, $this->config->keyword('all')),
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

	  if ($text =~ $this->{regex}) {
	      my $full_ch_name = $msg->param(0);
	      my $url = "http://im.kayac.com/api/post/" . $this->config->user;
	      my $text = Auto::AliasDB->stdreplace(
		  $msg->prefix,
		  $this->config->format || '[tiarra][#(channel):#(nick.now)] #(text)',
		  $msg, $sender,
		  channel => $full_ch_name,
		  text => $text,
		 );
	      my $req;
	      if ($this->config->secret) {
		  $req = POST $url,
		      [ message => $text,
			sig => Digest::SHA->new(1)
			    ->add($text . $this->config->secret)->hexdigest ];
	      } else {
		  $req = POST $url,
		      [ message => $text ];
	      }
	      my $runloop = $this->_runloop;
	      Tools::HTTPClient->new(
		  Request => $req,
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

# 反応するキーワードを正規表現で指定します。
# 複数指定したい時は複数行指定してください。
-regex-keyword: (?i:fugahoge)

# 反応するキーワードを指定します。
# 複数指定したい時は,(コンマ)で区切るか、複数行指定してください。
keyword: hoge

# im.kayac.com に送るメッセージのフォーマットを指定します。
format: [tiarra][#(channel):#(nick.now)] #(text)

# im.kayac.comで登録したユーザ名を入力します。
# im.kayac.comについては http://im.kayac.com/#docs を参考にしてください。
user: username

=cut
