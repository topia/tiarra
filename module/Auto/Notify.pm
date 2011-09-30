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

sub strip_mirc_formatting {
    my ($this, $text) = @_;
    $text =~ s/(?:\x03\d\d?(?:,\d\d?)?|[\x0f\x02\x1f\x16])//g;
    $text;
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
	text => $this->strip_mirc_formatting($text),
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
	       if (!ref($stat)) {
		   $runloop->notify_warn(__PACKAGE__." im.kayac.com: post failed: $stat");
	       } elsif ($stat->{Content} !~ /"result":\s*"(?:ok|posted)"/) {
		   # http://im.kayac.com/#docs
		   # (but actually responce is '"result": "ok"')
		   (my $content = $stat->{Content}) =~ s/\s+/ /;
		   $runloop->notify_warn(__PACKAGE__." im.kayac.com: post failed: $content");
	       }
	   },
	  );
}


sub config_prowl {
    my ($this, $config) = @_;

    require Crypt::SSLeay; # https support
    require URI;

    my $url = URI->new("https://api.prowlapp.com/publicapi/verify");
    $url->query_form(apikey => $config->apikey);
    my $runloop = $this->_runloop;
    Tools::HTTPClient->new(
	Request => GET($url->as_string()),
       )->start(
	   Callback => sub {
	       my $stat = shift;
	       $runloop->notify_warn(__PACKAGE__." prowl: verify failed: $stat")
		   unless ref($stat);
	       ## FIXME: check response (should check 'error')
	   },
	  );
}

sub send_prowl {
    my ($this, $config, $text, $msg, $sender, $full_ch_name) = @_;

    my $url = URI->new("https://api.prowlapp.com/publicapi/add");
    $text = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->format || $this->config->format || '[tiarra][#(channel):#(nick.now)] #(text)',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $this->strip_mirc_formatting($text),
       );
    my $event;
    if (defined $config->event_format) {
	$event = Auto::AliasDB->stdreplace(
	    $msg->prefix,
	    $config->event_format,
	    $msg, $sender,
	    channel => $full_ch_name,
	    raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	    text => $text,
	   );
    } else {
	$event = $config->event || 'keyword';
    }
    my $uri = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->url_format || '', ## config and param are "URL"
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    my @data = (apikey => $config->apikey,
		priority => $config->priority || 0,
		application => $config->application || 'tiarra',
		event => $event,
		($uri ne "" ? (url => $uri) : ()),
		description => $text);
    $url->query_form(@data);

    my $runloop = $this->_runloop;
    Tools::HTTPClient->new(
	Request => GET($url->as_string()),
       )->start(
	   Callback => sub {
	       my $stat = shift;
	       if (!ref($stat)) {
		   $runloop->notify_warn(__PACKAGE__." prowl: post failed: $stat");
	       } elsif ($stat->{Content} !~ /<success /) {
		   (my $content = $stat->{Content}) =~ s/\s+/ /;
		   $runloop->notify_warn(__PACKAGE__." prowl: post failed: $content");
	       }
	   },
	  );
}

sub config_boxcar {
    my ($this, $config) = @_;

    my $runloop = $this->_runloop;
    if (!$config->provider_key) {
	# growl mode
	require Crypt::SSLeay; # https support
	if (!$config->user || !$config->password) {
	    $runloop->notify_warn(__PACKAGE__." boxcar (Growl): please set user and/or password");
	}
    } elsif ($config->email_hash) {
	# ok
    } elsif ($config->email) {
	# needs to hash email
	require Digest::MD5;
    } elsif ($config->token && $config->secret) {
	# ok
    } else {
	$runloop->notify_warn(__PACKAGE__." boxcar (Provider): please set email-hash, email or token and secret");
    }

}

sub send_boxcar {
    my ($this, $config, $text, $msg, $sender, $full_ch_name) = @_;

    $text = $this->strip_mirc_formatting($text);
    my $screen_name = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->screenname_format || '[tiarra][#(channel):#(nick.now)]',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    $text = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->format || $this->config->format || '#(text)',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    my @data = ('notification[from_screen_name]' => $screen_name,
		'notification[message]' => $text);

    my $runloop = $this->_runloop;
    if (!$config->provider_key) {
	# Growl mode
	Tools::HTTPClient->new(
	    Request => POST("https://boxcar.io/notifications", \@data),
	   )->start(
	       Callback => sub {
		   my $stat = shift;
		   if (!ref($stat)) {
		       $runloop->notify_warn(__PACKAGE__." boxcar: post failed: $stat");
		   } elsif ($stat->{Content} !~ /^\s*$/) {
		       (my $content = $stat->{Content}) =~ s/\s+/ /;
		       $runloop->notify_warn(__PACKAGE__." boxcar: post failed: $content");
		   }
	       },
	      );
    } else {
	if ($config->email_hash) {
	    push(@data, email=>$config->email_hash);
	} elsif ($config->email) {
	    push(@data, email=>Digest::MD5->new->add($config->email)->hexdigest);
	} else {
	    push(@data,
		 token => $config->token,
		 secret => $config->secret);
	}
	Tools::HTTPClient->new(
	    Request => POST("http://boxcar.io/devices/providers/".
				$config->provider_key."/notifications", \@data),
	   )->start(
	       Callback => sub {
		   my $stat = shift;
		   if (!ref($stat)) {
		       $runloop->notify_warn(__PACKAGE__." boxcar: post failed: $stat");
		   } elsif ($stat->{Content} !~ /^\s*$/) {
		       (my $content = $stat->{Content}) =~ s/\s+/ /;
		       $runloop->notify_warn(__PACKAGE__." boxcar: post failed: $content");
		   }
	       },
	      );

    }

}


sub config_notifo {
    my ($this, $config) = @_;

    require Crypt::SSLeay; # https support
    require MIME::Base64;

    return # subscribe_user is not work with user account
	if (!defined($config->to) || $config->user eq $config->to);
    my $url = "https://api.notifo.com/v1/subscribe_user";
    my $runloop = $this->_runloop;
    Tools::HTTPClient->new(
	Request => POST($url, [username => $config->user],
			Authorization => 'Basic '.
			    MIME::Base64::encode($config->user .':'.$config->secret, "")),
       )->start(
	   Callback => sub {
	       my $stat = shift;
	       if (!ref($stat)) {
		   $runloop->notify_warn(__PACKAGE__." notifo: verify failed: $stat");
	       } elsif ($stat->{Content} !~ /"status":\s*"success"[,}]/) {
		   (my $content = $stat->{Content}) =~ s/\s+/ /;
		   $runloop->notify_warn(__PACKAGE__." notifo: verify failed: $content");
	       }
	   },
	  );
}

sub send_notifo {
    my ($this, $config, $text, $msg, $sender, $full_ch_name) = @_;

    my $url = "https://api.notifo.com/v1/send_notification";
    $text = $this->strip_mirc_formatting($text);
    my $title = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->title_format || '#(channel):#(nick.now)',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    my $uri = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->uri_format || '',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    $text = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->format || $this->config->format || '#(text)',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    my $data = [label => $config->label || 'tiarra',
		title => $title,
		to => $config->to || $config->user,
		((defined($uri) && $uri ne "") ? (uri => $uri) : ()),
		msg => $text];
    my $runloop = $this->_runloop;
    Tools::HTTPClient->new(
	Request => POST($url, $data, Authorization => 'Basic '.
			    MIME::Base64::encode($config->user .':'.$config->secret, "")),
       )->start(
	   Callback => sub {
	       my $stat = shift;
	       if (!ref($stat)) {
		   $runloop->notify_warn(__PACKAGE__." notifo: post failed: $stat");
	       } elsif ($stat->{Content} !~ /"status":\s*"success"[,}]/) {
		   (my $content = $stat->{Content}) =~ s/\s+/ /;
		   $runloop->notify_warn(__PACKAGE__." notifo: post failed: $content");
	       }
	   },
	  );
}


sub config_nma {
    my ($this, $config) = @_;

    # I don't have a good feeling to NMA, but Prowl didn't support
    #  Android, on 2011-09-30.
    # see also http://www.cocoaforge.com/viewtopic.php?f=45&t=20765#p129361
    # and check send_prowl and send_nma.

    require Crypt::SSLeay; # https support
    require URI;

    foreach my $apikey (split(/,/, $config->apikey)) {
	my $url = URI->new("https://www.notifymyandroid.com/publicapi/verify");
	$url->query_form(apikey => $apikey,
			 (defined $config->developerkey ?
			      (developerkey => $config->developerkey) : ()));
	my $runloop = $this->_runloop;
	Tools::HTTPClient->new(
	    Request => GET($url->as_string()),
	   )->start(
	       Callback => sub {
		   my $stat = shift;
		   $runloop->notify_warn(__PACKAGE__." NMA: verify failed: $stat")
		       unless ref($stat);
		   ## FIXME: check response (should check 'error')
	       },
	      );
    }
}

sub send_nma {
    my ($this, $config, $text, $msg, $sender, $full_ch_name) = @_;

    my $url = URI->new("https://www.notifymyandroid.com/publicapi/notify");
    $text = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->format || $this->config->format || '[tiarra][#(channel):#(nick.now)] #(text)',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $this->strip_mirc_formatting($text),
       );
    my $event = Auto::AliasDB->stdreplace(
	$msg->prefix,
	$config->event_format || 'keyword',
	$msg, $sender,
	channel => $full_ch_name,
	raw_channel => Auto::Utils::get_raw_ch_name($msg, 0),
	text => $text,
       );
    my @data = (apikey => $config->apikey,
		priority => $config->priority || 0,
		application => $config->application || 'tiarra',
		event => $event,
		description => $text,
		(defined $config->developerkey ?
		     (developerkey => $config->developerkey) : ()));
    $url->query_form(@data);

    my $runloop = $this->_runloop;
    Tools::HTTPClient->new(
	Request => GET($url->as_string()),
       )->start(
	   Callback => sub {
	       my $stat = shift;
	       if (!ref($stat)) {
		   $runloop->notify_warn(__PACKAGE__." NMA: post failed: $stat");
	       } elsif ($stat->{Content} !~ /<success /) {
		   (my $content = $stat->{Content}) =~ s/\s+/ /;
		   $runloop->notify_warn(__PACKAGE__." NMA: post failed: $content");
	       }
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

# メッセージのフォーマットを指定します。
# デフォルト値: [tiarra][#(channel):#(nick.now)] #(text)
# #(channel) のかわりに #(raw_channel) を利用するとネットワーク名がつきません。
format: [tiarra][#(channel):#(nick.now)] #(text)

# 使用するブロックを指定します
-blocks: im prowl boxcar-growl boxcar-provider notifo nma

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
-format: #(date:%H:%M:%S) #(text)

# Prowl で表示された apikey を入力します。
# Prowl については http://prowl.weks.net/ を参考にしてください。
-apikey: XXXXXX

# イベントのフォーマットを指定できます。
# 省略すると event の設定が利用されます。
event-format: #(channel):#(nick.now)

# URLのフォーマットを指定できます。
# 省略すると通知にURLを含めません。
# 現状の機構ではURLをエスケープする手段がないので、固定値以外はお勧めしません。
# また、 URL を指定するとアプリ側でのredirect設定は無視されるようです。
url-format:

# イベントを指定します。(固定値)
# event-format が指定された場合はそちらが優先されます。
event: keyword


# http://forums.cocoaforge.com/viewtopic.php?f=45&t=20339
priority: 0
application: tiarra

}

boxcar-growl {
# 利用する前にサービスリストに Growl を追加しておいてください。

type: boxcar

# Boxcar のユーザー名を指定します。必須です。
user:

# Boxcar のパスワードを指定します。必須です。
password:

# スクリーンネームのフォーマットを指定できます。
# デフォルト値: [tiarra][#(channel):#(nick.now)]
screenname-format: #(date:%H:%M:%S) [#(channel):#(nick.now)] #(text)

# 通知先ごとにフォーマットを指定できます。
# この例では先頭に時刻を追加しています。
# Boxcar ではスクリーンネームが別になるので、個別指定をお勧めします。
format: #(date:%H:%M:%S) [#(channel):#(nick.now)] #(text)

}

boxcar-provider {
# 自分用 provider を立てて利用するタイプです。
# http://boxcar.io/site/providers からサインアップしてください。
# このとき、 curl のコマンドライン中にある token と secret は
# サインアップ直後にしか表示されないので、忘れずメモしてください。
# (もちろんwebhookを立てればいつでも取得できますが……)
type: boxcar

# provider の API key を指定します。これがないと Growl モードになります。
provider-key: XXXXXX

# 通知先の指定をします。
# token と secret, email, email-hash のいずれかを指定するようにしてください。

# トークン。サインアップ直後の curl のコマンドライン中にあります。
-token: XXXXXX

# シークレット。サインアップ直後の curl のコマンドライン中にあります。
-secret: XXXXXXXX

# メールアドレス。 Digest::MD5 が必要です。
-email: XXXX@XXXX

# メールアドレスのMD5ハッシュ。 Digest::MD5 は必要ありません。
-email-hash: xxxxxx

# スクリーンネームのフォーマットを指定できます。
# デフォルト値: [tiarra][#(channel):#(nick.now)]
screenname-format: #(date:%H:%M:%S) [#(channel):#(nick.now)] #(text)

# 通知先ごとにフォーマットを指定できます。
# この例では先頭に時刻を追加しています。
# Boxcar ではスクリーンネームが別になるので、個別指定をお勧めします。
format: #(date:%H:%M:%S) [#(channel):#(nick.now)] #(text)

}

notifo {

# 通知先のタイプを指定します。
type: notifo

# noifo の Settings ページにある API Username を指定します。
# http://notifo.com/user/settings
user: XXXXXXX

# noifo の Settings ページにある API Secret を指定します。
# http://notifo.com/user/settings
secret: XXXXXXXXXXXXXXXXXXXXXX

# ラベルを指定します。
# サービスアカウントでは無視されます。
label: tiarra

# 通知先のユーザ名を指定します。
# ユーザアカウントでは無視されます。省略した場合は user に通知します。
-to: XXXXXXXXXXXXX

# タイトルのフォーマットを指定できます。
# デフォルト値: #(channel):#(nick.now)
title-format: #(channel):#(nick.now)

# URIのフォーマットを指定できます。
# 省略すると通知にURIを含めません。
# 現状の機構ではURIをエスケープする手段がないので、固定値以外はお勧めしません。
uri-format:

# 通知先ごとにフォーマットを指定できます。
# この例では先頭に時刻を追加しています。
format: #(date:%H:%M:%S) [#(channel):#(nick.now)] #(text)

}

nma {

# 通知先のタイプを指定します。
# Notify My Android には nma を指定してください。
type: nma

# 通知先ごとにフォーマットを指定できます。
# この例では先頭に時刻を追加しています。
format: #(date:%H:%M:%S) #(text)

# NMA で表示された apikey を入力します。
# https://www.notifymyandroid.com/account.php
# カンマで区切ると複数のAPIキーを指定することができます。
-apikey: XXXXXX

# イベントのフォーマットを指定できます。
# デフォルト値: keyword
event-format: #(channel):#(nick.now)

# https://www.notifymyandroid.com/api.php
priority: 0
application: tiarra
-developerkey:

}


=cut
