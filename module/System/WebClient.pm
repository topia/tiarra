## ----------------------------------------------------------------------------
#  System::WebClient.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package System::WebClient;
use strict;
use warnings;
use Module;
use base 'Module';
use Tools::HTTPServer;
use Tools::HTTPParser;
use Log::Logger;
use Auto::Utils;
use BulletinBoard;
use Module::Use qw(Tools::HTTPServer Tools::HTTPParser Log::Logger Auto::Utils);

use IO::Socket::INET;
use Scalar::Util qw(weaken);

our $DEBUG = 0;

our $DEFAULT_MAX_LINES = 100;
our $DEFAULT_NAME      = '???';
our $DEFAULT_SHOW_LINES = 20;

1;

# -----------------------------------------------------------------------------
# $pkg->new().
# (impl:tiarra-module)
#
#
sub new
{
  my $pkg  = shift;
  my $this = $pkg->SUPER::new(@_);

  local($DEBUG) = $DEBUG || $this->config->debug;
  $DEBUG and require Data::Dumper;

  my $has_lwp = $Tools::HTTPServer::Client::HAS_HTTP_PARSER;
  $this->_runloop->notify_msg(__PACKAGE__.", Tools::HTTPServer uses HTTP::Parser: ".($has_lwp?"yes":"no"));

  $this->{last_sender} = undef;
  $this->{last_msg}    = undef;
  $this->{last_line}   = undef;
  $this->{logger} = Log::Logger->new(
    sub { $this->_log_writer(@_) },
    $this,
    qw(S_PRIVMSG  C_PRIVMSG S_NOTICE C_NOTICE),
  );

  # トップ何行かのキャッシュ.
  $this->{bbs_val} = undef;
  $this->{cache} = undef;
  $this->_load_cache();

  my $config = $this->config;
  my $host   = $config->bind_addr || '127.0.0.1';
  my $port   = $config->bind_port || 8667;
  my $path   = $config->path || '/';
  $path =~ m{^/} or $path = "/$path";
  $path =~ m{/$} or $path = "$path/";

  $this->{host} = $host;
  $this->{port} = $port;
  $this->{path} = $path;

  $this->{listener} = undef;

  $this->_start_listener();
  
  $this;
}

# -----------------------------------------------------------------------------
# $this->destruct().
# (impl:tiarra-module)
#
sub destruct
{
  my $this = shift;

  local($DEBUG) = $DEBUG || $this->config->debug;

  if( my $lsnr = $this->{listener} )
  {
    if( $lsnr->installed )
    {
      $lsnr->uninstall();
    }
    $lsnr->close();
    $this->{listener} = undef;
  }

  # 循環参照の切断.
  $this->{logger} = undef;

  $this->{bbs_val}{unloaded_at} = time;
  $this->_debug(__PACKAGE__."->destruct(), done.");
}

# -----------------------------------------------------------------------------
# $obj->_load_cache().
# 有効にされる前のぶんとかをキャッシュに反映.
#
sub _load_cache
{
  my $this = shift;

  my $runloop = $this->_runloop;
  my $BBS_KEY = __PACKAGE__.'/cache';
  my $BBS_VAL = BulletinBoard->shared->get($BBS_KEY);
  if( !$BBS_VAL )
  {
    $runloop->notify_msg(__PACKAGE__."#_load_cache, bbs[$BBS_KEY] initialize");
    $BBS_VAL = {
      inited_at   => time,
      unloaded_at => 0,
      cache       => {},
    };
    BulletinBoard->shared->set($BBS_KEY, $BBS_VAL);
  }

  $this->{bbs_val} = $BBS_VAL;
  $this->{cache}   = $BBS_VAL->{cache};

  $runloop->notify_msg(__PACKAGE__."#_load_cache, bbs[$BBS_KEY].inited_at ".localtime($BBS_VAL->{inited_at}));
  $runloop->notify_msg(__PACKAGE__."#_load_cache, bbs[$BBS_KEY].unloaded_at ".($BBS_VAL->{unloaded_at}?localtime($BBS_VAL->{unloaded_at}):'-'));

  my $networks = $runloop->networks('even-if-not-connected');

  my %channels;
  foreach my $network (values %$networks)
  {
    my $netname = $network->network_name;
    my $channels = $network->channels('even-if-kicked-out');
    foreach my $channel (values %$channels)
    {
      my $channame = $channel->name;
      $this->{cache}{$netname}{$channame} ||= $this->_new_cache_entry($netname, $channame);
    }
  }
}


sub _new_cache_entry
{
  my $this = shift;
  my $netname  = shift;
  my $ch_short = shift;
  +{
    recent => [],
  };
}

# -----------------------------------------------------------------------------
# $obj->message_io_hook($msg, $sender, $type).
# (impl:tiarra-module)
#
sub message_arrived
{
  my ($this,$msg,$sender) = @_;

  my $cmd = $msg->command;
  if( $cmd ne 'PRIVMSG' && $cmd ne 'NOTICE' )
  {
    $this->_trace_msg($msg, $sender, '');
  }

  $msg;
}

sub message_io_hook
{
  my ($this,$msg,$sender,$type) = @_;
  my @ret = ($msg);

  if( $sender->isa('IrcIO::Server') )
  {
    # Serverとのio-hookのみ利用.
    # なおかつPRIVMSG/NOTICE のみ.
    my $cmd = $msg->command;
    if( $cmd eq 'PRIVMSG' || $cmd eq 'NOTICE' )
    {
      # PRIVMSG/NOTICE はserverゆきのメッセージを利用.
      my $msg = $msg->clone;

      # サーバゆきのチャンネル名になっているので, ch_full に書き換え.
      $msg->param(0, Multicast::attach($msg->param(0), $sender->network_name));

      my $dummy;
      if( $type eq 'out' )
      {
        # 送信だったらclientからおくられたように偽装.
        $dummy = bless \my$x, 'IrcIO::Client';
        $sender = $dummy;
      }

      eval{
        $this->_trace_msg($msg, $sender, $type);
      };
      if( $@ )
      {
        $this->_runloop->notify_error(__PACKAGE__."#message_io_hook: _trace_msg: $@");
      }

      if( $dummy )
      {
        # デストラクタが呼ばれないように差し替えて破棄.
        bless $dummy, 'UNIVERSAL';
      }
    }
  }

  @ret;
}

# -----------------------------------------------------------------------------
# $this->_trace_msg($msg, $sender, '').    // from message_arrived.
# $this->_trace_msg($msg, $sender, $type). // from message_io_hook.
#
sub _trace_msg
{
  my $this   = shift;
  my $msg    = shift;
  my $sender = shift;
  my $type   = shift;

  local($DEBUG) = $DEBUG || $this->config->debug;

  ##RunLoop->shared_loop->notify_msg(__PACKAGE__."#_trace_msg, ".$msg->command." ($sender/$type)");

  $this->{last_sender} = $sender;
  $this->{last_msg}    = $msg;
  $this->{last_line}   = undef;
  eval{
    $this->{logger}->log($msg,$sender);
  };
  $this->{last_sender} = undef;
  $this->{last_msg}    = undef;
  $this->{last_line}   = undef;
  if( $@ )
  {
    RunLoop->shared_loop->notify_error(__PACKAGE__."#_trace_msg, ".$@);
  }
}

# -----------------------------------------------------------------------------
# $this->S_PRIVMSG(..)
# $this->C_PRIVMSG(..)
# $this->S_NOTICE(..)
# $this->C_NOTICE(..)
# (impl/log-formatter).
# デフォルトのだとprivが寂しいのでトラップ.
#
{
no warnings 'once';
*S_PRIVMSG = \&PRIVMSG_or_NOTICE;
*S_NOTICE  = \&PRIVMSG_or_NOTICE;
*C_PRIVMSG = \&PRIVMSG_or_NOTICE;
*C_NOTICE  = \&PRIVMSG_or_NOTICE;
}

sub PRIVMSG_or_NOTICE
{
  my ($this,$msg,$sender) = @_;
  my $line = $this->{logger}->_build_message($msg, $sender);
  $this->{last_line} = $line;
  [$line->{ch_long}, $line->{line}];
}

# -----------------------------------------------------------------------------
# $this->_log_writer().
# (impl/log-writer).
#
sub _log_writer
{
  my ($this, $channel, $line) = @_;
  my $info   = $this->{last_line};

  #RunLoop->shared_loop->notify_msg(">> $channel $line");
  if( !$info )
  {
    # PRIVMSG/NOTICE 以外.
    my $sender = $this->{last_sender};

    my ($ch_short, $netname, $explicit) = Multicast::detach($channel);
    $explicit or $netname = $this->{last_sender}->network_name;
    $info = {
      netname  => $netname,
      ch_short => $ch_short,
      msg       => $line,
      formatted => $line,
    };
  }else
  {
    # チャンネル名なしに整形し直し.
    $line = sprintf(
      '%s%s%s %s',
      $info->{marker}[0],
      $info->{speaker},
      $info->{marker}[1],
      $info->{msg},
    );
  };
  my $netname  = $info->{netname};
  my $ch_short = $info->{ch_short};

  my @tm = localtime(time());
  $tm[5] += 1900;
  $tm[4] += 1;
  my $time = sprintf('%02d:%02d:%02d', @tm[2,1,0]);
  $info->{tm}   = \@tm;
  $info->{time} = $time;
  $info->{ymd} = sprintf('%04d-%02d-%02d', @tm[5,4,3]);
  $info->{formatted} = "$time $line";

  #RunLoop->shared_loop->notify_msg(__PACKAGE__."#_log_writer, $netname, $ch_short, [$channel] $line");

  my $cache = $this->{cache}{$netname}{$ch_short};
  if( !$cache )
  {
    $cache = $this->{cache}{$netname}{$ch_short} = $this->_new_cache_entry($netname, $ch_short);
  }

  my $recent = $cache->{recent};
  my $prev   = @$recent && $recent->[-1];
  $info->{lineno} = $prev && $prev->{ymd} eq $info->{ymd} ? $prev->{lineno} + 1 : 1;

  push(@$recent, $info);
  my $limit = $this->config->max_lines || 0;
  $limit =~ s/^0+//;
  if( !$limit || $limit !~ /^[1-9]\d*\z/ )
  {
    $limit = $DEFAULT_MAX_LINES;
  }
  @$recent > $limit and @$recent = @$recent[-$limit..-1];
}

# -----------------------------------------------------------------------------
# $this->_start_listener().
# new()の時に呼ばれる.
# Tools::HTTPServer を起動.
#
sub _start_listener
{
  my $this = shift;

  my $host = $this->{host};
  my $port = $this->{port};
  my $path = $this->{path};

  my $lsnr = Tools::HTTPServer->new();
  $lsnr->start(
    Host => $host,
    Port => $port,
    Path => $path,
    CallbackObject => $this,
  );
  RunLoop->shared_loop->notify_msg(__PACKAGE__.", listen on ".$lsnr->where);

  $this->{listener} = $lsnr;

  $this;
}

# -----------------------------------------------------------------------------
# $this->_debug($msg).
# デバッグメッセージ送信用.
#
sub _debug
{
  my $this = shift;
  my $msg = shift;
  RunLoop->shared_loop->notify_msg($msg);
}

# -----------------------------------------------------------------------------
# $this->_on_request($cli, $req).
# (impl:HTTPServer-callback)
#
sub _on_request
{
  my $this = shift;
  my $cli  = shift;
  my $req  = shift;

  local($DEBUG) = $DEBUG || $this->config->debug;

  my $peer = $cli->sock->peerhost .':'. $cli->sock->peerport;
  foreach my $eff ( $this->config->extract_forwarded_for('all') )
  {
    local($Tools::HTTPParser::DEBUG) = $Tools::HTTPParser::DEBUG || $DEBUG;
    my $allows = [ split( /\s+|\s*,\s*/, $eff ) ];
    if( @$allows && Tools::HTTPParser->extract_forwarded_for($req, $allows) )
    {
      $peer = "$req->{RemoteAddr}($peer)";
      last;
    }
  }
  $DEBUG and print __PACKAGE__."#_on_request, peer=$peer, ".Data::Dumper->new([$req])->Dump;

  my $conflist = $this->_find_conf($req);
  $req = {
    %$req,
    client    => $cli,
    peer      => $peer,
    conflist  => $conflist,
    need_auth => 1,
    ua_type   => undef,
    cgi_hash  => undef, # generated on demand.
    req_param => undef, # generated on demand.
  };
  if( my $ua = $req->{Header}{'User-Agent'} )
  {
    if( $ua =~ /(UP\.Browser|DoCoMo|J-PHONE|Vodafone|SoftBank)/i )
    {
      $req->{ua_type} = 'mobile';
    }else
    {
      $req->{ua_type} = 'pc';
    }
  }else
  {
    $req->{ua_type} = 'pc';
  }

  if( $req->{Method} !~ /^(GET|POST|HEAD)\z/ )
  {
    $this->_debug("$peer: method not allowed: $req->{Method}");
    # 405 Method Not Allowed
    $this->_response($req, 405);
    return;
  }

  if( !@$conflist )
  {
    $this->_debug("$peer: Forbidden by no conf");
    # 403 Forbidden.
    $this->_response($req, 403);
    return;
  }

  my ($user, $pass);
  if( my $line = $req->{Header}{Authorization} )
  {
    my ($type, $val) = split(' ', $line, 2);
    if( $type eq 'Basic' )
    {
      require MIME::Base64;
      my $dec = MIME::Base64::decode($val);
      ($user,$pass) = split(/:/, $dec, 2);
    }
  }
  my $need_auth = 1;
  if( !$user )
  {
    @$conflist = grep{ !$_->{auth} } @$conflist;
  }else
  {
    @$conflist = grep{ 
      my $auth = $_->{auth};
      my ($auth_user,$auth_pass) = split(' ', $auth);
      $auth_pass = _decode_value($auth_pass);
      $auth_user eq $user && $auth_pass eq $pass;
    } @$conflist;
  }
  $need_auth = @$conflist==0;

  if( $req->{Path} =~ /\?auth(?:=|[&;]|$)/ )
  {
    $need_auth = 1;
  }
  if( $need_auth )
  {
    $this->_debug("$peer: response: Authenticate Required");
    my $realm = 'Authenticate Required';
    # 401 Unauthorized
    my $res = {
      Code => 401,
      Header => {
        'WWW-Authenticate' => qq{Basic realm="$realm"},
      },
    };
    $this->_response($req, $res);
    return;
  }

  $this->_debug("$peer: accept.");
  $this->_dispatch($req);
}


sub _dispatch
{
  my $this = shift;
  my $req  = shift;

  my $path = $req->{Path};
  if( $path !~ s{\Q$this->{path}}{/} )
  {
    $this->_response($req, 404);
    return;
  }
  $path =~ s/\?.*//;

  if( $path eq '/' )
  {
    my $done = $req->{Method} eq 'POST' && $this->_post_list($req);
    if( !$done )
    {
      my $html = $this->_gen_list($req);
      $this->_response($req, [html=>$html]);
    }
  }elsif( $path =~ m{^/log/} )
  {
    my ($_blank, $_cmd, $netname, $ch_short, $param) = split('/', $path, 5);
    if( !defined($param) )
    {
      if( !$netname || !$ch_short )
      {
        $this->_location($req, "/");
      }else
      {
        $this->_location($req, "/log/$netname/$ch_short/");
      }
      return;
    }

    $ch_short =~ s/%([0-9a-f]{2})/pack("H*",$1)/gie;
    $ch_short =~ s/^=// or $ch_short = '#'.$ch_short;
    if( !$this->{cache}{$netname}{$ch_short} )
    {
      use Unicode::Japanese;
      my $ch2 = Unicode::Japanese->new($ch_short,'sjis')->utf8;
      if( $this->{cache}{$netname}{$ch2} )
      {
        $ch_short = $ch2;
      }else
      {
        RunLoop->shared_loop->notify_msg(__PACKAGE__."#_dispatch($path), not in cache ($netname/$ch_short)");
        $this->_response($req, 404);
        return;
      }
    }
    if( !$this->_can_show($req, $ch_short, $netname) )
    {
      #RunLoop->shared_loop->notify_msg(__PACKAGE__."#_dispatch($path), could not show ($netname/$ch_short)");
      $this->_response($req, 404);
      return;
    }
    #RunLoop->shared_loop->notify_msg(__PACKAGE__."#_dispatch($path), ok ($netname/$ch_short/$param)");
    if( $param eq '' )
    {
      my $done = $req->{Method} eq 'POST' && $this->_post_log($req, $netname, $ch_short);
      if( !$done )
      {
        my $html = $this->_gen_log($req, $netname, $ch_short);
        $this->_response($req, [html=>$html]);
      }
    }elsif( $param eq 'info' )
    {
      my $done = $req->{Method} eq 'POST' && $this->_post_chan_info($req, $netname, $ch_short);
      if( !$done )
      {
        my $html = $this->_gen_chan_info($req, $netname, $ch_short);
        $this->_response($req, [html=>$html]);
      }
    }else
    {
      $this->_response($req, 404);
    }
  }elsif( $path eq '/style/style.css' )
  {
    $this->_response($req, [css=>'']);
  }else
  {
    $this->_response($req, 404);
  }
}

sub _response
{
  my $this = shift;
  my $req  = shift;
  my $res  = shift;
  if( ref($res) eq 'ARRAY' )
  {
    my $spec = $res;
    if( $spec->[0] eq 'html' )
    {
      my $html = $spec->[1];
      $res = {
        Code => 200,
        Header => {
          'Content-Type'   => 'text/html; charset=utf-8',
          'Content-Length' => length($html),
        },
        Content => $html,
      };
    }elsif( $spec->[0] eq 'css' )
    {
      my $css = $spec->[1];
      $res = {
        Code => 200,
        Header => {
          'Content-Type'   => 'text/css; charset=utf-8',
          'Content-Length' => length($css),
        },
        Content => $css,
      };
    }else
    {
      die "unkown response spec: $spec->[0]";
    }
  }

  my $cli = $req->{client};
  $cli->response($res);

  # no Keep-Alive.
  $req->{client}->disconnect_after_writing();

  return;
}

sub _location
{
  my $this = shift;
  my $req  = shift;
  my $path = shift;

  $path = $this->{path} . $path;
  $path =~ s{//+}{/}g;
  my $res = {
    Code => 302,
    Header => {
      'Location' => $path,
    },
  };
  $this->_response($req, $res);
}

# -----------------------------------------------------------------------------
# $conflist = $this->_find_conf($req).
# $conflist: この接続元に対して利用可能な allow 情報の一覧.
# この時点ではまだ接続元IPアドレスでのチェックのみ.
#
sub _find_conf
{
  my $this = shift;
  my $req  = shift;
  my $peerhost = $req->{RemoteAddr};

  my @conflist;

  my $config = $this->config;
  foreach my $key (map{split(' ',$_)}$config->allow('all'))
  {
    my $name  = "allow-$key";
    my $block = $config->$name('block') or next;
    my $hosts = [$block->host('all')];
    my $match = Mask::match_deep($hosts, $peerhost);
    defined($match) or next;
    $match or last;
    my $allow = {
      name  => $name,
      block => $block,
      masks => [$block->mask('all')], # 公開するチャンネルの一覧.
      auth  => $block->auth,
    };
    push(@conflist, $allow);
  }

  \@conflist;
}

# -----------------------------------------------------------------------------
# $val = _decode_value($val).
# "{B}xxx" とかのデコード.
#
sub _decode_value
{
  my $val = shift;
  if( $val && $val =~ s/^\{(.*?)\}// )
  {
    my $type = $1;
    if( $type =~ /^(B|B64|BASE64)\z/ )
    {
      eval { require MIME::Base64; };
      if( $@ )
      {
        die "no MIME::Base64";
      }
      $val = MIME::Base64::decode($val);
    }else
    {
      die "unsupported packed value, type=$type";
    }
  }
  $val;
}

# -----------------------------------------------------------------------------
# $bool = $this->_can_show($req, $ch_short, $netname).
# 閲覧可能かの判定.
# 存在するかどうかは別途確認が必要.
#
sub _can_show
{
  my $this = shift;
  my $req  = shift;
  my $ch_short  = shift;
  my $netname   = shift;
  my $conflist = $req->{conflist};

  my $ch_full = Multicast::attach($ch_short, $netname);
  foreach my $allow (@$conflist)
  {
    my $ok = Mask::match_deep($allow->{masks}, $ch_full);
    $this->_debug("- $netname / $ch_short = ".($ok?"ok":"ng")." ".join(", ",@{$allow->{masks}}));
    if( $ok )
    {
      return $ok;
    }
  }
  return; # false.
}

# -----------------------------------------------------------------------------
# $html = $this->_gen_list($req).
#
sub _gen_list
{
  my $this = shift;
  my $req  = shift;

  my $peerhost = $req->{peerhost};
  my $conflist = $req->{conflist};

  my %channels;
  foreach my $netname (keys %{$this->{cache}})
  {
    foreach my $ch_short (keys %{$this->{cache}{$netname}})
    {
      my $ok = $this->_can_show($req, $ch_short, $netname);
      if( $ok )
      {
        push(@{$channels{$netname}}, $ch_short);
      }
    }
  }

  my $content = "";
  $content .= "<ul>\n";
  if( keys %channels )
  {
    foreach my $netname (sort keys %channels)
    {
      $content .= "<li> $netname\n";
      $content .= "  <ul>\n";
      my @channels = @{$channels{$netname}};
      @channels = sort @channels;
      foreach my $channame (@channels)
      {
        my $link_ch = $channame;
        $link_ch =~ s/^#// or $link_ch = "=$link_ch";
        my $link = "log\0$netname\0$link_ch\0";
        $link =~ s{/}{%2F}g;
        $link =~ tr{\0}{/};
        $link = $this->_escapeHTML($link);
        $content .= qq{<li><a href="$link">$channame</a></li>\n};
      }
      $content .= "  </ul>\n";
      $content .= "</li>\n";
    }
  }else
  {
    $content = "<li>no channels</li>\n";
  }
  $content .= "</ul>\n";

  my $tmpl = $this->_gen_list_html();
  $this->_expand($tmpl, {
    CONTENT => $content,
    UA_TYPE => $req->{ua_type},
  });
}
sub _gen_list_html
{
  <<HTML;
<?xml version="1.0" encoding="utf-8" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja-JP">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type"  content="text/css" />
  <meta http-equiv="Content-Script-Type" content="text/javascript" />
  <link rel="stylesheet" type="text/css" href="<&CSS>" />
  <title>channels</title>
</head>
<body>
<div class="main">
<div class="uatype-<&UA_TYPE>">

<h1>channels</h1>

<&CONTENT>

<form action="./" method="post">
ENTER: <input type="text" name="enter" value="" />
<input type="submit" value="入室" /><br />
</form>

<p>
[
<a href="./" accesskey="0">再表示</a>[0]
]
</p>

</div>
</div>
</body>
</html>
HTML
}

sub _post_list
{
  my $this = shift;
  my $req  = shift;

  my $cgi = $this->_get_cgi_hash($req);
  if( my $ch_long = $cgi->{enter} )
  {
    my ($ch_short, $netname) = Multicast::detach($ch_long);
    if( !$this->_can_show($req, $ch_short, $netname) )
    {
      return;
    }
    my $network  = $this->_runloop->network($netname);
    if( $network )
    {
      $this->{cache}{$netname}{$ch_short} ||= $this->_new_cache_entry($netname, $ch_short);
      $this->_debug("enter: $netname/$ch_short");
      my $link_ch = $ch_short;
      $link_ch =~ s/^#// or $link_ch = "=$link_ch";
      my $link = "log\0$netname\0$link_ch\0";
      $link =~ s{/}{%2F}g;
      $link =~ tr{\0}{/};
      $this->_location($req, $link);
      return 1;
    }
  }
  return undef;
}

sub _expand
{
  my $this = shift;
  my $tmpl = shift;
  my $vars = shift;

  my $top_path_esc = $this->_escapeHTML($this->{path});
  my $css_esc      = $this->_escapeHTML($this->config->css || "$this->{path}style/style.css");
  my $common_vars = {
    TOP_PATH => $top_path_esc,
    CSS      => $css_esc,
  };

  $tmpl =~ s{<&(.*?)>}{
    my $key = $1;
    if( defined($vars->{$key}) )
    {
      $vars->{$key};
    }elsif( defined($common_vars->{$key}) )
    {
      $common_vars->{$key};
    }else
    {
      die "unexpanded key: $key";
    }
  }ge;

  $tmpl;
}

# -----------------------------------------------------------------------------
# $html = $this->_gen_log($req, $netname, $ch_short).
#
sub _gen_log
{
  my $this = shift;
  my $req  = shift;
  my $netname  = shift;
  my $ch_short = shift;

  # cacheにはいっているのと閲覧許可があるのは確認済.

  my $content = "";

  if( my $net = $this->_runloop->network($netname) )
  {
    if( my $chan = $net->channel($ch_short) )
    {
      my $topic = $chan->topic || '(no-topic)';
      my $names = $chan->names || {};
      $names = [ values %$names ];
      @$names = map{
        my $pic = $_; # $pic :: PersonInChannel.
        my $nick  = $pic->person->nick;
        my $sigil = $pic->priv_symbol;
        "$sigil$nick";
      } @$names;
      @$names = sort @$names;
      my $topic_esc = $this->_escapeHTML($topic);
      my $names_esc = $this->_escapeHTML(join(' ', @$names));
      $content .= "<p>\n";
      $content .= "<span class=\"chan-topic\">TOPIC: $topic_esc</span><br />\n";
      #$content .= "<span class=\"chan-names\">member: $names_esc</span><br />\n";
      $content .= "</p>\n";
    }
  }else
  {
  }

  my $cache  = $this->{cache}{$netname}{$ch_short};
  my $recent = $cache->{recent};
  my $cgi    = $this->_get_cgi_hash($req);

  # 表示位置の探索.
  my $show_lines = $DEFAULT_SHOW_LINES;
  my $rindex;
  if( my $rtoken = $cgi->{r} )
  {
    my $re = qr/\Q$rtoken\E\z/;
    my $ymd = '-';
    foreach my $i (0..$#$recent)
    {
      my $info = $recent->[$i];
      if( $ymd ne $info->{ymd} )
      {
        $ymd = $info->{ymd};
        my $anchor = "L.$ymd";
        if( $anchor =~ $re )
        {
          $rindex = $i;
          last;
        }
      }
      my $anchor = "L.$ymd.$info->{lineno}";
      if( $anchor =~ $re )
      {
        $rindex = $i;
        last;
      }
    }
  }else
  {
    if( @$recent > $show_lines )
    {
      $rindex = @$recent - $show_lines;
    }
  }
  $rindex ||= 0;
  # $rindex も含めてindex系は [0..$#$recent] の範囲の値.

  my $last;
  if( $rindex + $show_lines > @$recent )
  {
    $last = $#$recent;
  }else
  {
    $last = $rindex + $show_lines - 1;
  }

  my $next_index = $last < $#$recent ? $last + 1 : $#$recent;
  my $prev_index = $rindex < $show_lines ? 0 : ($rindex - $show_lines);
  my ($next_rtoken, $prev_rtoken) = map {
    my $i = $_;
    my $info = $recent->[$i];
    my $anchor = "L.$info->{ymd}.$info->{lineno}";
    $anchor =~ s/.*-//;
    $anchor;
  } $next_index, $prev_index;

  my $nr_cached_lines = @$recent;
  my $lines2 = $nr_cached_lines==1 ? 'line' : 'lines';
  $recent = [ @$recent [ $rindex .. $last ] ];

  my $navi_raw = '';
  if( @$recent )
  {
    my $sort_order = $this->_get_req_param($req, 'sort-order');
    $this->_debug("sort_order = $sort_order");
    if( $sort_order ne 'asc' )
    {
      @$recent = reverse @$recent;
    }
    my $nr_recent = @$recent;
    my $lines    = $nr_recent==1 ? 'line' : 'lines';
    $navi_raw .= "<p>";
    $navi_raw .= "$nr_recent $lines / $nr_cached_lines $lines2.<br />";
    $navi_raw .= qq{[ <b><a href="?r=$prev_rtoken" accesskey="7">&lt;&lt;</a></b>[7] |};
    $navi_raw .= qq{  <b><a href="?r=$next_rtoken" accesskey="9">&gt;&gt;</a></b>[9] ]\n};
    $navi_raw .= "</p>";

    my $ymd = '-'; # first entry should be displayed.
    $content .= "<pre>";
    foreach my $info (@$recent)
    {
      if( $ymd ne $info->{ymd} )
      {
        $ymd = $info->{ymd};
        my $anchor = "L.$ymd";
        my $rtoken = $ymd;
        $content .= qq{[<b><a id="$anchor" href="?r=$rtoken">$ymd</a></b>]\n};
      }
      my $line_html = $this->_escapeHTML($info->{formatted});
      if( $req->{ua_type} ne 'pc' )
      {
        $line_html =~ s/^(\d\d:\d\d):\d\d /$1 /;
      }
      my $anchor = "L.$ymd.$info->{lineno}";
      my $rtoken = $anchor;
      $rtoken =~ s/.*-//;
      $content .= qq{<a id="$anchor" href="?r=$rtoken">$info->{lineno}</a>/$line_html\n};
    }
    $content .= "</pre>\n";
  }else
  {
    $content .= "<p>\n";
    $content .= "no lines.";
    $content .= "</p>\n";
  }

  my $ch_long = Multicast::attach($ch_short, $netname);
  my $ch_long_esc = $this->_escapeHTML($ch_long);
  my $name_esc = $this->_escapeHTML($cgi->{n} || '');

  my $mode = $this->_get_req_param($req, 'mode');
  my $name_input_raw = '';
  if( $mode ne 'owner' )
  {
    $name_input_raw = qq{name:<input type="text" name="n" size="10" value="$name_esc" /><br />};
  }

  my $tmpl = $this->_gen_log_html();
  $this->_expand($tmpl, {
    CONTENT_RAW => $content,
    UA_TYPE     => $req->{ua_type},
    NAVI_RAW    => $navi_raw,
    CH_LONG => $ch_long_esc,
    NAME    => $name_esc,
    NAME_INPUT_RAW => $name_input_raw,
    RTOKEN  => $next_rtoken,
    NEXT_RTOKEN => $next_rtoken,
    PREV_RTOKEN => $prev_rtoken,
  });
}
sub _gen_log_html
{
  <<HTML;
<?xml version="1.0" encoding="utf-8" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja-JP">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type"  content="text/css" />
  <meta http-equiv="Content-Script-Type" content="text/javascript" />
  <link rel="stylesheet" type="text/css" href="<&CSS>" />
  <title><&CH_LONG></title>
</head>
<body>
<div class="main">
<div class="uatype-<&UA_TYPE>">

<h1><&CH_LONG></h1>

<&CONTENT_RAW>

<form action="./" method="post">
<p>
talk:<input type="text" name="m" size="60" />
  <input type="submit" value="発言/更新" /><br />
<&NAME_INPUT_RAW>
<input type="hidden" name="r" size="10" value="<&RTOKEN>" />
</p>
</form>

<&NAVI_RAW>

<p>
[
<a href="./?r=<&NEXT_RTOKEN>" accesskey="*">更新</a>[*] |
<a href="<&TOP_PATH>" accesskey="0">List</a>[0] |
<a href="info" accesskey="#">info</a>[#]
]
</p>

</div>
</div>
</body>
</html>
HTML
}

sub _get_req_param
{
  my $this = shift;
  my $req  = shift;
  my $key  = shift;

  if( !grep{ $key eq $_ } qw(mode sort-order) )
  {
    die "invalid req-param [$key]";
  }
  if( $req->{req_param}{$key} )
  {
    return $req->{req_param}{$key};
  }

  my $val;
  foreach my $allow (@{$req->{conflist}})
  {
    $val = $allow->{block}->$key;
    $val or next;
    $DEBUG and $this->_debug(__PACKAGE__."#_gen_log, $key = $val (by $allow->{name})");
    last;
  }
  $val ||= $this->config->$key;
  if( $key eq 'mode' )
  {
    $val ||= 'owner';
    if( $val !~ /^(owner|shared)\z/ )
    {
      $val = 'owner';
    }
  }
  if( $key eq 'sort-order' )
  {
    $val ||= 'asc';
    $val = $val =~ /^(desc|rev)/ ? 'desc' : 'asc';
  }

  $req->{req_param}{$key} = $val;
  $val;
}

sub _get_cgi_hash
{
  my $this = shift;
  my $req  = shift;

  if( $req->{cgi_hash} )
  {
    return $req->{cgi_hash};
  }

  my $cgi = {};

  if( $req->{Method} eq 'GET' )
  {
    if( $req->{Path} =~ m{\?} )
    {
      (undef,my $query) = split(/\?/, $req->{Path});
      foreach my $pair (split(/[&;]/, $query))
      {
        my ($key, $val) = split(/=/, $pair, 2);
        $val =~ s/%([0-9a-f]{2})/pack("H*",$1)/gie;
        $cgi->{$key} = $val;
      }
    }
  }

  if( $req->{Method} eq 'POST' )
  {
    foreach my $pair (split(/[&;]/, $req->{Content}))
    {
      my ($key, $val) = split(/=/, $pair, 2);
      $val =~ s/%([0-9a-f]{2})/pack("H*",$1)/gie;
      $cgi->{$key} = $val;
    }
  }

  $req->{cgi_hash} = $cgi;
  $cgi;
}

sub _post_log
{
  my $this = shift;
  my $req  = shift;
  my $netname  = shift;
  my $ch_short = shift;

  my $mode = $this->_get_req_param($req, 'mode');

  my $cgi = $this->_get_cgi_hash($req);
  my $name   = $cgi->{n} || '';
  if( my $m = $cgi->{m} )
  {
    if( $mode ne 'owner' )
    {
      $m = ($name || $this->config->name_default || $DEFAULT_NAME) . "> " . $m;
    }
    $m =~ s/[\r\n].*//s;
    my $network = RunLoop->shared_loop->network($netname);
    if( $network )
    {
      my $channel = $network->channel($ch_short);
      if( $channel || !Multicast::channel_p($ch_short) )
      {
        my $msg_to_send = Auto::Utils->construct_irc_message(
          Command => 'PRIVMSG',
          Params  => [ '', $m ],
        );

        # send to server.
        #
        {
          my $for_server = $msg_to_send->clone;
          $for_server->param(0, $ch_short);
          $network->send_message($for_server);
        }

        # send to clients.
        #
        my $ch_on_client = Multicast::attach_for_client($ch_short, $netname);
        my $for_client = $msg_to_send->clone;
        $for_client->param(0, $ch_on_client);
        $for_client->remark('fill-prefix-when-sending-to-client', 1);
        RunLoop->shared_loop->broadcast_to_clients($for_client);
      }else
      {
        RunLoop->shared_loop->notify_error("no such channel [$ch_short] on network [$netname]");
      }
    }else
    {
      RunLoop->shared_loop->notify_error("no network to talk: $netname");
    }
  }
  return undef;
}

# -----------------------------------------------------------------------------
# $html = $this->_gen_chan_info($req, $netname, $ch_short).
#
sub _gen_chan_info
{
  my $this = shift;
  my $req  = shift;
  my $netname  = shift;
  my $ch_short = shift;

  my $content_raw = "";

  my ($topic_esc, $names_esc);
  if( my $net = $this->_runloop->network($netname) )
  {
    if( my $chan = $net->channel($ch_short) )
    {
      my $topic = $chan->topic || '(none)';
      my $names = $chan->names || {};
      $names = [ values %$names ];
      @$names = map{
        my $pic = $_; # $pic :: PersonInChannel.
        my $nick  = $pic->person->nick;
        my $sigil = $pic->priv_symbol;
        "$sigil$nick";
      } @$names;
      @$names = sort @$names;
      $topic_esc = $this->_escapeHTML($topic);
      $names_esc = $this->_escapeHTML(join(' ', @$names));
    }
  }else
  {
  }
  $topic_esc ||= '-';
  $names_esc ||= '-';

  my $in_topic_esc;
  my $cgi = $this->_get_cgi_hash($req);
  if( my $in_topic = $cgi->{topic} )
  {
    $in_topic_esc = $this->_escapeHTML($in_topic);
  }else
  {
    $in_topic_esc = $topic_esc;
  }

  my $ch_long = Multicast::attach($ch_short, $netname);
  my $ch_long_esc = $this->_escapeHTML($ch_long);

  my $tmpl = $this->_tmpl_chan_info();
  $this->_expand($tmpl, {
    CONTENT_RAW => $content_raw,
    UA_TYPE     => $req->{ua_type},
    CH_LONG   => $ch_long_esc,
    TOPIC     => $topic_esc,
    IN_TOPIC  => $in_topic_esc,
    NAMES     => $names_esc,
    PART_MSG  => 'Leaving...',
  });
}
sub _tmpl_chan_info
{
  <<HTML;
<?xml version="1.0" encoding="utf-8" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja-JP">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <meta http-equiv="Content-Style-Type"  content="text/css" />
  <meta http-equiv="Content-Script-Type" content="text/javascript" />
  <link rel="stylesheet" type="text/css" href="<&CSS>" />
  <title><&CH_LONG></title>
</head>
<body>
<div class="main">
<div class="uatype-<&UA_TYPE>">

<h1><&CH_LONG></h1>

<&CONTENT_RAW>

<form action="./info" method="post">
TOPIC: <span class="chan-topic"><&TOPIC></span><br />
<input type="text" name="topic" value="<&IN_TOPIC>" />
<input type="submit" value="変更" /><br />
</form>

<p>
NAMES: <span class="chan-names"><&NAMES></span><br />
</p>

<form action="./info" method="post">
PART: <input type="text" name="part" value="<&PART_MSG>" />
<input type="submit" value="退室" /><br />
</form>

<form action="./info" method="post">
JOIN <input type="text" name="join" value="<&CH_LONG>" />
<input type="submit" value="入室" /><br />
</form>

<form action="./info" method="post">
DELETE <input type="text" name="delete" value="<&CH_LONG>" />
<input type="submit" value="削除" /><br />
</form>

<p>
[
<a href="./" accesskey="*">戻る</a>[*] |
<a href="<&TOP_PATH>" accesskey="0">List</a>[0] |
<a href="info" accesskey="#">再表示</a>[#]
]
</p>

</div>
</div>
</body>
</html>
HTML
}

sub _post_chan_info
{
  my $this = shift;
  my $req  = shift;
  my $netname  = shift;
  my $ch_short = shift;

  my $cgi = $this->_get_cgi_hash($req);
  if( exists($cgi->{topic}) )
  {
    my $msg_to_send = Auto::Utils->construct_irc_message(
      Command => 'TOPIC',
      Params  => [ '', $cgi->{topic} ],
    );

    # send to server.
    #
    my $network = RunLoop->shared_loop->network($netname);
    if( $network )
    {
      my $for_server = $msg_to_send->clone;
      $for_server->param(0, $ch_short);
      $network->send_message($for_server);
    }
  }

  if( exists($cgi->{part}) )
  {
    my $msg_to_send = Auto::Utils->construct_irc_message(
      Command => 'PART',
      Params  => [ '', $cgi->{part} ],
    );

    # send to server.
    #
    my $network = RunLoop->shared_loop->network($netname);
    if( $network )
    {
      my $for_server = $msg_to_send->clone;
      $for_server->param(0, $ch_short);
      $network->send_message($for_server);
    }
  }

  if( exists($cgi->{join}) )
  {
    my $msg_to_send = Auto::Utils->construct_irc_message(
      Command => 'JOIN',
      Params  => [ '' ],
    );

    # send to server.
    #
    my $network = RunLoop->shared_loop->network($netname);
    if( $network )
    {
      my $for_server = $msg_to_send->clone;
      $for_server->param(0, $ch_short);
      $network->send_message($for_server);
    }
  }

  if( exists($cgi->{'delete'}) )
  {
    delete $this->{cache}{$netname}{$ch_short};
    if( !keys %{$this->{cache}{$netname}} )
    {
      delete $this->{cache}{$netname};
    }
    $this->_location($req, "/");
    return 1;
  }

  return undef;
}

# -----------------------------------------------------------------------------
# $txt = $this->_escapeHTML($html).
#
sub _escapeHTML
{
  my $this = shift;
  Tools::HTTPParser->escapeHTML(@_);
}

# -----------------------------------------------------------------------------
# End of Module.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# End of File.
# -----------------------------------------------------------------------------
__END__

=encoding utf8

=for stopwords
	YAMASHINA
	Hio
	ACKNOWLEDGEMENTS
	AnnoCPAN
	CPAN
	RT

package System::WebClient;

=begin tiarra-doc

info:    ブラウザ上でログを見たり発言したりできます.
default: off
#section: important

# WebClient を起動させる場所の指定.
bind-addr: 127.0.0.1
bind-port: 8668
path: /irc
css:  /style/irc-style.css
# 上の設定をapacheでReverseProxyさせる場合, httpd.conf には次のように設定.
#  ProxyPass        /irc/ http://localhost:8667/irc/
#  ProxyPassReverse /irc/ http://localhost:8667/irc/
#  <Location /irc/>
#  ...
#  </Location>

# ReverseProxy 利用時の追加設定.
# 接続元が全部プロキシサーバになっちゃうのでその対応.
-extract-forwarded-for: 127.0.0.1

# 利用する接続設定の一覧.
#
# 空白区切りで評価する順に記述.
# 使われる設定は,
# - 接続元 IP が一致する物.
# - user/passが送られてきていない(認証前/anonymous):
#   - 認証不要の設定があればその設定を利用.
#   - 認証不要の設定がなければ 401 Unauthorized.
# - user/passが送られてきている.
#   - 一致する設定を利用.
#   - 一致する設定がなければ 401 Unauthorized.
allow: private public

# 許可する接続の設定.
allow-private {
  # 接続元IPアドレスの制限.
  host: 127.0.0.1
  # 認証設定.
  auth: user pass
  # 公開するチャンネルの指定.
  mask: #*@*
  mask: *@*
}
allow-public {
  host: *
  auth: user2 pass2
  mask: #公開チャンネル@ircnet
}

# デバッグフラグ.
-debug: 0

# 保存する最大行数.
-max-lines:    100

# クライアントモード.
# owner か shared.
- mode: owner

# ログの方向.
# asc (旧->新) か desc (新->旧).
- sort-order: asc

# 発言BOXで名前指定しなかったときのデフォルトの名前.
# mode: shared の時に使われる.
-name-default: (noname)

=end tiarra-doc

=cut
