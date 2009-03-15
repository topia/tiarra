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
use Unicode::Japanese;

use IO::Socket::INET;
use Scalar::Util qw(weaken);

our $VERSION = '0.06';

our $DEBUG = 0;

our $DEFAULT_MAX_LINES = 100;
our $DEFAULT_SHOW_LINES = 20;
our $DEFAULT_SITE_NAME  = "Tiarra::WebClient";
our $DEFAULT_SESSION_EXPIRE = 7 * 24 * 60*60;
our $NO_TOPIC = '(no-topic)';

=begin COMMENT

System::WebClient - ブラウザ上でログを見たり発言したりできるようにする Tiarra モジュール.

 /
   #==> [POST/_post_list] ENTER.
   #==> [GET/_gen_list]   /log/*/* を一覧.
 /log/<network>/<channel>/
   #==> [POST/_post_log] 発言.
   #==> [GET/_gen_log]   ログの閲覧.
   #==> ?r=XXX ==> ここまでは見たからこれの次から表示.
   #==> ?x=XXX ==> 最新を表示するけれど,ここまではみたから表示しない.
 /log/<network>/<channel>/info
   #==> [POST/_post_chan_info] TOPIC/JOIN/PART/DELETE.
   #==> [GET/_gen_chan_info]   チャンネル情報表示.
 /config
   #==> [POST/_post_config] NAME
   #==> [GET/_gen_config]   shared時の名前設定
 /style/style.css
   #==> 空のCSSファイル.
 <それ以外>
   #==> 404.

session 情報:
  $req->{session}{seen} -- 未読管理.
    $req->{session}{seen}{$netname}{$ch_short} = $recent内のオブジェクト.
  $req->{session}{name} -- shared用の名前.

(*) 存在するけれど閲覧許可のないページであっても, 
    403 (Forbidden) ではなく 404 (Not Found) を返す.
(*) ENTER: チャンネル情報を作成. この情報はそこにチャンネルがある(あった)ということを
           保持していて, PART後も残るため過去ログが閲覧できる.
(*) DELETE: 保持しているチャンネル情報を削除.
            そのチャンネルの情報がもういらないのなら, 存在していたことを削除できる.

=end COMMENT

=cut

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
  $this->{bbs_val}   = undef;
  $this->{cache}     = undef;
  $this->{max_lines} = undef;
  $this->{session_master} = undef;
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
  $DEBUG and $this->_debug(__PACKAGE__."->destruct(), done.");
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
      session     => {},
    };
    BulletinBoard->shared->set($BBS_KEY, $BBS_VAL);
  }
  $BBS_VAL->{session} ||= {};

  $this->{bbs_val} = $BBS_VAL;
  $this->{cache}   = $BBS_VAL->{cache};
  $this->{session_master} = $BBS_VAL->{session};

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
      my $cache = $this->{cache}{$netname}{$channame};

      # old version does not have these entries.
      $this->{cache}{$netname}{$channame}{netname}  ||= $netname;
      $this->{cache}{$netname}{$channame}{ch_short} ||= $channame;
    }
  }

  my $limit = $this->config->max_lines || 0;
  $limit =~ s/^0+//;
  if( !$limit || $limit !~ /^[1-9]\d*\z/ )
  {
    $limit = $DEFAULT_MAX_LINES;
  }
  $this->{max_lines}{''} = $limit;
}


sub _new_cache_entry
{
  my $this = shift;
  my $netname  = shift;
  my $ch_short = shift;
  +{
    recent => [],
    netname  => $netname,
    ch_short => $ch_short,
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
  my $limit = $this->{max_lines}{''};
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
    authid    => undef, # login token (basic, etc.)
    authtoken => undef, # session token (sid).
    ua_type   => undef,
    cgi_hash  => undef, # generated on demand.
    req_param => undef, # config params, generated on demand.
    session   => undef,
    path      => undef, # path under $config->{path}.
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
    $DEBUG and $this->_debug("$peer: method not allowed: $req->{Method}");
    # 405 Method Not Allowed
    $this->_response($req, 405);
    return;
  }

  if( !@$conflist )
  {
    $DEBUG and $this->_debug("$peer: Forbidden by no conf");
    # 403 Forbidden.
    $this->_response($req, 403);
    return;
  }

  $DEBUG and $this->_debug("$peer: check auth ...");
  my $accepted_list = $this->auth($conflist, $req);
  #$DEBUG and $this->_debug("$peer: auth=".Dumper($accepted_list));use Data::Dumper;
  my $authid_list;
  my $authtoken_list;
  if( @$accepted_list )
  {
    $DEBUG and $this->_debug("$peer: has auth");
    # update @$conflist.
    @$conflist = map{ $_->{conf} } @$accepted_list;

    # extract authtoken list.
    $authid_list    = [];
    $authtoken_list = [];
    foreach my $auth (@$accepted_list)
    {
      if( !grep { $_ eq $auth->{token} } @$authtoken_list )
      {
        # unique.
        push(@$authtoken_list, $auth);
      }
      if( !grep { $_ eq $auth->{id} } @$authid_list )
      {
        # unique.
        push(@$authid_list, $auth);
      }
    }
  }else
  {
    $DEBUG and $this->_debug("$peer: no auth");
    @$conflist = grep{ !$_->{auth} } @$conflist;
    $DEBUG and $this->_debug("$peer: has guest entry ".(@$conflist?"yes":"no"));
  }

  my $need_auth = @$conflist == 0;
  if( $req->{Path} =~ /\?auth(?:=|[&;]|$)/ )
  {
    $need_auth = 1;
  }
  if( $need_auth )
  {
    $DEBUG and $this->_debug("$peer: response: Authenticate Required");
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

  $req->{authid}    = ($authid_list    && @$authid_list)    ? $authid_list   ->[0]->{id}     : undef;
  $req->{authtoken} = ($authtoken_list && @$authtoken_list) ? $authtoken_list->[0]->{atoken} : undef;
  if( !$req->{authtoken} )
  {
    $DEBUG and $this->_debug("$peer: no authtoken, check cookie");
    CHECK_COOKIE:{
      my $cookies = $req->{Header}{Cookie} || '';
      my @cookies = split(/\s*[;,]\s*/, $cookies);
      my $ck = shift @cookies || '';
      my ($key, $val) = split(/=/, $ck);
      $key && $val or last CHECK_COOKIE;
      $val =~ s/%([0-9a-f]{2})/pack("H*",$1)/ge;
      $DEBUG and $this->_debug("$peer: cookie: [$key]=[$val]");
      if( $val !~ /^sid:(\d+):(\d+):(\d+)(?::|\z)/ )
      {
        last CHECK_COOKIE;
      }
      my ($seed, $seq, $check) = ($1, $2, $3);
      my $sid = "sid:$seed:$seq:$check";
      $req->{authtoken} = $sid;
      $DEBUG and $this->_debug("$peer: $sid");
    }
  }

  my $path = $req->{Path};
  if( $path !~ s{\Q$this->{path}}{/} )
  {
    $this->_debug("$peer: outside request, [$path] is not contened in [$this->{path}]");
    $this->_response($req, 404);
    return;
  }
  $path =~ s/\?.*//;
  $req->{path} = $path;

  my $mode = $this->_get_req_param($req, 'mode');
  if( $mode eq 'owner' )
  {
    $req->{authtoken} ||= "owner:*";
  }
  $this->_update_session($req);

  my $need_name;
  if( $mode eq 'owner' )
  {
    $need_name = undef;
  }elsif( $req->{session}{name} )
  {
    $need_name = undef;
  }elsif( $path eq '/style/style.css' )
  {
    $need_name = undef;
  }else
  {
    $need_name = 1;
  }
  
  if( $need_name )
  {
    $this->_debug("$peer: login required (no name). [vpath=$req->{path}]");
    eval{
      $this->_login($req);
    };
  }else
  {
    my $aid  = $req->{authid}        || '-';
    my $sid  = $req->{authtoken}     || '-';
    my $name = $req->{session}{name} || '-';
    $this->_debug("$peer: accept: auth=$aid, name=$name, sid=$sid");
    eval {
      $this->_dispatch($req);
    };
  }
  $@ and $this->_debug("$peer: error: $@");
  $DEBUG and $this->_debug("$peer: done");
}

# -----------------------------------------------------------------------------
# my $sess = $this->_new_session().
# Set-Cookie も設定される.
#
sub _new_session
{
  my $this = shift;
  my $req  = shift;

  our $seed ||= int(rand(0xFFFF_FFFF));
  our $seq  ||= 0;
  $seq ++;
  my $rnd = int(rand(0xFFFF_FFFF));
  my $sid = "sid:$seed:$seq:$rnd";
  $DEBUG and $this->_debug("$req->{peer}: _new_session: $sid");

  $req->{authtoken} = $sid;
  my $sess = $this->_update_session($req);
  $req->{cookies}{SID} = $sess->{_sid};
  $sess;
}

# -----------------------------------------------------------------------------
# my $sess = $this->_delete_session($req).
# 削除用の Set-Cookie も設定される.
#
sub _delete_session
{
  my $this = shift;
  my $req  = shift;
  my $sess = $req->{session} || {};
  my $sid  = $sess->{_sid} || '';
  my $deleted = delete $this->{session_master}{$sid};
  if( $deleted )
  {
    $deleted->{_deleted} = 1;
  }
  if( $sid )
  {
    $req->{cookies}{SID} = undef;
  }
  $deleted;
}

# -----------------------------------------------------------------------------
# $this->_update_session($req);
# 指定のsessionを取得.
# なかったら生成される.
#
sub _update_session
{
  my $this = shift;
  my $req  = shift;

  my $sid = $req->{authtoken};
  if( !$sid )
  {
    # check weak session.
    my $cgi = $this->_get_cgi_hash($req);
    my $w_sid = $cgi->{SID};
    my $sess = $w_sid && $this->{session_master}{$w_sid};
    if( $sess && $sess->{_weak} )
    {
      # accept weak session.
      $sid = $w_sid;
      $req->{authtoken} = $w_sid;
    }else
    {
      $DEBUG and $this->_debug("$req->{peer}: _update_session: no sid");
      $req->{session} = {};
      return;
    }
  }

  my $sess = ($this->{session_master}{$sid} ||= {});
  my $now  = time;
  if( $sess->{_updated_at} )
  {
    if( $sess->{_updated_at} + $DEFAULT_SESSION_EXPIRE < $now )
    {
      # clean up.
      $sess = {};
      $this->{session_master}{$sid} = $sess;
    }
  }

  if( !$sess->{_sid} )
  {
    $sess->{_sid}        = $sid;
    $sess->{_created_at} = $now;
    $sess->{_expire}     = $DEFAULT_SESSION_EXPIRE;
    $sess->{_weak}       = undef;
  }
  $sess->{_updated_at} =   $now;

  # $sess->{seen} = \%seen;
  # $sess->{name} = $name;
  $DEBUG and $this->_debug("$req->{peer}: _get_session: $sess->{_sid}");
  #$DEBUG and $this->_debug("$req->{peer}: _get_session: ".Dumper($sess));use Data::Dumper;

  $req->{session} = $sess;

  $sess;
}

sub auth
{
  my $this     = shift;
  my $conflist = shift;
  my $req      = shift;
  my @accepts;

  # 認証関数.
  # $val = $sub->($this, \@param, $req).
  # \%hashref #==> accept.
  # undef     #==> ignore.
  # ''        #==> deny.
  our $AUTH ||= {
    ':basic'    => \&_auth_basic,
    ':softbank' => \&_auth_softbank,
    ':au'       => \&_auth_au,
  };

  foreach my $conf (@$conflist)
  {
    $DEBUG and $this->_debug("$req->{peer}: check auth for $conf->{name}");
    my $authlist = $conf->{auth} or next;
    foreach my $auth (@$authlist)
    {
      my @param = split(' ', $auth || '');
      if( !@param )
      {
        $DEBUG and ::printmsg("$req->{peer}: - skip: empty value");
        next;
      }
      $param[0] =~ /^:/ or unshift(@param, ':basic');
      my $auth_sub = $AUTH->{$param[0]};
      if( !$auth_sub )
      {
        $DEBUG and ::printmsg("$req->{peer}: - skip: unsupported: $param[0]");
        next;
      }
      my $val = $this->$auth_sub(\@param, $req);
      if( $val )
      {
        $DEBUG and $this->_debug("$req->{peer}: - $conf->{name} accepted ($param[0])");
        push(@accepts, {
          atoken => $val->{atoken}, # auth token, string or undef.
          id     => $val->{id},     # auth id,    string. not undef.
          conf   => $conf,
        });
      }elsif( defined($val) )
      {
        $DEBUG and $this->_debug("$req->{peer}: auth denied by $conf->{name}");
        return undef;
      }
    }
  }
  \@accepts;
}

sub _auth_basic
{
  my $this  = shift;
  my $param = shift;
  my $req   = shift;

  my $line = $req->{Header}{Authorization};
  if( !$line )
  {
    $DEBUG and ::printmsg("$req->{peer}: no Authorization: header");
    return;
  }

  my ($type, $val) = split(' ', $line, 2);
  if( $type ne 'Basic' )
  {
    $DEBUG and ::printmsg("$req->{peer}: not Basic Authorization (got $type)");
    return;
  }

  require MIME::Base64;
  my $dec = MIME::Base64::decode($val);
  my ($user,$pass) = split(/:/, $dec, 2);

  if( !_verify_value($param->[1], $user) )
  {
    defined($user) or $user = '';
    $DEBUG and ::printmsg("$req->{peer}: $param->[0] user $param->[1] does not match with '$user' (user)");
    return;
  }
  if( !_verify_value($param->[2], $pass) )
  {
    defined($pass) or $pass = '';
    $DEBUG and ::printmsg("$req->{peer}: $param->[0] pass $param->[2] does not match with '$pass' (pass)");
    return;
  }

  # accept.
  $DEBUG and ::printmsg("$req->{peer}: accept user $param->[0] pass $param->[2] with '$user' '$pass'");
  +{
    id => "basic:$user",
    atoken => undef,
  };
}

sub _auth_softbank
{
  my $this  = shift;
  my $param = shift;
  my $req   = shift;

  #TODO: carrier ip-addresses range.

  # UIDはhttp領域若しくはsecure.softbank.ne.jp経由.
  # SNは端末の設定.
  my $uid = $req->{Header}{'X-JPHONE-UID'};
  my $sn = do{
    my ($ua1) = split(' ', $req->{Header}{'User-Agent'} || '');
    my @ua = split('/', $ua1 || '');
    my $carrier = uc($ua[0] || '');
    my $sn = $carrier eq 'J-PHONE'  ? $ua[3] 
           : $carrier eq 'VODAFONE' ? $ua[4]
           : $carrier eq 'SOFTBANK' ? $ua[4]
           : undef;
    $sn;
  };
  if( _verify_value($param->[1], $uid) )
  {
    # accept.
    my $id = "softbank:$uid";
    return +{
      id     => $id,
      atoken => $id,
    };
  }
  if( _verify_value($param->[1], $sn) )
  {
    # accept.
    my $id = "softbank:$sn";
    return +{
      id     => $id,
      atoken => $id,
    };
  }
  defined($uid) or $uid = '';
  defined($sn)  or $sn  = '';
  $DEBUG and ::printmsg("$req->{peer}: $param->[0] pass $param->[1] does not match with '$uid' (uid), '$sn' (sn)");
  return;
}

sub _auth_au
{
  my $this  = shift;
  my $param = shift;
  my $req   = shift;

  #TODO: carrier ip-addresses range.
  # http://www.au.kddi.com/ezfactory/tec/spec/ezsava_ip.html
  my $subno = $req->{Header}{'X-UP-SUBNO'};
  if( !_verify_value($param->[1], $subno) )
  {
    defined($subno) or $subno = '';
    $DEBUG and ::printmsg("$req->{peer}: $param->[0] pass $param->[1] does not match with '$subno' (subno)");
    return;
  }
  my $id = return "au:$subno";
  return +{
    id     => $id,
    atoken => $id,
  };
}

# -----------------------------------------------------------------------------
# $this->_login($req).
# special case for _dispatch().
#
sub _login
{
  my $this = shift;
  my $req  = shift;
  my $path = $req->{path};

  $DEBUG and $this->_debug("$req->{peer}: login: process login dispatcher");

  if( $path eq '/' )
  {
    $this->_location($req, "/login");
  }elsif( $path eq '/login' )
  {
    my $done = $req->{Method} eq 'POST' && $this->_post_login($req);
    if( !$done )
    {
      my $html = $this->_gen_login($req);
      $this->_new_session($req);
      $this->_response($req, [html=>$html]);
    }
  }elsif( $path eq '/logout' )
  {
    # but not loged in.
    $this->_location($req, "/login");
  }elsif( $path eq '/style/style.css' )
  {
    $this->_response($req, [css=>'']);
  }else
  {
    $this->_response($req, 404);
    return;
  }
}

sub _post_login
{
  my $this = shift;
  my $req  = shift;

  my $cgi = $this->_get_cgi_hash($req);
  if( my $name = $cgi->{n} )
  {
    if( $req->{Header}{Cookie} )
    {
      $DEBUG and $this->_debug("$req->{peer}: _post_login: name=$name");
      $this->_new_session($req); # regen.
      $req->{session}{name} = $name;
      my $path = $cgi->{path} || "/";
      $this->_location($req, $path);
      return 1;
    }
    if( $cgi->{weak} )
    {
      $DEBUG and $this->_debug("$req->{peer}: _post_login: name=$name (weak session)");
      $this->_new_session($req); # regen.
      $req->{session}{name}  = $name;
      $req->{session}{_weak} = 1;
      my $path = $cgi->{path} || "/";
      $this->_location($req, $path);
      return 1;
    }
    $DEBUG and $this->_debug("$req->{peer}: _post_login: name=$name (no cookie)");
    return $this->_form_session($req);
  }

  $DEBUG and $this->_debug("$req->{peer}: _post_login: skip");
  undef;
}
sub _gen_login
{
  my $this = shift;
  my $req  = shift;

  my $tmpl = $this->_gen_login_html();
  $this->_expand($req, $tmpl, {
    NAME        => $this->_escapeHTML($req->{session}{name} || '' ),
    PATH        => '',
  });
}
sub _gen_login_html
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
  <title>login</title>
</head>
<body>
<div class="main">
<div class="uatype-<&UA_TYPE>">

<h1>Login</h1>

<form action="login" method="POST">
名前: <input type="text" name="n" value="<&NAME>" /><br />
<input type="submit" value="Login" /><br />
<input type="hidden" name="path" value="<&PATH>" />
</form>

</div>
</div>
</body>
</html>
HTML
}

sub _form_session
{
  my $this = shift;
  my $req  = shift;

  my $cgi = $this->_get_cgi_hash($req);
  my $name = $cgi->{n};
  defined($name) or die "no cgi.name";

  my $tmpl = $this->_gen_form_session_html();
  my $html = $this->_expand($req, $tmpl, {
    NAME        => $this->_escapeHTML($name),
    PATH        => '',
  });
  $this->_response($req, [html=>$html]);
  1;
}
sub _gen_form_session_html
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
  <title>login (weak session)</title>
</head>
<body>
<div class="main">
<div class="uatype-<&UA_TYPE>">

<h1>Login</h1>

<form action="login" method="POST">
名前: <input type="text" name="n" value="<&NAME>" /><br />
<input type="submit" value="Login" /><br />
<input type="hidden" name="path" value="<&PATH>" />
(<label for="weak"><input type="checkbox" name="weak" id="weak" />(※)弱いセッションを使う</label>)
</form>

<p>
(※) 携帯等Cookieの機能が使えない場合, 
代替手段としてクエリにセッションIDを埋め込みます.<br />
ログインしてもこのページが繰り返し表示されてしまう場合にのみ
チェックを入れてください.
</p>

</div>
</div>
</body>
</html>
HTML
}

# -----------------------------------------------------------------------------
# $this->_dispatch($req).
#
sub _dispatch
{
  my $this = shift;
  my $req  = shift;
  my $path = $req->{path};

  my $mode = $this->_get_req_param($req, 'mode');
  if( $mode ne 'owner' )
  {
    my $cgi = $this->_get_cgi_hash($req);
    my $cgi_dump = join('&', map{
      my $key = $_;
      my $val = $cgi->{$key};
      for($key, $val)
      {
        $_ =~ s/([%=\x00-\x1f])/'%'.pack("H*", $1)/ge;
      }
      "$key=$val";
    } sort keys %$cgi);
    $this->_debug("$req->{peer}: _dispatch: mode=$mode, path=[$path], cgi=[$cgi_dump], method=$req->{Method}");
  }

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
    my $ch_short_orig = $ch_short;
    my $netname_orig  = $netname;
    ($ch_short, $netname) = $this->_detect_channel($ch_short, $netname);
    if( !$ch_short )
    {
      RunLoop->shared_loop->notify_msg(__PACKAGE__."#_dispatch($path), not in cache ($netname_orig/$ch_short_orig)");
      $this->_response($req, 404);
      return;
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
  }elsif( $path eq '/login' )
  {
    $this->_login($req);
  }elsif( $path eq '/logout' )
  {
    $this->_delete_session($req);
    $this->_location($req, "/");
  }elsif( $path eq '/config' )
  {
    my $done = $req->{Method} eq 'POST' && $this->_post_config($req);
    if( !$done )
    {
      my $html = $this->_gen_config($req);
      $this->_response($req, [html=>$html]);
    }
  }else
  {
    $this->_response($req, 404);
  }
}

# ($ch_short, $netname) = $this->_detect_channel($ch_short, $netname).
sub _detect_channel
{
  my $this = shift;
  my $ch_short = shift;
  my $netname  = shift;

  if( $ch_short =~ s/^=// )
  {
    # priv or special channels.
    if( $this->{cache}{$netname}{$ch_short} )
    {
      return wantarray ? ($ch_short, $netname) : $ch_short;
    }
    foreach my $extract_line ( $this->config->extract_network('all') )
    {
      my ($extract, $sep) = split(' ', $extract_line);
      $sep ||= '@';
      my $ch_long = $this->_attach($ch_short, $netname, $sep);
      if( $this->{cache}{$extract}{$ch_long} )
      {
        return wantarray ? ($ch_long, $extract) : $ch_short;
      }
    }
    # not found.
    return undef;
  }

  if( $ch_short =~ s/^!// )
  {
    foreach my $key (keys %{$this->{cache}{$netname}})
    {
      $key =~ /^![0-9A-Z]{5}/ or next;
      substr($key, 6) eq $ch_short or next;
      return wantarray ? ($key, $netname) : $key;
    }
    # try decode from sjis.
    my $ch2 = Unicode::Japanese->new($ch_short,'sjis')->utf8;
    foreach my $key (keys %{$this->{cache}{$netname}})
    {
      $key =~ /^![0-9A-Z]{5}/ or next;
      substr($key, 6) eq $ch2 or next;
      return wantarray ? ($key, $netname) : $key;
    }

    foreach my $extract_line ( $this->config->extract_network('all') )
    {
      my ($extract, $sep) = split(' ', $extract_line);
      $sep ||= '@';
      my $ch_long  = $this->_attach($ch_short, $netname, $sep);
      my $ch_long2 = $this->_attach($ch2,      $netname, $sep);
      foreach my $key (keys %{$this->{cache}{$extract}})
      {
        $key =~ /^![0-9A-Z]{5}/ or next;
        my $subkey = substr($key, 6);
        if( $subkey eq $ch_long || $subkey eq $ch_long2 )
        {
          return wantarray ? ($key, $extract) : $key;
        }
      }
    }

    # not found.
    return undef;
  }

  # normal channels.
  $ch_short = '#'.$ch_short;
  if( $this->{cache}{$netname}{$ch_short} )
  {
    # found.
    return wantarray ? ($ch_short, $netname) : $ch_short;
  }

  foreach my $extract_line ( $this->config->extract_network('all') )
  {
    my ($extract, $sep) = split(' ', $extract_line);
    $sep ||= '@';
    my $ch_long = $this->_attach($ch_short, $netname, $sep);
    if( $this->{cache}{$extract}{$ch_long} )
    {
      return wantarray ? ($ch_long, $extract) : $ch_short;
    }
  }

  # try decode from sjis.
  my $ch2 = Unicode::Japanese->new($ch_short,'sjis')->utf8;
  if( $this->{cache}{$netname}{$ch2} )
  {
    return wantarray ? ($ch2, $netname) : $ch2;
  }

  # not found.
  return undef;
}

sub _response
{
  my $this = shift;
  my $req  = shift;
  my $res  = shift; # number or hash-ref or array-ref.

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
  if( $req->{cookies} )
  {
    my @cookies;
    foreach my $key (sort keys %{$req->{cookies}})
    {
      my $val = $req->{cookies}{$key};
      $key =~ /^[a-zA-Z]\w+\z/ or die "invalid cookie name: $key";
      if( defined($val) )
      {
        $val =~ s/([^-.\w])/'%'.unpack("H*",$1)/ge;
        length($val) >= 100 and die "value of cookies.$key is too long";
      }else
      {
        # delete.
        $val = "x; expires=Sun, 10-Jun-2001 12:00:00 GMT";
      }
      my $cookie = "$key=$val; path=$this->{path}";
      push(@cookies, $cookie);
    }
    if( @cookies )
    {
      ref($res) or $res = {
        Code => $res,
      };
      $res->{Header}{'Set-Cookie'} = $cookies[0];
      @cookies >= 2 and die "currently multiple cookies are not supported";
    }
  }

  if( $req->{session}{_weak} && ref($res) )
  {
    # HTTPコードだけの場合はLocation等もナイので書き換えの必要はなし.
    $this->_rewrite_html($req, $res);
  }

  my $cli = $req->{client};
  $cli->response($res);
  #$DEBUG and $this->_debug( Tools::HTTPParser->to_string($res) );

  # no Keep-Alive.
  $req->{client}->disconnect_after_writing();

  return;
}

# -----------------------------------------------------------------------------
# $this->_location($path).
# サイト内リダイレクト.
# weak-sessionであればSIDの付与は自動で行われる.
#
sub _location
{
  my $this = shift;
  my $req  = shift;
  my $path = shift;

  $DEBUG and $this->_debug("$req->{peer}: location: $path");
  $path = $this->{path} . $path;
  $path =~ s{//+}{/}g;
  if( $req->{session}{_weak} )
  {
    if( $path =~ /\?/ )
    {
      $path .= "&SID=$req->{session}{_sid}";
    }else
    {
      $path .= "?SID=$req->{session}{_sid}";
    }
  }
  my $res = {
    Code => 302,
    Header => {
      'Location' => $path,
    },
  };
  $this->_response($req, $res);
}

# -----------------------------------------------------------------------------
# $this->_rewrite_html($req, $res).
# weak-session時のHTML書き換え.
#
sub _rewrite_html
{
  my $this = shift;
  my $req  = shift;
  my $res  = shift;

  $req->{session}{_weak} or return;

  my $sid_enc = $this->_escapeHTML($req->{session}{_sid});

  $res->{Content} =~ s{(<.*?>)}{
    my $tag = $1;
    if( $tag =~ /^<form\b/ )
    {
      $tag .= qq{<input type="hidden" name="SID" value="$sid_enc" />};
    }else
    {
      $tag =~ s{\b(href|src)\s*=\s*(".*?"|[^\s>]*)}{
        my ($key, $val) = ($1, $2);
        my $quoted   = $val =~ s/^"(.*)"\z/$1/s;
        my $fragment = $val =~ s/(#.*)//s ? $1 : '';
        my ($path, $query) = split(/\?/, $val, 2);
        my @params;
        if( defined($query) )
        {
          @params = split(/[&;]/, $query);
          foreach my $pair (@params)
          {
            my ($k, $v) = split(/=/, $pair, 2);
            $k =~ tr/+/ /;
            $k =~ s/%([0-9a-f]{2})/pack("H*",$1)/ge;
            if( $k eq 'SID' )
            {
              $pair = undef;
            }
          }
          @params = grep{ defined($_) } @params;
        }
        push(@params, "SID=$sid_enc");
        my $new_val = $path . '?' . join('&', @params);
        if( $quoted )
        {
          $new_val = qq{"$new_val"};
        }
        "$key=$new_val";
      }ges;
    }
    $tag;
  }ges;

  $res->{Header}{'Content-Length'} = length($res->{Content});

  $res;
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
      auth  => [$block->auth('all')],
    };
    push(@conflist, $allow);
  }

  \@conflist;
}

# -----------------------------------------------------------------------------
# $match = _verify_value($enc, $plain).
# パスワードの比較検証.
# "{MD5}xxx" (MD5)
# "{SMD5}xxx" (Salted MD5, hex(md5(pass+salt)+salt)
# "{B}xxx"   (BASE64)
# "{RAW}xxx" (生パスワード)
# "{CRYPT}xxx" (cryptパスワード)
# "xxx"      (生パスワード)
#
sub _verify_value
{
  my $enc   = shift;
  my $plain = shift;
  if( !defined($enc) || !defined($plain) )
  {
    return undef;
  }
  my $type = $enc =~ s/^\{(.*?)\}// ? $1 : 'RAW';

  if( $type =~ /^(B|B64|BASE64)\z/ )
  {
    eval { require MIME::Base64; };
    if( $@ )
    {
      die "no MIME::Base64";
    }
    my $cmp = MIME::Base64::encode($plain, '');
    return $enc eq $cmp;
  }elsif( $type =~ /^(MD5)\z/ )
  {
    eval { require Digest::MD5; };
    if( $@ )
    {
      die "no Digest::MD5";
    }
    my $cmp = Digest::MD5::md5_hex($plain);
    return $cmp eq lc($enc);
  }elsif( $type =~ /^(SMD5)\z/ )
  {
    eval { require Digest::MD5; };
    if( $@ )
    {
      die "no Digest::MD5";
    }
    my $enc_hex  = substr($enc, 0, 32);
    my $enc_salt = pack("H*",substr($enc, 32));
    my $cmp = Digest::MD5::md5_hex($plain.$enc_salt);
    return $cmp eq lc($enc_hex);
  }elsif( $type =~ /^(RAW)\z/ )
  {
    return $enc eq $plain;
  }elsif( $type =~ /^(CRYPT)\z/ )
  {
    my $cmp = crypt($plain,substr($enc,0,2));
    if( length($plain) > 8 )
    {
      my $cmp2 = crypt(substr($plain, 0, 8),substr($enc,0,2));
      if( $cmp eq $cmp2 )
      {
        die "CRYPT supports upto 8 bytes";
        return;
      }
    }
    return $cmp eq $enc;
  }else
  {
    die "unsupported packed value, type=$type";
  }
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
    $DEBUG and $this->_debug("- can_show: $netname / $ch_short = ".($ok?"ok":"ng")." mask: ".join(", ",@{$allow->{masks}}));
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

  my $show_all;
  if( my $show = $this->_get_cgi_hash($req)->{show} )
  {
    $show_all = $show eq 'all';
  }

  # 表示できるネットワーク＆チャンネルを抽出.
  #
  my %channels;
  foreach my $netname (keys %{$this->{cache}})
  {
    foreach my $ch_short (keys %{$this->{cache}{$netname}})
    {
      my $ok = $this->_can_show($req, $ch_short, $netname);
      if( $ok )
      {
        my $cache  = $this->{cache}{$netname}{$ch_short};
        my $pack = {
          disp_netname  => $netname,
          disp_ch_short => $ch_short,
          anchor        => undef,
          unseen        => undef,
          unseen_plus   => undef,
        };

        my $recent = $cache->{recent} || [];
        my $seen = $req->{session}{seen}{$netname}{$ch_short} || 0;
        my $nr_unseen = 0;
        foreach my $r (reverse @$recent)
        {
          $r == $seen and last;
          ++$nr_unseen;
        }

        $pack->{unseen} = $nr_unseen;
        if( $nr_unseen == $this->{max_lines}{''} && $recent->[0] != $seen )
        {
          $pack->{unseen_plus} = 1;
        }

        if( $seen )
        {
          $pack->{anchor} = "L.$seen->{ymd}.$seen->{lineno}";
        }

        if( $nr_unseen > 0 || $show_all )
        {
          push(@{$channels{$netname}}, $pack);
        }
      }
    }
  }
  # 別のTiarraさんのネットワークを解凍(設定があったとき).
  my %new_channels;
  foreach my $extract_line ( $this->config->extract_network('all') )
  {
    my ($extract, $sep) = split(' ', $extract_line);
    $sep ||= '@';
    my $list = delete $channels{$extract} or next;
    foreach my $pack (@$list)
    {
      my $ch_long = $pack->{disp_ch_short};
      my ($ch_short, $netname, $is_explicit) = $this->_detach($ch_long, $sep);
      if( !$is_explicit )
      {
        # wrong separator?
        next;
      }
      if( $channels{$netname} && !$new_channels{$netname} )
      {
        # no merge.
        next;
      }
      $pack->{disp_netname}  = $netname;
      $pack->{disp_ch_short} = $ch_short;
      push(@{$new_channels{$netname}}, $pack);
    }
  }
  %channels = (%channels, %new_channels);

  # ネットワーク＆チャンネルの一覧をHTML化.
  #
  my $is_pc = $req->{ua_type} eq 'pc';
  my $content = "";
  $content .= $is_pc ? "<ul>\n" : "<div>\n";
  if( keys %channels )
  {
    foreach my $netname (sort keys %channels)
    {
      if( $is_pc )
      {
        $content .= "<li> $netname\n";
        $content .= "  <ul>\n";
      }else
      {
        $content .= "[$netname]<br />\n";
      }
      my @channels = @{$channels{$netname}};
      @channels = sort {$a->{disp_ch_short} cmp $b->{disp_ch_short}} @channels;
      my $seqno = 0;
      foreach my $pack (@channels)
      {
        my $channame = $pack->{disp_ch_short};
        ++$seqno;
        my $link_ch = $channame;
        if( $link_ch =~ s/^#// )
        {
          # normal channels.
        }elsif( $link_ch =~ s/^![0-9A-Z]{5}/!/ )
        {
          # channel    =  ( "#" / "+" / ( "!" channelid ) / "&" ) chanstring [ ":" chanstring ]
          # channelid  = 5( %x41-5A / digit )   ; 5( A-Z / 0-9 )
          # (RFC2812)
        }else
        {
          $link_ch = "=$link_ch";
        }
        my $link = "log\0$netname\0$link_ch\0";
        $link =~ s{/}{%252F}g;
        $link =~ tr{\0}{/};
        $link = $this->_escapeHTML($link);

        my $unseen;
        if( !$pack->{unseen} )
        {
          $unseen = '';
        }else
        {
          my $nr_unseen = $pack->{unseen};
          my $plus      = $pack->{unseen_plus} ? '+' : '';
          $unseen = " ($nr_unseen$plus)";
        }

        my $channame_label = $this->_escapeHTML($channame);
        $channame_label =~ s/^![0-9A-Z]{5}/!/;
        my $ref = $pack->{anchor} ? "?x=$pack->{anchor}" : '';
        if( $is_pc )
        {
          $content .= qq{    <li><a href="$link$ref">$channame_label</a>$unseen</li>\n};
        }else
        {
          $content .= qq{$seqno. <a href="$link$ref">$channame_label</a>$unseen<br />\n};
        }
      }
      if( $is_pc )
      {
        $content .= "  </ul>\n";
        $content .= "</li>\n";
      }
    }
  }else
  {
    $content = $is_pc ? "<li>no channels</li>\n" : "no channels\n";
  }
  $content .= $is_pc ? "</ul>\n" : "<div\n>";

  my $shared_box = '';
  my $mode = $this->_get_req_param($req, 'mode');
  if( $mode ne 'owner' )
  {
    $shared_box .= "<br />\n";
    $shared_box .= "[\n";
    $shared_box .= qq{<a href="config">設定</a>\n};
    $shared_box .= "|\n";
    $shared_box .= qq{<a href="logout">ログアウト</a>\n};
    $shared_box .= "]\n";
  }
  my $tmpl = $this->_gen_list_html();
  $this->_expand($req, $tmpl, {
    CONTENT => $content,
    SHOW_TOGGLE_LABEL => $show_all ? 'MiniList' : 'ShowAll',
    SHOW_TOGGLE_VALUE => $show_all ? 'updated' : 'all',
    SHARED_BOX => $shared_box,
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

<form action="./" method="POST">
ENTER: <input type="text" name="enter" value="" />
<input type="submit" value="入室" /><br />
</form>

<p>
[
<a href="./" accesskey="0">再表示</a>[0] |
<a href="./?show=<&SHOW_TOGGLE_VALUE>" accesskey="#"><&SHOW_TOGGLE_LABEL></a>[#]
]
<&SHARED_BOX>
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
      $DEBUG and $this->_debug("enter: $netname/$ch_short");
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
  my $req  = shift;
  my $tmpl = shift;
  my $vars = shift;

  my $top_path_esc  = $this->_escapeHTML($this->{path});
  my $css_esc       = $this->_escapeHTML($this->config->css || "$this->{path}style/style.css");
  my $site_name_esc = $this->_escapeHTML($this->config->site_name || $DEFAULT_SITE_NAME);
  $req->{ua_type} =~ /^\w+\z/ or die "invalid ua_type: [$req->{ua_type}]";
  my $common_vars = {
    TOP_PATH  => $top_path_esc,
    CSS       => $css_esc,
    UA_TYPE   => $req->{ua_type},
    SITE_NAME => $site_name_esc,
    VERSION   => '-',
  };
  if( $req->{session}{name} )
  {
    $common_vars->{VERSION} = $VERSION;
  }

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
      my $topic = $chan->topic || $NO_TOPIC;
      my $topic_esc = $this->_escapeHTML($topic);
      $content .= "<p>\n";
      $content .= "<span class=\"chan-topic\">TOPIC: $topic_esc</span><br />\n";
      $content .= "</p>\n";
    }
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
  if( my $xtoken = $cgi->{x} )
  {
    my $re = qr/\Q$xtoken\E\z/;
    foreach my $i ($rindex..$#$recent )
    {
      my $info = $recent->[$i];
      my $anchor = "L.$info->{ymd}.$info->{lineno}";
      if( $anchor =~ $re )
      {
        if( $i < $#$recent )
        {
          $rindex = $i + 1;
        }else
        {
          $rindex = $#$recent;
        }
        last;
      }
    }
  }

  my $last;
  if( $rindex + $show_lines > @$recent )
  {
    $last = $#$recent;
  }else
  {
    $last = $rindex + $show_lines - 1;
  }

  # 既読情報の更新.
  my $last_seen_index;
  if( my $cur = $req->{session}{seen}{$netname}{$ch_short} )
  {
    foreach my $i ($last+1 .. $#$recent)
    {
      if( $recent->[$i] == $cur )
      {
        $last_seen_index = $i;
        last;
      }
    }
  }
  if( !defined($last_seen_index) )
  {
    $last_seen_index = $last;
    my $last_seen = @$recent ? $recent->[$last] : undef;
    $req->{session}{seen}{$netname}{$ch_short} = $last_seen;
  }

  my $next_index = $last < $#$recent ? $last + 1 : $#$recent;
  my $prev_index = $rindex < $show_lines ? 0 : ($rindex - $show_lines);
  my ($next_rtoken, $prev_rtoken, $last_seen_rtoken) = map {
    my $i = $_;
    my $info = @$recent ? $recent->[$i] : {ymd=>'-00',lineno=>0};
    my $anchor = "L.$info->{ymd}.$info->{lineno}";
    $anchor =~ s/.*-//;
    $anchor;
  } $next_index, $prev_index, $last_seen_index;

  my $nr_cached_lines = @$recent;
  my $lines2 = $nr_cached_lines==1 ? 'line' : 'lines';
  $recent = [ @$recent [ $rindex .. $last ] ];

  my $navi_raw = '';
  if( @$recent )
  {
    my $sort_order = $this->_get_req_param($req, 'sort-order');
    $DEBUG and $this->_debug("sort_order = $sort_order");
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

      my $a_tag = qq{<a id="$anchor" href="?r=$rtoken">};
      if( $line_html !~ s{^(\d\d:\d\d(?::\d\d)?)}{$a_tag$1</a>} )
      {
        $line_html = "$a_tag$info->{lineno}</a>/" . $line_html;
      }
      $content .= $line_html . "\n";
    }
    $content .= "</pre>\n";
  }else
  {
    $content .= "<p>\n";
    $content .= "no lines.";
    $content .= "</p>\n";
  }

  my $ch_long = Multicast::attach($ch_short, $netname);
  $ch_long =~ s/^![0-9A-Z]{5}/!/;
  my $ch_long_esc = $this->_escapeHTML($ch_long);
  my $name_esc = $this->_escapeHTML($req->{session}{name} || '');

  my $mode = $this->_get_req_param($req, 'mode');
  my $name_marker_raw = '';
  if( $mode ne 'owner' )
  {
    $name_marker_raw = qq{$name_esc&gt; };
  }

  my $h1_ch_long_raw;
  if( $req->{ua_type} eq 'pc' )
  {
    $h1_ch_long_raw = "<h1>$ch_long_esc</h1>";
  }else
  {
    $h1_ch_long_raw = "<b>$ch_long_esc</b>";
  }

  my $tmpl = $this->_gen_log_html();
  $this->_expand($req, $tmpl, {
    CONTENT_RAW => $content,
    NAVI_RAW    => $navi_raw,
    CH_LONG => $ch_long_esc,
    H1_CH_LONG_RAW => $h1_ch_long_raw,
    NAME    => $name_esc,
    NAME_MARKER_RAW => $name_marker_raw,
    RTOKEN  => $next_rtoken,
    NEXT_RTOKEN => $next_rtoken,
    PREV_RTOKEN => $prev_rtoken,
    LAST_SEEN_RTOKEN => $last_seen_rtoken,
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

<&H1_CH_LONG_RAW>

<&CONTENT_RAW>

<form action="./" method="POST">
<p>
talk:<&NAME_MARKER_RAW><input type="text" name="m" size="60" />
  <input type="submit" value="発言/更新" /><br />
<input type="hidden" name="x" size="10" value="<&LAST_SEEN_RTOKEN>" />
</p>
</form>

<&NAVI_RAW>

<p>
[
<a href="./?x=<&LAST_SEEN_RTOKEN>" accesskey="*">更新</a>[*] |
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
    if( $val !~ /^(?:owner|shared)\z/ )
    {
      $val = 'owner';
    }
  }
  if( $key eq 'sort-order' )
  {
    $val ||= 'asc';
    $val = $val =~ /^(?:desc|rev)/ ? 'desc' : 'asc';
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
        $val =~ tr/+/ /;
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
      $val =~ tr/+/ /;
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
  if( my $m = $cgi->{m} )
  {
    if( $mode ne 'owner' )
    {
      my $name = $req->{session}{name} or die "no session.name";
      $m = "$name> $m";
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

  my ($topic_disp_esc, $topic_esc, $names_esc);
  if( my $net = $this->_runloop->network($netname) )
  {
    if( my $chan = $net->channel($ch_short) )
    {
      my $topic = $chan->topic;
      defined($topic) or $topic = '';
      my $topic_disp = $topic eq '' ? $NO_TOPIC : $topic;

      my $names = $chan->names || {};
      $names = [ values %$names ];
      @$names = map{
        my $pic = $_; # $pic :: PersonInChannel.
        my $nick  = $pic->person->nick;
        my $sigil = $pic->priv_symbol;
        "$sigil$nick";
      } @$names;
      @$names = sort @$names;
      $topic_disp_esc = $this->_escapeHTML($topic_disp);
      $topic_esc = $this->_escapeHTML($topic);
      $names_esc = $this->_escapeHTML(join(' ', @$names));
    }
  }else
  {
    $topic_disp_esc = $NO_TOPIC;
    $topic_esc = '';
    $names_esc = '';
  }

  my $in_topic_esc;
  my $cgi = $this->_get_cgi_hash($req);
  if( defined(my $in_topic = $cgi->{topic}) )
  {
    $in_topic_esc = $this->_escapeHTML($in_topic);
  }else
  {
    $in_topic_esc = $topic_esc;
  }

  my $ch_long = Multicast::attach($ch_short, $netname);
  $ch_long =~ s/^![0-9A-Z]{5}/!/;
  my $ch_long_esc = $this->_escapeHTML($ch_long);

  my $tmpl = $this->_tmpl_chan_info();
  $tmpl =~ s{<!begin:no_shared_mode>\s*(.*)<!end:no_shared_mode>\s*}{
    my $mode = $this->_get_req_param($req, 'mode');
    $mode eq 'owner' ? $1 : '';
  }ges;
  $this->_expand($req, $tmpl, {
    CONTENT_RAW => $content_raw,
    CH_LONG   => $ch_long_esc,
    TOPIC     => $topic_disp_esc,
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

<form action="./info" method="POST">
TOPIC: <span class="chan-topic"><&TOPIC></span><br />
<input type="text" name="topic" value="<&IN_TOPIC>" />
<input type="submit" value="変更" /><br />
</form>

<p>
参加者: <span class="chan-names"><&NAMES></span><br />
</p>

<!begin:no_shared_mode>
<form action="./info" method="POST">
PART: <input type="text" name="part" value="<&PART_MSG>" />
<input type="submit" value="退室" /><br />
</form>

<form action="./info" method="POST">
JOIN <input type="hidden" name="join" value="<&CH_LONG>" />
<input type="submit" value="入室" /><br />
</form>

<form action="./info" method="POST">
DELETE <input type="hidden" name="delete" value="<&CH_LONG>" />
<input type="submit" value="削除" /><br />
</form>
<!end:no_shared_mode>

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
      my $chan = $network->channel($ch_short);
      my $cur_topic = $chan ? $chan->topic : undef;
      if( !defined($cur_topic) || $cgi->{topic} ne $cur_topic )
      {
        my $for_server = $msg_to_send->clone;
        $for_server->param(0, $ch_short);
        $network->send_message($for_server);
      }else
      {
        $this->_debug("$req->{peer}: topic not changed cur=[$cur_topic] new=[$cgi->{topic}]");
      }
    }
  }

  if( exists($cgi->{part}) )
  {
    my $mode = $this->_get_req_param($req, 'mode');
    if( $mode eq 'owner' )
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

    }else
    {
      $this->_debug("$req->{peer}: part is not allowed when mode is not 'owner'");
    }
  }

  if( exists($cgi->{join}) )
  {
    my $mode = $this->_get_req_param($req, 'mode');
    if( $mode eq 'owner' )
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

    }else
    {
      $this->_debug("$req->{peer}: join is not allowed when mode is not 'owner'");
    }
  }

  if( exists($cgi->{'delete'}) )
  {
    my $mode = $this->_get_req_param($req, 'mode');
    if( $mode eq 'owner' )
    {

    delete $this->{cache}{$netname}{$ch_short};
    if( !keys %{$this->{cache}{$netname}} )
    {
      delete $this->{cache}{$netname};
    }
    $this->_location($req, "/");
    return 1;

    }else
    {
      $this->_debug("$req->{peer}: delete is not allowed when mode is not 'owner'");
    }
  }

  return undef;
}

# -----------------------------------------------------------------------------
# $html = $this->_gen_config($req).
#
sub _gen_config
{
  my $this = shift;
  my $req  = shift;

  my $name_esc = $this->_escapeHTML( $req->{session}{name} || '' );

  my $tmpl = $this->_tmpl_config();
  $this->_expand($req, $tmpl, {
    NAME      => $name_esc,
  });
}
sub _tmpl_config
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
  <title>設定</title>
</head>
<body>
<div class="main">
<div class="uatype-<&UA_TYPE>">

<h1>設定</h1>

<form action="./config" method="POST">
名前: <input type="text" name="n" value="<&NAME>" /><br />
<input type="submit" value="変更" /><br />
</form>

<p>
System::WebClient version <&VERSION>.
</p>

<p>
[
<a href="./" accesskey="*">戻る</a>[*] |
<a href="<&TOP_PATH>" accesskey="0">List</a>[0] |
<a href="config" accesskey="#">再表示</a>[#]
]
</p>

</div>
</div>
</body>
</html>
HTML
}

sub _post_config
{
  my $this = shift;
  my $req  = shift;

  my $cgi = $this->_get_cgi_hash($req);
  if( $cgi->{n} )
  {
    my $old = $req->{session}{name} || '-';
    $this->_debug("$req->{peer}: rename: $old => $cgi->{n}");

    $req->{session}{name} = $cgi->{n};
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

# ($ch_short, $net_name, $explicit) = $this->_detach($ch_long, $sep);
# $ch_short = $this->_detach($ch_long, $sep);
sub _detach {
    my $this = shift;
    my $str  = shift;
    my $sep  = shift;

    if (!defined $str) {
	die "Arg[0] was undef.\n";
    }
    elsif (ref($str) ne '') {
	die "Arg[0] was ref.\n";
    }

    my @result;
    if ((my $sep_index = index($str,$sep)) != -1) {
	my $before_sep = substr($str,0,$sep_index);
	my $after_sep = substr($str,$sep_index+length($sep));
	if ((my $colon_pos = index($after_sep,':')) != -1) {
	    # #さいたま@taiyou:*.jp  →  #さいたま:*.jp + taiyou
	    @result = ($before_sep.substr($after_sep,$colon_pos),
		       substr($after_sep,0,$colon_pos),
		       1);
	}
	else {
	    # #さいたま@taiyou  →  #さいたま + taiyou
	    @result = ($before_sep,$after_sep,1);
	}
    }
    else {
	@result = ($str,$this->_runloop->default_network,undef);
    }
    return wantarray ? @result : $result[0];
}

sub _attach {
    # $strはChannelInfoのオブジェクトでも良い。
    # $network_nameは省略可能。IrcIO::Serverのオブジェクトでも良い。
    my $this = shift;
    my $str  = shift;
    my $network_name = shift;
    my $separator    = shift;

    if (ref($str) eq 'ChannelInfo') {
	$str = $str->name;
    }
    if (ref($network_name) eq 'IrcIO::Server') {
	$network_name = $network_name->network_name;
    }

    if (!defined $str) {
	die "Arg[0] was undef.\n";
    }
    elsif (ref($str) ne '') {
	die "Arg[0] was ref.\n";
    }

    $network_name = $this->_runloop->default_network if $network_name eq '';
    if ((my $pos_colon = index($str,':')) != -1) {
	# #さいたま:*.jp  →  #さいたま@taiyou:*.jp
	$str =~ s/:/$separator.$network_name.':'/e;
    }
    else {
	# #さいたま  →  #さいたま@taiyou
	$str .= $separator.$network_name;
    }
    $str;
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
bind-port: 8667
path: /irc
css:  /irc/style/style.css
# 上の設定をapacheでReverseProxyさせる場合, httpd.conf には次のように設定.
#  ProxyPass        /irc/ http://localhost:8667/irc/
#  ProxyPassReverse /irc/ http://localhost:8667/irc/
#  <Location /irc/>
#  ...
#  </Location>

# ReverseProxy 利用時の追加設定.
# 接続元が全部プロキシサーバになっちゃうのでその対応.
# ReverseProxy 使わず直接公開の場合は不要.
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
  # auth: <user> <pass>
  # auth: :basic <user> <pass>
  # auth: :softbank <端末ID>
  # auth: :softbank <UID>
  # auth: :au <SUBNO>
  # 各値(<pass>等)には {MD5}xxxx や {B}xxx や {CRYPT}xxx を利用可能.
  # そのままべた書きも出来るけれど.
  auth: :basic user pass
  # 公開するチャンネルの指定.
  mask: #*@*
  mask: *@*
}
allow-public {
  host: *
  auth: :basic user2 pass2
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

# name-default 設定は VERSION 0.05 で廃止されました.
# # 発言BOXで名前指定しなかったときのデフォルトの名前.
# # mode: shared の時に使われる.
# -name-default: (noname)

# 外部にTiarraさんを使っているときに, そこのネットワークを切り出して表示する.
# exteact-network: <netname> <remote-sep>
# <netname> ::= このTiarraさんから見たときの外部Tiarraさんのネットワーク名.
#               (このtiarra.confで指定しているネットワーク名)
# <remote-sep> ::= 外部Tiarraさんで使っているセパレータ.
#                  (こっちはこのtiarra.confのではないです)
#                  省略すると @ と仮定.
-exteact-network: tiarra
-exteact-network: tiarra @

=end tiarra-doc

=cut
