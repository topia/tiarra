## ----------------------------------------------------------------------------
#  Auto::FetchTitle.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::FetchTitle;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Tools::HTTPClient);
use Module::Use qw(Auto::FetchTitle::Plugin);
use Auto::FetchTitle::Plugin;
use Auto::Utils;
use Configuration; # Configuration::Hook.
use Mask;
use Multicast;
use Scalar::Util qw(weaken);
use Tiarra::Encoding;
use Tools::HTTPClient;

our $VERSION   = '0.03';

# 全角空白.
our $U_IDEOGRAPHIC_SPACE = "\xe3\x80\x80";
our $RE_WHITESPACES = qr/(?:\s|$U_IDEOGRAPHIC_SPACE)+/;

# デバッグフラグ.
# configや$this->{debug}の値もlocal()内で反映される.
our $DEBUG = 0;

our $ENCODER = 'Unicode::Japanese';
use Unicode::Japanese;

# LATIN-1 を JIS で通る物にマッピング.
#
our @LATIN1_MAP = qw(
  0 0 0 ∫ 0 … † ‡  ^ ‰  s < 0 OE Z 0
  0 0 0 0 0 0 0 0  ~ TM S > 0 oe z y
  0  ! ¢ £ 0 \ 0  §   ¨ (C) 0 《 ￢ 0 (R) ￣
  ゜ ± 0 0 ´ μ ¶  ・  0 0 0 》 1/4 1/2 3/4  ?
  A  A A A A A AE C   E E E E I I I  I
  D  N O O O O O  ×   O U U U U Y TH ss
  a  a a a a a ae c   e e e e i i i  i
  th n o o o o o  ÷   o u u u u y th y
);
$LATIN1_MAP[0x82-0x80] = ',';
$LATIN1_MAP[0xa0-0x80] = ' ';

our $TOP_LEVEL_DOMAINS = {
  map{ $_=>1 } qw(.biz  .com  .edu  .gov  .info  .int  .mil  .net  .org
  .aero  .asia  .cat  .coop  .jobs  .mobi  .museum  .tel  .travel)
};

our $HAS_IMAGE_EXIFTOOL = do{
  eval{ local($SIG{__DIE__}) = 'DEFAULT'; require Image::ExifTool; };
  !$@;
};

our $MAX_ACTIVE_REQUESTS        = 3;
our $MAX_URLS_IN_SINGLE_MESSAGE = 3;
our $DEFAULT_RECV_LIMIT         = 4*1024; # 4K bytes.
our $DEFAULT_TIMEOUT            = 3;  # sec.
our $MAX_REDIRECTS              = 5;
our $MAX_REDIRECTS_LIMIT        = 20;
our $PROCESSING_LIMIT_TIME      = 60; # secs.

$|=1;
1;

# -----------------------------------------------------------------------------
# [処理の流れ]
# FLOW-1st:
#  new().
#  <loop>
#    message_arrived().
#  </loop>
#  destruct().
#
# FLOW-2nd: tiarra-module handler/$obj->message_arrived
#   $obj->_dispatch(..).
#   <if debug-comment>
#     $obj->_process_command(..).
#     return.
#   </if>
#   $obj->_extract_urls(..).
#   $obj->_check_mask($url).
#   $obj->_create_request(..).
#   $obj->_add_request($req).
#     (drop orphan requests/_close_request)
#     $obj->_start_request($req).
#
# FLOW-3rd: _start_request()
#   setup headers.
#   apply prereq filter.
#   check redirects on prereq.
#   start HTTP client.
#     finish Callback  => $obj->_request_finished($req, @_).
#     ProgressCallback => $obj->_request_progress($req, @_) => _request_finished().
#
# FLOW-4th: _request_finished.
#   $obj->_close_request($req).
#   $obj->_reply().
#
# FLOW-5th: _close_request().
#   $obj->_close_head_request().
#     $obj->_parse_response().
#     apply response filter.
#     check redirects on response/_start_request().

# -----------------------------------------------------------------------------
# my $obj = $pkg->new().
#
sub new
{
  my $pkg  = shift;
  my $this = $pkg->SUPER::new(@_);

  $this->{loaded_at}     = time;
  $this->{debug}         = $this->config->debug;

  $this->{request_queue} = {};   # { $ch_full => [] }.
  $this->{reply_queue}   = undef;
  $this->{reply_timer}   = undef;

  $this->{mask} = undef;
  $this->{plugins} = undef;
  $this->{hooks}   = undef;

  $this->_reload_config();
  $this->_reload_plugins();

  my $weaken_this = $this;
  weaken($weaken_this);
  $this->{conf_hook} = Configuration::Hook->new(sub{
    my $this = $weaken_this or return;
    $this->_reload_config();
    $this->_reload_plugins();
  })->install('reloaded');

  return $this;
}

# -----------------------------------------------------------------------------
# $obj->destruct().
#
sub destruct
{
  my $this = shift;
  if( $this->{reply_timer} )
  {
    $this->{reply_timer}->uninstall();
    $this->{reply_timer} = undef;
  }
  if( $this->{conf_hook} )
  {
    $this->{conf_hook}->uninstall();
    $this->{conf_hook} = undef;
  }

  $this->run_hook('plugin.finalize', undef);
}

# -----------------------------------------------------------------------------
# $obj->_reload_config().
#
sub _reload_config
{
  my $this = shift;

  $this->_runloop->notify_msg(__PACKAGE__.", reload config.");
  $this->{debug} = $this->config->debug;
  if( $this->{debug} && $this->{debug} =~ /^(off|no|false)/i )
  {
    $this->{debug} = undef;
  }

  $this->{mask} = [];
  foreach my $line ($this->config->mask('all'))
  {
    my ($ch_mask, @opts) = split(' ', $line);
    $ch_mask or next;

    # #Tiarra@ircnet:*.jp か $#Tiarra:*.jp@ircnet か
    # 紛らわしいのでmaskがどっちでもマッチするように.
    # (正しくは前者)
    # マッチさせるチャンネル名はプログラム内の物なので必ず前者形式のはず.
    my ($ch_mask_short, $ch_mask_net, $explicit) = Multicast::detach($ch_mask);
    if( $explicit )
    {
      $ch_mask = Multicast::attach($ch_mask_short, $ch_mask_net);
    }

    my @conf;
    while( @opts && $opts[0] =~ s/^&// )
    {
      my $confkey = shift @opts;
      push(@conf, $this->config->get("conf-$confkey", 'block'));
    }
    my $url_mask = shift @opts || '*';
    my $mask = {
      _line    => $line,
      ch_mask  => $ch_mask,
      url_mask => $url_mask,
      conf     => \@conf,
    };
    push(@{$this->{mask}}, $mask);
  }
}

# -----------------------------------------------------------------------------
# @plugins = $obj->plugins().
#
sub plugins
{
  my $this = shift;

  if( !$this->{plugins} )
  {
    $this->_reload_plugins();
  }

  @{$this->{plugins}};
}

# -----------------------------------------------------------------------------
# $obj->_reload_plugins().
# reload plugins list.
#
sub _reload_plugins
{
  my $this = shift;

  my $loader;
  my @plugins;
  eval{
    local($SIG{__DIE__}) = 'DEFAULT';
    require Module::Pluggable;
    Module::Pluggable->import(sub_name => '_load_plugins', require => 1);
    @plugins = $this->_load_plugins;
    @plugins = grep{ !/::SUPER$/ } @plugins;
    $loader = 'Module::Pluggable';
  };
  if( $@ )
  {
    RunLoop->shared_loop->notify_msg("Module::Pluggable failed: $@");
    $loader = 'local';
    @plugins = $this->_find_local_plugins;
  }

  $this->{plugins} = [];
  $this->{hooks} = {};

  $this->register_hook(undef, {
    name   => 'basic',
    'filter.prereq' => \&_filter_basic_prereq,
    old    => 1,
  });
  $this->register_hook(undef, {
    name   => 'cookie',
    'filter.prereq' => \&_filter_cookie_prereq,
    old    => 1,
  });
  $this->register_hook(undef, {
    name     => 'uploader',
    'filter.prereq'   => \&_filter_uploader_prereq,
    'filter.response' => \&_filter_uploader_response,
    old      => 1,
  });

  RunLoop->shared_loop->notify_msg(__PACKAGE__."#_reload_plugins, ($loader) plugins:");
  if( @plugins )
  {
    Module::Use->import(@plugins);
    my $plugins_conf = $this->config->plugins;
    $plugins_conf = ref($plugins_conf) && UNIVERSAL::isa($plugins_conf, 'Configuration::Block') && $plugins_conf;
    foreach my $pkgname (@plugins)
    {
      my $mininame = $pkgname;
      $mininame =~ s/^Auto::FetchTitle::Plugin:://;
      my $plugin = {
        module => $pkgname,
        object => undef,
      };
      eval "require $pkgname; 1"; $@ and RunLoop->shared_loop->notify_msg("load $pkgname: $@");
      my $conf = $plugins_conf && $plugins_conf->get($mininame);
      $conf = ref($conf) && UNIVERSAL::isa($conf, 'Configuration::Block') ? $conf : Configuration::Block->new();
      my $obj = eval{ $pkgname->new($conf); };
      if( !$obj )
      {
        RunLoop->shared_loop->notify_msg("- $pkgname ".($@?"error $@":"ignore"));
        next;
      }
      RunLoop->shared_loop->notify_msg("+ $pkgname $obj");
      $plugin->{object} = $obj;
      push(@{$this->{plugins}}, $plugin);
      $obj->register($this);
    }
  }else
  {
    RunLoop->shared_loop->notify_msg("- none");
  }

  $this->run_hook('plugin.initialize', undef);
}

# -----------------------------------------------------------------------------
# $obj->_find_local_plugins().
# rollback of Module::Pluggable.
#
sub _find_local_plugins
{
  my $this = shift;
  my $dir     = 'module/Auto/FetchTitle/Plugin';
  my $modbase = 'Auto::FetchTitle::Plugin';
  if( opendir(my $dh, $dir) )
  {
    my @files = readdir($dh);
    closedir($dh);
    my @plugins;
    foreach my $file (@files)
    {
      $file =~ /^([a-zA-Z_]\w*)\.pm\z/ or next;
      my $name    = $1; # untaint.
      my $modpath = "$dir/$name.pm";
      my $modname = $modbase.'::'.$name;
      eval{ local($SIG{__DIE__}) = 'DEFAULT'; require $modpath; };
      if( $@ )
      {
        RunLoop->shared_loop->notify_msg("_find_local_plugins, load $modpath failed: $@");
        next;
      }
      push(@plugins, $modname);
    }
    return @plugins;
  }else
  {
    RunLoop->shared_loop->notify_msg("_find_local_plugins, opendir($dir): $!");
    return;
  }
}

sub register_hook
{
  my $this    = shift;
  my $plugin_obj = shift;
  my $spec    = shift;
  my $name    = $spec->{name} or die "no hook name for $plugin_obj";
  $this->{hooks}{$name} and die "hook $name is already registered";

  $spec->{object} = $plugin_obj;
  weaken($spec->{object});

  $this->{hooks}{$name} = $spec;
  $plugin_obj->{hook}   = $spec;
}

# -----------------------------------------------------------------------------
# $obj->message_arrived($msg, $sender).
# (impl:tiarra-module)
#
sub message_arrived
{
  my $this   = shift;
  my $msg    = shift;
  my $sender = shift;

  my($RESULT) = [$msg];

  # サーバーからのメッセージ以外無視.
  # (=クライアントからのメッセージを無視)
  #if( !$sender->isa('IrcIO::Server') )
  #{
  #  return @$RESULT;
  #}

  # PRIVMSG は無視.
  if( $msg->command ne 'PRIVMSG' )
  {
    return @$RESULT;
  }

  eval{
    $this->_dispatch($msg, $sender, $RESULT);
  };
  if( $@ )
  {
    my $ch = Auto::Utils::get_full_ch_name($msg, 0);
    $this->_reply($ch, "DIED: $@");
  }

  return @$RESULT;
}

# -----------------------------------------------------------------------------
# $obj->_dispatch($msg, $sender, $result).
# dispatcher.
#
sub _dispatch
{
  my $this   = shift;
  my $msg    = shift;
  my $sender = shift;
  my $result = shift;

  my ($get_ch_name,$reply_in_ch,$reply_as_priv,$reply_anywhere, $get_full_ch_name)
    = Auto::Utils::generate_reply_closures($msg,$sender,$result);
  my $full_ch_name = $get_full_ch_name->();

  local($DEBUG) = $DEBUG || $this->{debug};

  my $msgval = $msg->param(1);
  $DEBUG and $this->_debug($full_ch_name, "debug: msgval = [$msgval]");

  # デバッグ用コマンド.

  my $debug_command = $this->config->debug_command || 'fetchtitle:';
  if( $msgval =~ s/^\Q$debug_command\E(?:$RE_WHITESPACES)*// )
  {
    $DEBUG and $this->_debug($full_ch_name, "debug: goto process command");
    $this->_process_command($msg, $sender, $result, $msgval);
    return;
  }

  $DEBUG and $this->_debug($full_ch_name, "debug: goto extract urls");
  my @urls = $this->_extract_urls($msgval);
  $DEBUG and $this->_debug($full_ch_name, "debug: ".@urls." url".(@urls==1?'':'s')." found");
  if( !@urls )
  {
    return;
  }

  my $count = 0;
  foreach my $_url (@urls)
  {
    if( $count >= $MAX_URLS_IN_SINGLE_MESSAGE )
    {
      $DEBUG and $this->_debug($full_ch_name, "debug: too many urls");
      last;
    }
    $DEBUG and $this->_debug($full_ch_name, "debug: check $_url");
    my $url = $_url;
    $url =~ s{^ttp(s?)://}{http$1://};
    $url =~ m{^https?://} or next;
    $url =~ s{^https?://[-\w.\x80-\xff]+\z}{$url/};
    $DEBUG && $url ne $_url and $this->_debug($full_ch_name, "debug: fixed url is $url");

    # 処理対象か確認.
    my $matched = $this->_check_mask($full_ch_name, $url);
    if( !$matched )
    {
      $DEBUG and $this->_debug($full_ch_name, "debug: no match");
      next;
    }

    ++$count;

    # リクエストの生成.
    my $req = $this->_create_request($full_ch_name, $url, $matched);
    $req->{cookie_jar} = [];
    #$this->_debug($req, "new-request: ".Data::Dumper->new([$req])->Indent(0)->Dump);
    $this->_add_request($req);
  }

  $DEBUG and $this->_debug($full_ch_name, "debug: dispatch done.");
  return;
}

# -----------------------------------------------------------------------------
# $req = $this->_create_request($full_ch_name, $url, $mask_conf);
# (補足までにリクエストが生成されるのは_dispatch()と_redirect()の２箇所)
#
sub _create_request
{
  my $this         = shift;
  my $full_ch_name = shift;
  my $url          = shift;
  my $mask_conf    = shift;

  my $url_orig = $url;
  $url =~ s/([^ -~])/'%'.uc(unpack("H*",$1))/ge;
  if( $url ne $url_orig )
  {
    $this->_debug($full_ch_name, "url will be encoded: $url");
    $this->_debug($full_ch_name, "original is: $url_orig");
  }

  my $anchor;
  ($url, $anchor) = split(/#/, $url, 2);
  my $req = {
    old          => undef,    # undef for first (non-redirect) request.
    ini_req      => undef,    # undef for first (non-redirect) request.
    redirected   => undef,    # nr of redirects (integer).
    applied_filters => undef,    # array-ref.

    url          => $url,
    anchor       => $anchor,
    full_ch_name => $full_ch_name,
    mask         => $mask_conf,

    requested_at => time,
    started_at   => undef,
    active       => undef,
    timer        => undef,

    httpclient   => undef,
    addr_checked => undef,
    headers      => {},
    cookies      => [],    # cookies for this request.
    recv_limit   => $DEFAULT_RECV_LIMIT,
    max_redirects=> undef, # integer.
    timeout      => undef,
    response     => undef,
    result       => undef,
    method       => undef,
    content      => undef,
    cookie_jar   => undef, # session cookies, set at initial _create_request() call.
  };
  $req;
}

# -----------------------------------------------------------------------------
# $matched_mask = $this->_check_mask($full_ch_name, $url);
# チャンネルとURLから, 利用する mask: 行を１つ抽出.
# マッチした許可マスク定義HASH-refを返す.
# {
#   ch_mask  => $ch_mask,  # mask: のチャンネル指定部分(必須).
#   url_mask => $url_mask, # mask: のURL指定部分(省略'*').
#   conf     => \@conf,    # mask: のconfに対応するブロックのリスト(Configuration::Block).
# };
#
sub _check_mask
{
  my $this = shift;
  my $full_ch_name = shift;
  my $url  = shift;

  foreach my $mask (@{$this->{mask}})
  {
    my $chan_match = Mask::match($mask->{ch_mask},  $full_ch_name);
    if( !$chan_match )
    {
      defined($chan_match) or next;
      $DEBUG and $this->_debug($full_ch_name, "debug: - channel denied: [$full_ch_name] [$mask->{ch_mask}]");
      return undef;
    }

    my $url_match = Mask::match($mask->{url_mask}, $url);
    if( !$url_match )
    {
      defined($url_match) or next;
      $DEBUG and $this->_debug($full_ch_name, "debug: - url denied: [$url] [$mask->{url_mask}]");
      return undef;
    }

    return $mask;
  }
  undef;
}

# -----------------------------------------------------------------------------
# my @urls = $pkg->_extract_urls($text).
# extract all url like strings (include ftp://, ttp://).
#
sub _extract_urls
{
  my $this   = shift;
  my $msgval = shift;

  my $pars = {
    '<' => '>',
    '(' => ')',
    '[' => ']',
  };

  my @tokens = split( $RE_WHITESPACES, $msgval );
  my @urls = map{ m{ (\S?\w+://\S+) }gx } @tokens;
  foreach my $url (@urls)
  {
    my $par_begin = $url =~ s/^(\W)// ? $1 : '';
    my $par_end   = $pars->{$par_begin};
    $par_end or next;
    $url =~ s/\Q$par_end\E\z//;
  }

  @urls;
}

# -----------------------------------------------------------------------------
# $obj->_process_command($msg, $sender, $result, $msgval).
# process "fetchtitle: " commands.
#
sub _process_command
{
  my $this   = shift;
  my $msg    = shift;
  my $sender = shift;
  my $result = shift;
  my $msgval = shift;

  my $ch_full    = Auto::Utils::get_full_ch_name($msg, 0);
  my $msg_prefix = $msg->prefix;

  $DEBUG and $this->_debug($ch_full, "debug: check debug-mask for $ch_full, $msg_prefix");
  my $accepted = Mask::match_deep_chan([$this->config->debug_mask('all')], $msg_prefix, $ch_full);
  if( !$accepted )
  {
    $this->_reply($ch_full, "(not acceptable)");
    return;
  }

  my ($cmd, $rest) = split( $RE_WHITESPACES, $msgval, 2);
  my $lc_cmd = lc($cmd);
  if( $lc_cmd eq 'version' )
  {
    $this->_reply($ch_full, "version: $VERSION");
  }elsif( $lc_cmd eq 'loaded-at' )
  {
    $this->_reply($ch_full, "loaded-at: ".localtime($this->{loaded_at}));
  }elsif( $lc_cmd eq 'debug' )
  {
    if( $rest && $rest =~ /^on/ )
    {
      $this->{debug} = 1;
      $this->_reply($ch_full, "debug: turned on");
    }elsif( $rest && $rest =~ /^off/ )
    {
      $this->{debug} = undef;
      $this->_reply($ch_full, "debug: turned off");
    }else
    {
      $this->_reply($ch_full, "debug: current flag is ".($this->{debug} ? "on" : "off"));
    }
  }else
  {
    $this->_reply($ch_full, "unknown-command: $lc_cmd");
  }
}


# -----------------------------------------------------------------------------
# $obj->_add_request($req).
#
sub _add_request
{
  my $this = shift;
  my $req  = shift;

  $req->{url} or die "no url";

  my $full_ch_name = $req->{full_ch_name};
  my $queue = ($this->{request_queue}{$full_ch_name} ||= []);
  push(@$queue, $req);

  
  # drop orphan requests if exists.
  $this->_close_request($full_ch_name);

  if( (grep{$_->{active}} @$queue) >= $MAX_ACTIVE_REQUESTS )
  {
    return;
  }
  my $real_req = $this->_start_request($req);
  if( $real_req != $req )
  {
    # _start_request() で修正されていたら差し替え.
    @$queue = map{ $_==$req ? $real_req : $_ } @$queue;
  }
}

# -----------------------------------------------------------------------------
# $val = _decode_value($val).
#
sub _decode_value
{
  my $val = shift;
  @_ and $val = shift; # for OO-style.

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
# $new_req = $obj->_start_request($req).
# $new_req は処理前リダイレクトされて$reqとは変わっていることもある.
#
sub _start_request
{
  my $this = shift;
  my $req  = shift;

  $req->{started_at} = time;
  $DEBUG and $this->_debug($req, "debug: start request $req->{full_ch_name} $req->{url}");

  $this->_request_filter(prereq => $req);
  while( $req->{redirect} && !$req->{response} )
  {
    my $new_req = $this->_redirect($req->{redirect}, $req, $req);
    if( !$new_req || $new_req->{response} )
    {
      last;
    }
    $req = $new_req;
    $req->{started_at} = time;
    $this->_request_filter(prereq => $req);
  }

  if( $req->{response} )
  {
    $req->{active}     = 1;
    $req->{httpclient} = undef;
    $DEBUG and $this->_debug($req, "debug: request has response before start connection");
    $this->_close_request($req->{full_ch_name});
    return $req;
  }

  my $headers = $req->{headers};

  my $agent_name = $headers->{'User-Agent'};
  if( !defined($agent_name) || $agent_name eq '' )
  {
    $DEBUG and $this->_debug($req, "debug: drop User-Agent header");
    delete $headers->{'User-Agent'};
  }

  my $cookies = join('; ', map{ "$_->{name}=$_->{value}" } @{$req->{cookies}});
  if( $req->{headers}{Cookie} )
  {
    $req->{headers}{Cookie} = "$cookies; $req->{headers}{Cookie}";
  }else
  {
    if( $cookies )
    {
      $req->{headers}{Cookie} = $cookies;
    }else
    {
      delete $req->{headers}{Cookie};
    }
  }
  $DEBUG and $this->_debug($req, "Cookie: ".($req->{headers}{Cookie} || '(none)'));

  my $timeout = $req->{timeout} || $this->config->timeout || $DEFAULT_TIMEOUT;
  $DEBUG and $this->_debug($req, "debug: create http-client, timeout=$timeout");
  my $httpclient = Tools::HTTPClient->new(
    Method  => $req->{method} || 'GET',
    Url     => $req->{url},
    Header  => $headers,
    Timeout => $timeout,
    Content => $req->{content},
  );
  $DEBUG and $this->_debug($req, "debug: start http-client: $req->{url}");

  weaken(my $_this = $this);
  eval{
    $httpclient->start(
      Callback => sub{
        my $this = $_this;
        $DEBUG and print "Callback.this = $this\n";
        $this or return RunLoop->shared_loop->notify_error(__PACKAGE__."#_start_request/httpclient.Callback, object was deleted.");
        local($DEBUG) = $DEBUG || $this->{debug};
        $DEBUG and $this->_debug($req, "debug: http-client finished: @_");
        $this->_request_finished($req, @_);
      },
      ProgressCallback => sub{
        my $this = $_this;
        $this or return RunLoop->shared_loop->notify_error(__PACKAGE__."#_start_request/httpclient.Callback, object was deleted.");
        local($DEBUG) = $DEBUG || $this->{debug};
        $DEBUG and $this->_debug($req, "debug: http-client progress @_");
        $this->_request_progress($req, @_);
      },
    );
  };
  if( $@ )
  {
    my $err = "$@";
    $err =~ s/$RE_WHITESPACES\z//;
    if( $err =~ m{Failed to connect: (\S+):\d+, IO::Socket::INET: Bad hostname '\1' at } )
    {
      $err = 'no host to connect';
    }
    $err =~ s{Failed to connect: \S+:\d+, IO::Socket::INET: (?:connect: )?(.*) at .*}{$1};
    $req->{response} = $err;
    $this->_request_finished($req, $err);
    return $req;
  }

  $req->{active}     = 1;
  $req->{httpclient} = $httpclient;
  $DEBUG and $this->_debug($req, "debug: request has marked as active");

  $req;
}

# -----------------------------------------------------------------------------
# $obj->_apply_recv_limit($req, $new_val).
# $req->{recv_limit} に現在値と新しい値の大きな方を設定.
#
sub _apply_recv_limit
{
  my $this = shift;
  my $req  = shift;
  my $new_value = shift;
  my $cur_value = $req->{recv_limit} || 0;

  $req->{recv_limit} = $new_value > $cur_value ? $new_value : $cur_value;
}

# -----------------------------------------------------------------------------
# $obj->_apply_timeout($req, $new_val).
# $req->{timeout} に現在値と新しい値の大きな方を設定.
#
sub _apply_timeout
{
  my $this = shift;
  my $req  = shift;
  my $new_value = shift;
  my $cur_value = $req->{timeout} || 0;

  $req->{timeout} = $new_value > $cur_value ? $new_value : $cur_value;
}

# -----------------------------------------------------------------------------
# $obj->_apply_max_redirects($req, $new_val).
# $req->{max_redirects} に現在値と新しい値の大きな方を設定.
# 但し MAX_REDIRECTS_LIMIT を上限.
#
sub _apply_max_redirects
{
  my $this = shift;
  my $req  = shift;
  my $new_value = shift;
  my $cur_value = $req->{max_redirects} || 0;

  $req->{max_redirects} = $new_value > $cur_value ? $new_value : $cur_value;
  if( $req->{max_redirects} > $MAX_REDIRECTS_LIMIT )
  {
    $req->{max_redirects} = $MAX_REDIRECTS_LIMIT;
  }
  $DEBUG and $this->_debug($req, "max-redirects: $req->{max_redirects}");
}

# -----------------------------------------------------------------------------
# $this->run_hook($hook_name => $arg).
# フックの実行.
#
sub run_hook
{
  my $this      = shift;
  my $hook_name = shift;
  my $arg       = shift;

  foreach my $plugin ($this->plugins)
  {
    my $spec = $plugin->{object}{hook};
    my $sub = $spec && $spec->{$hook_name};
    $sub or next;
    $plugin->$sub($this, $arg);
  }
}

# -----------------------------------------------------------------------------
# $this->_request_filter(prereq   => $req).
# $this->_request_filter(response => $req).
# リクエストのフィルタを適用.
#
sub _request_filter
{
  my $this = shift;
  my $when = shift;
  my $req  = shift;
  my $url  = $req->{url};

  if( $when eq 'prereq' )
  {
    $req->{headers}{'User-Agent'} ||= "FetchTitle/$VERSION (tiarra)";
    if( $url =~ m{https?://\w+\.2ch\.net(?:/|$)} )
    {
      $DEBUG and $this->_debug($req, "debug: change user-agent for 2ch");
      $req->{headers}{'User-Agent'} =~ s/libwww-perl/LWP/;
    }
  }
  my $hook_name = "filter.$when";

  my $has_extract_heading;
  $DEBUG and $this->_debug($req, "debug: conf check start for $when");
  foreach my $conf (@{$req->{mask}{conf}})
  {
    $DEBUG and $this->_debug($req, "debug: conf check");
    my $table = $conf->table;
    foreach my $key (sort keys %$table)
    {
      $DEBUG and $this->_debug($req, "debug: - $key");
      my $block = $conf->get($key, 'block');
      my $url_masks = [$block->url('all')];
      #$DEBUG and $this->_debug($req, "debug: - - url: $_") for @$url_masks;
      if( @$url_masks && !Mask::match_deep($url_masks, $url) )
      {
        #$DEBUG and $this->_debug($req, "debug: - - not match");
        next;
      }

      $DEBUG and $this->_debug($req, "debug: - - match");
      if( $when eq 'prereq' and my $timeout = $block->timeout )
      {
        if( $timeout =~ /^\d+\z/ )
        {
          my $prev = $req->{timeout} || '(noval)';
          $DEBUG and $this->_debug($req, "debug: - - timeout: $prev -> $timeout");
          $req->{timeout} = $timeout;
        }else
        {
          $DEBUG and $this->_debug($req, "debug: - - timeout: invalid value: $timeout");
        }
      }

      my @types = $block->type('all');
      if( $block->user && !grep {$_ eq 'basic'} @types )
      {
        push(@types, 'basic');
      }
      if( $block->cookie && !grep {$_ eq 'cookie'}  @types)
      {
        push(@types, 'cookie');
      }
      $has_extract_heading ||= grep {$_ eq 'extract-heading'} @types;
      foreach my $type (@types)
      {
        my $spec = $this->{hooks}{$type};
        if( !$spec )
        {
          $DEBUG && $type ne '' and $this->_debug($req, "debug: unsupported type: $type");
          next;
        }
        my $sub = $spec->{$hook_name};
        if( !$sub )
        {
          $DEBUG && $type ne '' and $this->_debug($req, "debug: - no sub for $hook_name");
          next;
        }
        $DEBUG and $this->_debug($req, "debug: call $type/$hook_name");
        $req->{applied_filters} ||= [];
        push(@{$req->{applied_filters}}, $type);
        if( $spec->{old} )
        {
          my $old_sub = $sub;
          $sub = sub{
            my $obj = shift;
            my $ctx = shift;
            my $arg = shift;
            $old_sub->($ctx, $arg->{block}, $arg->{req}, $arg->{when}, $arg->{type});
          };
        }
        my $arg = {
          block => $block,
          req   => $req,
          when  => $when,
          type  => $type,
        };
        $spec->{object}->$sub($this, $arg);
        if( $req->{redirect} || ($when eq 'prereq' && $req->{response}) )
        {
          return;
        }
      }
    }
  }

  if( !$has_extract_heading )
  {
    my $type = 'extract-heading';
    my $spec = $this->{hooks}{$type};
    my $sub = $spec->{$hook_name};
    if( $sub )
    {
      my $block = undef;#Configuration::Block->new();
      $DEBUG and $this->_debug($req, "debug: call $type/$hook_name (extra)");
      $req->{applied_filters} ||= [];
      push(@{$req->{applied_filters}}, $type);

      my $arg = {
        block => $block,
        req   => $req,
        when  => $when,
        type  => $type,
      };
      $spec->{object}->$sub($this, $arg);
    }
  }

}

# -----------------------------------------------------------------------------
# $this->_filter_basic_prereq($block, $req, $when, $type).
# (impl:fetchtitle-filter)
# BASIC認証/prereq.
#
sub _filter_basic_prereq
{
  my $this  = shift;
  my $block = shift;
  my $req   = shift;
  my $when  = shift;
  my $type  = shift;

  eval { require MIME::Base64; };
  if( $@ )
  {
    $DEBUG and $this->_debug($req, "debug: no MIME::Base64");
    next;
  }
  my $user = _decode_value($block->user);
  my $pass = _decode_value($block->pass);
  $req->{headers}{Authorization} = "Basic ".MIME::Base64::encode("$user:$pass", "");

  $this;
}

# -----------------------------------------------------------------------------
# $this->_filter_cookie_prereq($block, $req, $when, $type).
# (impl:fetchtitle-filter)
# cookie/prereq.
#
sub _filter_cookie_prereq
{
  my $this  = shift;
  my $block = shift;
  my $req   = shift;
  my $when  = shift;
  my $type  = shift;

  foreach my $cookie ($block->cookie('all'))
  {
    if( $req->{headers}{Cookie} )
    {
      $req->{headers}{Cookie} .= "; ";
    }else
    {
      $req->{headers}{Cookie} = "";
    }
    if( $cookie =~ /^(\S+?)=(\S+)\z/ )
    {
      $req->{headers}{Cookie} .= "$cookie";
    }else
    {
      $DEBUG and $this->_debug($req, "debug: invalid cookie value: $cookie");
    }
  }

  $this;
}

# -----------------------------------------------------------------------------
# $this->_filter_uploader_prereq($block, $req, $when, $type).
# (impl:fetchtitle-filter)
# uploader/prereq.
# uploader.jp. ダウンロードURLに情報がないので,
# トップページから情報を取得.
#
sub _filter_uploader_prereq
{
  my $this  = shift;
  my $block = shift;
  my $req   = shift;
  my $when  = shift;
  my $type  = shift;

  my $url = $req->{url};
  if( $url =~ s{/dl/(\w+)/[^/]+\.html}{/home/$1/} )
  {
    $req->{redirect} = {
      url        => $url,
      recv_limit => 20*1024,
    };
  }
  $this;
}

# -----------------------------------------------------------------------------
# $this->_filter_uploader_response($block, $req, $when, $type).
# (impl:fetchtitle-filter)
# uploader/response.
#
sub _filter_uploader_response
{
  my $this  = shift;
  my $block = shift;
  my $req   = shift;
  my $when  = shift;
  my $type  = shift;

  my $prev = $req->{old}{url} or return;
  $DEBUG and $this->_debug($req, "debug: prev url is $prev");

  my $regexp = qr{
    (?-x:<td>No.(\d+) <a href="\Q$prev\E">(.*?)</a></td>)
    (?-x:\s*<td>(.*?)</td>) # desc.
    (?-x:\s*<td>(.*?)</td>) # size.
    (?-x:\s*<td>(.*?)</td>) # date.
    (?-x:\s*<td>(.*?)</td>) # filename.
  }x;
  if( !$req->{result}{decoded_content} || $req->{result}{decoded_content} !~ $regexp )
  {
    $DEBUG and $this->_debug($req, "debug: - not match");
    return;
  }
  my $no    = $1;
  my $alias = $2;
  my $desc  = $3;
  my $size  = $4;
  my $date  = $5;
  my $origname = $6;
  $desc =~ s/^$RE_WHITESPACES//;
  my $locked = $size =~ s{ <font color="red">\*</font>}{};

  my @opts;
  push(@opts, "No.$no");
  push(@opts, $size);
  push(@opts, $locked ? "locked" : "non-pass");
  push(@opts, $date);

  my $reply;
  if( $desc )
  {
    $reply = $desc;
    push(@opts, $origname);
  }else
  {
    $reply = $origname;
  }
  $reply .= " (".join("; ",@opts).")";
  $req->{result}{result} = $reply;
}

# -----------------------------------------------------------------------------
# $obj->_request_progress($req, $res).
# 大抵はタイトル取得に全部を落とす必要がないので
# ある程度取得したら切断しちゃう用.
#
sub _request_progress
{
  my $this = shift;
  my $req  = shift;
  my $res  = shift; # HTTPClient response.

  my $rlen = defined($res->{Content}) ? length($res->{Content}) : 0;
  $DEBUG and $this->_debug($req, "debug: progress $rlen / $req->{recv_limit}");

  if( my $addr = !$req->{addr_checked} && $req->{httpclient}->{addr} )
  {
    my $desc  = $this->_addr_check($addr);
    if( !$desc )
    {
      $req->{addr_checked} = 'not local';
    }else
    {
      my $allowed = $this->_is_allowed_local($req, $addr);
      if( $allowed )
      {
        $req->{addr_checked} = "$desc, allowed";
      }else
      {
        $req->{addr_checked} = "$desc, not allowed";
        $req->{httpclient}->stop();
        $this->_debug($req, "reserved address: $desc ($addr)");
        $this->_request_finished($req, "reserved address: $desc");
      }
    }
  }

  if( $rlen>=$req->{recv_limit} )
  {
    $DEBUG and $this->_debug($req, "debug: stop request.");
    $req->{httpclient}->stop();
    $this->_request_finished($req, $res);
  }
}

sub _addr_check
{
  my $this = shift;
  my $addr = shift;

  $DEBUG and print __PACKAGE__."#_addr_check: $addr\n";

  my $ipv4 = $this->_addr_check_ipv4($addr);
  if( $ipv4 )
  {
    return $ipv4;
  }

  my $ipv6 = $this->_addr_check_ipv6($addr);
  if( $ipv6 )
  {
    return $ipv6;
  }

  return undef;
}

sub _addr_check_ipv4
{
  my $this = shift;
  my $addr = shift;

  my @digits = $addr =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)\z/;
  @digits or  return undef;
  grep{ $_>255 || /^0./ } @digits and return undef;
  my $addr_num = ($digits[0] << 24) | ($digits[1] << 16) | ($digits[2] << 8) | $digits[3];

  my $cidrs = $this->_config_reserved_addresses();
  foreach my $cidr (@$cidrs)
  {
    my $a0   = $cidr->[0];
    my $mask = $cidr->[1];
    ($addr_num & $mask) == $a0 or next;
    return $cidr->[3];
  }
  return undef;
}

sub _addr_check_ipv6
{
  my $this = shift;
  my $addr = shift;

  # not supported.

  return undef;
}

sub _is_allowed_local
{
  my $this = shift;
  my $req  = shift;
  my $addr = shift;

  my ($addr_num) = $this->_split_cidr($addr);

  foreach my $conf (@{$req->{mask}{conf}})
  {
    my $table = $conf->table;
    foreach my $key (sort keys %$table)
    {
      my $block = $conf->get($key, 'block');
      foreach my $cidr ($block->allow_local('all'))
      {
        my ($a0, $mask) = $this->_split_cidr($cidr);
        if( !defined($a0) )
        {
          $this->_error("invalid cidr: $cidr");
          next;
        }
        if( ($addr_num & $mask) != $a0 )
        {
          next;
        }
        return $cidr;
      }
    }
  }
  
  return undef;
}

# -----------------------------------------------------------------------------
# $obj->_request_finished($req, $res).
#
sub _request_finished
{
  my $this = shift;
  my $req  = shift;
  my $res  = shift; # HTTPClient response.

  $DEBUG and print __PACKAGE__."#_request_finished\n";
  $req->{response} = $res;
  $req->{httpclient} = undef;
  $DEBUG and $this->_debug($req, "debug: got response for $req->{full_ch_name} $req->{url}");

  my $full_ch_name = $req->{full_ch_name};
  $this->_close_request($full_ch_name);
}

# -----------------------------------------------------------------------------
# $obj->_close_request($full_ch_name).
# 最初のリクエストが完了していたら返答を生成して送信.
# 最初のあるだけ複数個.
#
sub _close_request
{
  my $this = shift;
  my $full_ch_name = shift;
  $DEBUG and print __PACKAGE__."#_close_request\n";
  while( my $req = $this->_close_head_request($full_ch_name) )
  {
    my $reply = $req->{result}{result};
    $DEBUG and print __PACKAGE__."#_close_head_request, reply = $reply\n";
    $this->_reply($full_ch_name => $reply);
    #$this->_request_filter(closed => $req);
  }
  $DEBUG and print __PACKAGE__."#_close_request, done\n";
}

# -----------------------------------------------------------------------------
# my $reply_text = $obj->_close_head_request($full_ch_name).
# 最初のリクエストが完了していたら返答を生成.
# 最初の１つだけ.
#
sub _close_head_request
{
  my $this = shift;
  my $full_ch_name = shift;
  $DEBUG and print __PACKAGE__."#_close_head_request\n";
  if( !$full_ch_name )
  {
    $this->_error("_close_head_request: no ch name");
    return;
  }

  my $req_queue = $this->{request_queue}{$full_ch_name};
  my $req = $req_queue && @$req_queue && $req_queue->[0];

  if( !$req )
  {
    # no request in queue.
    return;
  }
  if( !$req->{response} )
  {
    # first request is still in progress.
    my $now = time;
    if( $req->{requested_at} < $now - $PROCESSING_LIMIT_TIME )
    {
      $req->{response} = "timeout(*)";
      my $el = $now - $req->{requested_at};
      $DEBUG and $this->_debug($req, "debug: request not finished, but expired: $req->{requested_at}+$el/$PROCESSING_LIMIT_TIME for $req->{full_ch_name} $req->{url}");
    }else
    {
      $DEBUG and $this->_debug($req, "debug: request not finished: for $req->{full_ch_name} $req->{url}");
      return;
    }
  }

  shift @$req_queue;

  my $result = $this->_parse_response($req->{response}, $req);

  $req->{result} = $result;
  $this->_request_filter(response => $req);

  if( my $redir = $result->{redirect} )
  {
    my $new_req = $this->_redirect($redir, $req, $result);
    if( $new_req )
    {
      if( !$new_req->{response} )
      {
        # つめなおしてもう一度問い合わせ.
        unshift @$req_queue, $new_req;
        my $real_req = $this->_start_request($new_req);
        $req_queue->[0] = $real_req;
        return;
      }
      $req    = $new_req;
      $result = $this->_parse_response($req->{response}, $req);
      $req->{result} = $result;
      # これ以上はフィルタ処理しないでおく.
      # してもいいのかもだけど,
      # いまのとこ多段処理する予定もないので.
    }
  }

  if( $DEBUG )
  {
    if( my $file = $this->config->debug_dumpfile )
    {
      $this->_debug($req, "debug: dump result into $file");
      if( open(my$fh, '>', $file) )
      {
        use Data::Dumper;
        my $req = { %$req };
        my $res = $req->{response};
        $req->{response} = '(drop)';
        #ref($res) && length($res->{Content})>100 and substr($res->{Content}, 100, -1, '(drop)');
        print $fh Dumper($req, $res, $result);
        close $fh;
      }else
      {
        $this->_debug($req, "debug: open: $!");
      }
    }else
    {
      $this->_debug($req, "debug: no dumpfile specified");
    }
  }

  $req;
}

# -----------------------------------------------------------------------------
# $new_req = $this->_redirect($redir, $prev_res).
# リダイレクト処理.
# $redir はハッシュリファレンスかスカラー(URL).
#
sub _redirect
{
  my $this  = shift;
  my $redir = shift;
  my $req   = shift;

  if( !ref($redir) )
  {
    $redir = { url => $redir };
  }
  my $err;
  my $count = ($req->{redirected}||0) + 1;
  my $full_ch_name = $req->{full_ch_name};

  $DEBUG and $this->_debug($req, "debug: _redirect: ($count) $redir->{url}");

  if( $redir->{url} !~ m{/} )
  {
    my $base = $req->{url};
    $base =~ s{[^/]+$}{};
    $redir->{url} = $base . $redir->{url};
    $DEBUG and $this->_debug($req, "debug: _redirect: rewrite basename, $redir->{url}");
  }elsif( $redir->{url} =~ m{^/} )
  {
    my ($scheme, $domain, $path) = $this->_parse_url($req);
    if( !$scheme )
    {
      $this->_error("parsing url for redirect is failed: $req->{url}");
      return;
    }
    $redir->{url} = "$scheme://$domain$redir->{url}";
    $DEBUG and $this->_debug($req, "debug: _redirect: rewrite path-style, $redir->{url}");
  }

  my $matched = $this->_check_mask($full_ch_name, $redir->{url});
  if( !$matched )
  {
    $DEBUG and $this->_debug($req, "debug: _redirect: not in mask, no redirect");
    return;
  }

  # リダイレクトリクエストの生成.
  my $new_req = $this->_create_request($req->{full_ch_name}, $redir->{url}, $matched);
  my $ini_req = $req->{ini_req} || $req;
  $new_req->{old}        = $req;
  $new_req->{ini_req}    = $ini_req;
  $new_req->{redirected} = $count;
  $new_req->{requested_at} = $req->{requested_at};
  $new_req->{cookie_jar} = $ini_req->{cookie_jar};
  $this->_add_cookie_header($new_req, $ini_req->{cookie_jar});
  if( $redir->{recv_limit} )
  {
    $this->_apply_recv_limit($new_req, $redir->{recv_limit});
  }
  if( $req->{max_redirects} )
  {
    $this->_apply_max_redirects($new_req, $req->{max_redirects});
  }
  if( $redir->{max_redirects} )
  {
    $this->_apply_max_redirects($new_req, $redir->{max_redirects});
  }

  $redir->{method} and $new_req->{method} = $redir->{method};
  if( my $h = $redir->{headers} )
  {
    @{$new_req->{headers}}{keys %$h} = values %$h;
  }
  if( $redir->{content} )
  {
    $new_req->{content} = $redir->{content};
    $new_req->{method}  ||= 'POST';
    $new_req->{headers}{'Content-Length'} = length($new_req->{content});
  }

  $new_req->{response} = $redir->{response};
  if( $count > ($new_req->{max_redirects} || $MAX_REDIRECTS) )
  {
    $new_req->{response} ||= "too many redirects: $req->{redirected}";
  }

  $new_req;
}

# -----------------------------------------------------------------------------
# $result = $this->_parse_response($res, $req).
# 関数名の通り.
#
sub _parse_response
{
  my $this = shift;
  my $res  = shift;
  my $req  = shift;
  my $full_ch_name = $req->{full_ch_name};
  $DEBUG and $this->_debug($req, "_parse_response.");

  my $result = {
    result         => undef,
    status_code    => undef,
    is_success     => undef,
    title          => undef,
    content_type   => undef,
    content_length => undef,
    decoded_content => undef,
    fetch_length    => undef,
  };

  if( !ref($res) )
  {
    my $DEFAULT_LANG = 'ja';
    my $lang = $this->config->lang || $DEFAULT_LANG;
    my $msgmap = {};
    if( $lang eq 'ja' )
    {
      $msgmap = {
        error   => 'エラー',
        timeout => 'タイムアウト',
        'no host to connect'   => 'サーバが見つかりません',
        '接続を拒否されました' => 'サーバに接続できませんでした',
        'Connection refused'   => 'サーバに接続できませんでした',
      };
    };
    $result->{result} = "(".($msgmap->{error}||'error').") $req->{url} ".($msgmap->{$res}||$res);
    return $result;
  }

  my $protocol    = $res->{Protocol};
  my $status_code = $res->{Code} || 0;
  my $status_msg  = $res->{Message};
  my $headers     = $res->{Header}; # hash-ref.
  my $content     = $res->{Content};
  $result->{fetch_length} = defined($content) ? length($content) : undef;
  defined($content) or $content = '';
  my @opts;

  $result->{status_code}    = $status_code;
  $result->{content_length} = $headers->{'Content-Length'};
  if( !defined($result->{content_length}) && $res->{StreamState} eq 'finished' )
  {
    $result->{content_length} = length($content);
  }
  $DEBUG and $this->_debug($full_ch_name, "debug: fetch ".length($content)." bytes");

  # extract Cookies;
  if( $headers->{'Set-Cookie'} )
  {
    $this->_extract_cookies($req);
  }

  if( my $loc = $headers->{Location} )
  {
    $DEBUG and $this->_debug($full_ch_name, "debug: has Location header: $loc");
    if( $loc =~ m{^\s*(\w+://[-.\w]+\S*)\s*$} )
    {
      $result->{redirect} = substr($loc, 0, length($1)); # keep taintness.
    }elsif( $loc =~ m{^\s*((/?).*?(?:[#?].*)?)\s*$} )
    {
      my $path = substr($loc, 0, length($1)); # keep taintness.
      my $is_abs = $2;
      my $new_url = $req->{url};
      $new_url =~ s{[#?].*}{};
      if( $is_abs )
      {
        $new_url =~ s{^(\w+://[^/]+)/.*}{$1} or die "invalid req url(abs): $new_url";
      }else
      {
        $new_url =~ s{^(\w+://[^/]+.*/).*}{$1} or die "invalid req url(rel): $new_url";
      }
      $result->{redirect} = $new_url . $path;
    }else
    {
      $DEBUG and $this->_debug($full_ch_name, "debug: broken location url: $loc");
    }
    $DEBUG && $result->{redirect} and $this->_debug($full_ch_name, "debug: Location redirect: $result->{redirect}");
  }
  if( int($status_code / 100) != 2 && !$result->{redirect} )
  {
    $result->{title} = $status_msg;
    push(@opts, "http status $status_code");
  }

  # detect refresh tag.
  if( $content =~ m{<META HTTP-EQUIV="refresh" CONTENT="(\d+);URL=(.*?)">}i )
  {
    my $after = $1;
    my $url   = $2;
    $DEBUG and $this->_debug($full_ch_name, "debug: meta.refresh found: $after; $url");
    $result->{redirect} = $url;
  }

  # detect encoding.
  my $enc = 'auto';
  if( $content =~ m{<meta\s+http-equiv="Content-Type"\s+content="\w+/\w+(?:\+\w+)*\s*;\s*charset=([-\w]+)"\s*/?>}i )
  {
    my $e = lc($1);
    $enc = $e =~ /s\w*jis/     ? 'sjis'
         : $e =~ /euc/         ? 'euc'
         : $e =~ /utf-?8/      ? 'utf8'
         : $e =~ /iso-2022-jp/ ? 'jis'
         : $e =~ /\bjis\b/     ? 'jis'
         : $enc;
    $DEBUG and $this->_debug($full_ch_name, "debug: charset $enc from meta ($e)");
  }
  if( $enc eq 'auto' && $headers->{'Content-Type'} && $headers->{'Content-Type'} =~ /;\s*charset=(\S+)/ )
    {
    my $e = lc($1);
    $enc = $e =~ /s\w*jis/     ? 'sjis'
         : $e =~ /euc/         ? 'euc'
         : $e =~ /utf-?8/      ? 'utf8'
         : $e =~ /iso-2022-jp/ ? 'jis'
         : $e =~ /\bjis\b/     ? 'jis'
         : $enc;
    $DEBUG and $this->_debug($full_ch_name, "debug: charset $enc from http-header ($e)");
  }
  if( $enc eq 'auto' )
  {
    my $guessed = $ENCODER->new->getcode($content);
    $enc = $guessed ne 'unknown' ? $guessed : 'sjis';
    $DEBUG and $this->_debug($full_ch_name, "debug: charset $enc from guess ($guessed)");
  }

  # drop broken utf-8 sequences.
  if( $enc eq 'utf8' && $content =~ s{([\xe0-\xef][\x80-\xbf]?)(?=[\x00-\x7e])}{join('',map{sprintf("[%02x]",$_)}unpack("C*",$1))}eg )
  {
    $DEBUG and $this->_debug($full_ch_name, "debug: broken utf-8 found and fixed");
    my $url = $req->{url};
    $this->_log("broken utf-8 on $url (enc=$enc)");
    $DEBUG and $this->_debug($req, "broken utf-8 on $url (enc=$enc)");
  }

  # decode.
  $content = $ENCODER->new($content, $enc)->utf8;
  $result->{decoded_content} = $content;

  my ($title) = $content =~ m{<title\s*>\s*(.*?)\s*</title\s*>}is;
  $DEBUG && !$title and $this->_debug($full_ch_name, "debug: no title elements in document");

  if( defined($title) )
  {
    $title = $this->_fixup_title($title);
    $result->{title} = $title;
  }else
  {
    $title = $result->{title};
  }

  my ($ctype) = split(/[ ;]/, $headers->{'Content-Type'}, 2);
  $ctype ||=  'unknown/unkown';
  $result->{content_type} = $ctype;
  $DEBUG and $this->_debug($full_ch_name, "debug: content-type: $ctype");

  my $reply = defined($title) ? $title : '';
  if( $reply eq '' )
  {
    $DEBUG and $this->_debug($full_ch_name, "debug: check icecast");
    if( my $icy_name = $headers->{'icy-name'} )
    {
      # Icecast.
      my $desc    = $headers->{'icy-description'};
      my $bitrate = $headers->{'icy-br'};
      $reply = $icy_name;
      if( defined($bitrate) )
      {
        $reply .= " [${bitrate}k]";
      }
      if( defined($desc) && $desc ne $icy_name )
      {
        $reply .= " - $desc";
      }
      $reply = $ENCODER->new($reply,'auto')->utf8;
    }
  }
  if( $ctype eq 'audio/x-mpegurl' && $res->{StreamState} eq 'finished' )
  {
    if( $content =~ m{^(\w+://[-.\w]+\S*)\s*$}m )
    {
      $result->{redirect} = substr($content, 0, length($1)); # keep taintness.
    }
  }

  if( $reply eq '' || $ctype !~ /html/ )
  {
    push(@opts, $ctype);
  }
  if( $ctype =~ m{^(?:image|video)/} && $HAS_IMAGE_EXIFTOOL )
  {
    $DEBUG and $this->_debug($full_ch_name, "debug: check image");
    my @tags = qw(Title ImageSize Headline);
    my $info = Image::ExifTool::ImageInfo(\$res->{Content}, @tags);
    my $x = sub{ my $x=shift;$x=~s/([^ -~])/sprintf('[%02x]',unpack("C",$1))/ge;$x};
    $DEBUG and $this->_debug($full_ch_name, "debug: - ".$x->(join(", ", %$info)));
    if( $reply eq '' )
    {
      my ($key) = grep{$info->{$_}} qw(Title Headline);
      my $decoded_key = $info->{"$key (1)"} && "$key (1)";
      my $val = $info->{$decoded_key} || $info->{$key};
      my $guessed = $decoded_key ? 'decoded' : $ENCODER->getcode($val);
      my $enc = $guessed eq 'unknown' ? 'sjis' : $guessed;
      $DEBUG and $this->_debug($full_ch_name, "debug: - $key ($enc/$guessed) ".$x->($val));
      $reply ||= $decoded_key ? $info->{$decoded_key} : $ENCODER->new($val, $enc)->utf8;
    }
    if( $info->{ImageSize} )
    {
      push(@opts, $info->{ImageSize});
    }
  }
  if( $reply eq '' || $ctype !~ /html/ )
  {
    my $len = $result->{content_length};
    if( defined($len) )
    {
      $len =~ s/(?<=\d)(?=(\d\d\d)+(?!\d))/,/g;
      $len = "$len bytes";
      push(@opts, $len);
    }
  }
  if( $req->{redirected} )
  {
    my $redirs = $req->{redirected}==1 ? 'redir' : 'redirs';
    push(@opts, "$req->{redirected} $redirs");
  }

  if( $reply eq '' && $ctype =~ /text/ )
  {
    $reply = '(untitled)';
  }
  if( @opts )
  {
    $reply eq '' or $reply .= ' ';
    $reply .= "(".join("; ", @opts).")";
  }

  $result->{is_success} = 1;
  $result->{result} = $reply;
  $result;
}

sub _parse_url
{
  my $this = shift;
  my $url  = shift;
  ref($url) and $url = $url->{url};

  my ($scheme, $domain, $path) = $url =~ m{^(http|https)://(?:[^/]+\@)?([^/]+)(.*)};
  if( !$scheme )
  {
    return;
  }
  $path =~ s/[\?#].*//;
  $path =~ s{[^/]$}{};
  ($scheme, $domain, $path);
}

sub _add_cookie_header
{
  my $this = shift;
  my $req  = shift;
  my $cookie_jar = shift;

  $DEBUG and print __PACKAGE__."#_add_cookie_header, $req->{url}\n";

  my ($scheme, $domain, $path) = $this->_parse_url($req);
  if( !$scheme )
  {
    $this->_error("parsing url for cookie is failed: $req->{url}");
    return;
  }

  my $ini_req = $req->{ini_req} || $req;
  my @send_cookies;
  foreach my $cookie (@$cookie_jar)
  {
    if( $cookie->{domain} ne $domain )
    {
      next;
    }
    if( $cookie->{_scheme} ne $scheme )
    {
      if( $cookie->{_scheme} eq 'https' && $cookie->{secure} )
      {
        next;
      }
    }
    if( $path !~ /^\Q$cookie->{path}/ )
    {
      next;
    }
    push(@send_cookies, $cookie);
  }
  if( @send_cookies )
  {
    $this->_merge_cookies($req->{cookies}, \@send_cookies);
  }
}

sub _extract_cookies
{
  my $this = shift;
  my $req  = shift;
  $DEBUG and $this->_debug($req, __PACKAGE__."#_extract_cookies, $req->{url}");

  my $res  = $req->{response};
  my $new_cookies = $res->{ListedHeader}{'Set-Cookie'} || [$res->{Header}{'Set-Cookie'}];
  my $parsed_cookies = $this->_parse_cookies($req->{url}, $new_cookies);

  if( $parsed_cookies )
  {
    $req->{parsed_cookies} = $parsed_cookies;

    my $ini_req = $req->{ini_req} || $req;
    $this->_merge_cookies($ini_req->{cookie_jar}, $parsed_cookies);
  }
}

sub _parse_cookies
{
  my $this = shift;
  my $url  = shift;
  my $new_cookies = shift;

  ref($url) and $url = $url->{url};

  my ($scheme, $domain, $path) = $this->_parse_url($url);
  if( !$scheme )
  {
    $this->_error("parsing url for cookie is failed: $url");
    return;
  }

  my $now = time;
  my $now_cmp;
  my @parsed_cookies;

  foreach my $cookie_str (@$new_cookies)
  {
    #print "cookie = $cookie_str\n";

    my %attrs = (
      _url         => $url,
      _orig        => $cookie_str,
      _got_at      => $now,
      _scheme      => undef,
      domain       => undef,
      path         => undef,
      name         => undef,
      value        => undef,
      expires      => undef,
      _expires_cmp => undef,
      _is_expired  => undef,
      #secure       => undef,
      #httponly     => undef,
    );
    my $is_first = 1;
    foreach my $pair (split(/\s*;\s*/, $cookie_str))
    {
      my ($key, $val) = split(/\s*=\s*/, $pair, 2);
      if( $is_first )
      {
        $attrs{name}  = $key; # keep encoded.
        $attrs{value} = $val; # keep encoded.
        $is_first     = undef;
      }else
      {
        $attrs{lc $key} = defined($val) ? $val : 1;
      }
    }
    if( $attrs{domain} )
    {
      my $pass;
      if( $attrs{domain} eq $domain )
      {
        $pass = 1;
      }elsif( $domain =~ /\Q$attrs{domain}\E\z/ && $attrs{domain} =~ /^\./ )
      {
        my $nr_dots = $attrs{domain} =~ tr/././;
        $pass = $nr_dots >= 3;
        $pass ||= $attrs{domain} =~ /\.[^.]{3,}\.jp\z/;
        $pass ||= $attrs{domain} =~ /(\.\w+)\z/ && $TOP_LEVEL_DOMAINS->{$1};
      }
      if( !$pass )
      {
        $this->_error("_parse_cookies, domain $attrs{domain} does not match with one in url $domain, ignore this cookie");
        next;
      }
    }
    $attrs{_scheme}   = $scheme;
    $attrs{domain}  ||= $domain;
    $attrs{path}    ||= $path;
    $attrs{_ident}    = join(';', @attrs{qw(_scheme domain path name)});

    if( $attrs{expires} && $attrs{expires} =~ /^\w+, (\d+)-(\w+)-(\d+) (\d+):(\d+):(\d+) \S+$/ )
    {
      my ($mday, $mon, $year, $hour, $min, $sec) = ($1, $2, $3, $4, $5, $6);
      my %mon_map = map{lc($_)}qw(Jan 1 Feb 2 Mar 3 Apr 4 May 5 Jun 6 Jul 7 Aug 8 Sep 9 Oct 10 Nov 11 Dec 12);
      $mon = $mon_map{lc$mon} || 99;
      my $cmp = sprintf('%04d-%02d-%02d %02d:%02d:%02d', $year, $mon, $mday, $hour, $min, $sec);
      $attrs{_expires_cmp} = $cmp;
      $now_cmp ||= do{
        my @tm = localtime();
        $tm[5] += 1900, $tm[4] += 1;
        sprintf('%04d-%02d-%02d %02d:%02d:%02d', reverse @tm[0..5]);
      };
      $attrs{_is_expired} = $cmp lt $now_cmp; 
    }
    push(@parsed_cookies, \%attrs);
    #$DEBUG and print "new cookie: ".Dumper(\%attrs);
  }
  @parsed_cookies ? \@parsed_cookies : undef;
}

sub _merge_cookies
{
  my $this = shift;
  my $cookie_store   = shift;
  my $parsed_cookies = shift;

  foreach my $cookie (@$parsed_cookies)
  {
    @$cookie_store = grep{ $_->{_ident} ne $cookie->{_ident} } @$cookie_store;
    if( !$cookie->{_is_expired} )
    {
      push(@$cookie_store, $cookie);
    }
  }
}

# -----------------------------------------------------------------------------
# $title_text = $this->_fixup_title($title_html).
# htmlから切り出したhtmlパーツのtext化.
#
sub _fixup_title
{
  my $this = shift;
  my $title = shift;

  $title =~ s/<.*?>//g;

  $title = $this->_unescapeHTML($title);
  $title =~ s/[\r\n]+/ /g;
  $title =~ s/^\s+|\s+$//g;
  $title =~ s/\xc2([\x80-\xbf])/ $LATIN1_MAP[unpack("C",$1)-0x80]      || $1 /ge;
  $title =~ s/\xc3([\x80-\xbf])/ $LATIN1_MAP[unpack("C",$1)-0x80+0x40] || $1 /ge;
  #$title =~ s/([^ -~])/sprintf('[%02x]',unpack("C",$1))/ge;

  $title;
}

# -----------------------------------------------------------------------------
# $txt = $this->_unescapeHTML($html).
# HTML中の実際参照をデリファレンス. (ってHTMLもそういうのかな？)
#
sub _unescapeHTML
{
  my $this = shift;
  my $html = shift;
  my $map = {
   nbsp => ' ',
   lt   => '<',
   gt   => '>',
   amp  => '&',
   quot => '"',
   laquo => "\xc2\xab",
   raquo => "\xc2\xbb",
  };
  $html =~ s{&#(\d+);|&#x([0-9a-fA-F]+);|&(\w+);}{
    if( defined($1) || defined($2) )
    {
      my $ch = defined($1) ? $1 : hex($2);
      $ch && $ch < 127 ? chr($ch) : $ENCODER->new(pack("n",$ch), 'ucs2')->utf8;
    }else
    {
      $map->{$3} || "[$3]";
    }
  }ge;
  $html;
}

# -----------------------------------------------------------------------------
# $obj->_log($msg).
#  print log in console.
#
sub _log
{
  my $this = shift;
  my $msg  = shift;
  RunLoop->shared_loop->notify_msg($msg);
}

# -----------------------------------------------------------------------------
# $obj->_reply($full_ch_name, $reply).
# お返事を送信.
#
sub _reply
{
  my $this = shift;
  my $full_ch_name = shift;
  my $reply = shift;

  my $reply_prefix = $this->config_get('reply_prefix');
  my $reply_suffix = $this->config_get('reply_suffix');
  defined($reply_prefix) or $reply_prefix = '';
  defined($reply_suffix) or $reply_suffix = '';
  my $msg = $reply_prefix . $reply . $reply_suffix;
  $msg =~ s/[\r\n]+/ /g;

  # メッセージが追い越しちゃわないように
  # いったんキュー経由.
  push(@{$this->{reply_queue}}, [$full_ch_name, $msg]);
  if( !$this->{reply_timer} )
  {
    $this->{reply_timer} = Timer->new(
      After    => -1, # immediately.
      Code     => sub{ $this->_reply_timer_handler() },
    )->install();
  }
}

# -----------------------------------------------------------------------------
# $this->config_get('reply-prefux').
# $this->config_get('reply-suffix').
# 設定の取得.
# $this->config->reply_prefix 等にダブルクオート処理を加えた物.
#
sub config_get
{
  my $this = shift;
  my $key  = shift;
  my $val  = $this->config->$key;
  if( $val && $val =~ /^"((?:[^\"]+|\\.)*)"/ )
  {
    $val = $1;
    my %map = (
      t => "\t",
      "\\" => "\\",
      "\"" => "\"",
    );
    $val =~ s{\\($1)}{$map{$1}||$1}eg;
  }
  $val;
}

# -----------------------------------------------------------------------------
# $obj->_reply_timer_handler().
# キューにたまっているお返事を実際に送信.
#
sub _reply_timer_handler
{
  my $this = shift;
  $this->{reply_timer} = undef;
  while( my $pair = shift @{$this->{reply_queue}} )
  {
    my $full_ch_name = $pair->[0];
    my $reply        = $pair->[1];

    my $msg_to_send = Auto::Utils->construct_irc_message(
      Command => 'NOTICE',
      Params  => [ '', $reply ],
    );

    my ($ch_short,$net_name) = Multicast::detach($full_ch_name);

    # send to server.
    #
    my $sendto_server = RunLoop->shared_loop->network($net_name);
    if( defined $sendto_server )
    {
      my $for_server = $msg_to_send->clone;
      $for_server->param(0, $ch_short);
      $sendto_server->send_message($for_server);
    }

    # send to clients.
    #
    my $ch_on_client = Multicast::attach_for_client($ch_short, $net_name);
    my $for_client = $msg_to_send->clone;
    $for_client->param(0, $ch_on_client);
    $for_client->remark('fill-prefix-when-sending-to-client', 1);
    RunLoop->shared_loop->broadcast_to_clients($for_client);
  }
}

# -----------------------------------------------------------------------------
# $obj->_error($msg).
# エラーメッセージの送信.
# 回答用じゃなくてエラー記録用.
#
sub _error
{
  my $this = shift;
  my $msg  = shift;

  RunLoop->shared_loop->notify_error($msg);
}

# -----------------------------------------------------------------------------
# $obj->_debug($full_ch_name, $reply).
# $obj->_debug($req, $reply).
# デバッグメッセージの送信.
#
sub _debug
{
  my $this         = shift;
  @_==1 and unshift(@_, '***');
  my $full_ch_name = shift;
  my $reply        = shift;

  if( ref($full_ch_name) eq 'HASH' && $full_ch_name->{full_ch_name} )
  {
    $full_ch_name = $full_ch_name->{full_ch_name};
  }

  $reply =~ s/^debug: ?//;

  my $reply_prefix = $this->config_get('reply_prefix');
  my $reply_suffix = $this->config_get('reply_suffix');
  defined($reply_prefix) or $reply_prefix = '';
  defined($reply_suffix) or $reply_suffix = '';
  my $msg_to_send = Auto::Utils->construct_irc_message(
    Command => 'NOTICE',
    Params  => [ '', $reply_prefix."debug: $reply".$reply_suffix ],
  );
  $DEBUG and print __PACKAGE__."#_debug, ".$msg_to_send->param(1)."\n";

  #$this->_error("_debug: full_ch_name: ".Data::Dumper->new([$full_ch_name])->Indent(0)->Dump);
  my ($ch_short,$net_name) = Multicast::detach($full_ch_name);

  # send to clients.
  #
  my $ch_on_client = Multicast::attach_for_client($ch_short, $net_name);
  my $for_client = $msg_to_send->clone;
  $for_client->param(0, $ch_on_client);
  $for_client->remark('fill-prefix-when-sending-to-client', 1);
  RunLoop->shared_loop->broadcast_to_clients($for_client);
}

# -----------------------------------------------------------------------------
# $list = $pkg->_config_reserved_addresses().
#
sub _config_reserved_addresses
{
  my $this = shift || __PACKAGE__;

  our $RESERVED_ADDRESSES ||= [
    [ 0, 0, '0.0.0.0/8',        'Current network',                     'RFC 1700', ],
    [ 0, 0, '10.0.0.0/8',       'Private network',                     'RFC 1918', ],
    [ 0, 0, '14.0.0.0/8',       'Public data networks',                'RFC 1700', ],
    [ 0, 0, '39.0.0.0/8',       'Reserved',                            'RFC 1797', ],
    [ 0, 0, '127.0.0.0/8',      'Loopback',                            'RFC 3330', ],
    [ 0, 0, '128.0.0.0/16',     'Reserved (IANA)',                     'RFC 3330', ],
    [ 0, 0, '169.254.0.0/16',   'Link-Local',                          'RFC 3927', ],
    [ 0, 0, '172.16.0.0/12',    'Private network',                     'RFC 1918', ],
    [ 0, 0, '191.255.0.0/16',   'Reserved (IANA)',                     'RFC 3330', ],
    [ 0, 0, '192.0.0.0/24',     'Reserved (IANA)',                     'RFC 3330', ],
    [ 0, 0, '192.0.2.0/24',     'Documentation and example code',      'RFC 3330', ],
    [ 0, 0, '192.88.99.0/24',   'IPv6 to IPv4 relay',                  'RFC 3068', ],
    [ 0, 0, '192.168.0.0/16',   'Private network',                     'RFC 1918', ],
    [ 0, 0, '198.18.0.0/15',    'Network benchmark tests',             'RFC 2544', ],
    [ 0, 0, '223.255.255.0/24', 'Reserved (IANA)',                     'RFC 3330', ],
    [ 0, 0, '255.255.255.255',  'Broadcast',                           '',         ],
    [ 0, 0, '224.0.0.0/4',      'Multicasts (former Class D network)', 'RFC 3171', ],
    [ 0, 0, '240.0.0.0/4',      'Reserved (former Class E network)',   'RFC 1700', ],
  ];
  if( !$RESERVED_ADDRESSES->[-1][0] )
  {
    foreach my $info (@$RESERVED_ADDRESSES)
    {
      my $cidr = $info->[2];
      my ($addr, $mask) = $this->_split_cidr($cidr);
      defined($addr) or die "invalid cidr: $cidr";
      $info->[0] = $addr;
      $info->[1] = $mask;
    }
  }
  $RESERVED_ADDRESSES;
}

# -----------------------------------------------------------------------------
# ($addr, $mask) = $pkg->_split_cidr($cidr).
#
sub _split_cidr
{
  my $this = shift;
  my $cidr = shift;

  my @digits = split(/\D+/, $cidr);
  my ($addr, $mask);
  if( @digits == 5 )
  {
    $addr = ($digits[0] << 24) | ($digits[1] << 16) | ($digits[2] << 8) | $digits[3];
    $mask = -1-((1<<(32-$digits[4]))-1);
  }elsif( @digits == 4 )
  {
    $addr = ($digits[0] << 24) | ($digits[1] << 16) | ($digits[2] << 8) | $digits[3];
    $mask = -1;
  }else
  {
    return ();
  }

  $mask &= 0xFFFF_FFFF;
  $addr &= $mask;

  wantarray or die "_split_cidr should call with array-context";
  ($addr, $mask);
}

# -----------------------------------------------------------------------------
# End of Module.
# -----------------------------------------------------------------------------

=begin tiarra-doc

info:    発言に含まれるURLからタイトルを取得.
default: off

# リクエストタイムアウトまでの時間(秒).
timeout: 3

# 有効にするチャンネルとオプションとURLの設定.
# 書式: mask: <channel> [<&conf>...] <url>
#
# mask: #test@ircnet &test http://*
# mask: * http://*
mask: * http://*

# &test と設定すると conf-test ブロックの中身が使われる.
#conf-test {
#  auth-test1 {
#    url:  http://example.com/*
#    url:  http://example.org/*
#    user: test
#    #pass: test
#    pass: {BASE64}dGVzdAo=
#  }
#  filter-xx {
#    url:  http://example.com/*/xx/*
#    type: xx
#  }
#}

# お返事の前や後ろにつける字句.
reply-prefix: "(FetchTitle) "
reply-suffix: " [AR]"

# デバッグフラグ.
#debug: 0
#debug-mask: #debug-chan your_nick!~you@example.com
#debug-dumpfile: fetchtitle.log

# NOTE:
#  利用するにはcodereposから
#  module/Tools/HTTPClient.pm     rev.8220
#  main/Tiarra/Socket/Buffered.pm rev.8219 
#  以降が必要です.

=end tiarra-doc

=head1 NAME

Auto::FetchTitle - tiarra-module: fetch title from url.

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

 + Auto::FetchTitle {
   reply-prefix: "(FetchTitle) "
   reply-suffix: " [AR]"
 
   mask: * http://*
 }

See all.conf or sample in tiarra-doc.

=head1 AUTHOR

YAMASHINA Hio, C<< <hio at cpan.org> >>

=head1 SEE ALSO

L<tiarra>

http://coderepos.org/share/wiki/Tiarra

=head1 COPYRIGHT & LICENSE

Copyright 2008 YAMASHINA Hio, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

