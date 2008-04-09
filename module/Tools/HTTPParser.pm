## ----------------------------------------------------------------------------
#  Tools::HTTPParser.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Tools::HTTPParser;
use strict;
use warnings;

#our $HAS_HTTP_PARSER ||= do{
#  eval 'local($SIG{__DIE__})="DEFAULT";use HTTP::Parser; 1;';
#  $@ and RunLoop->shared_loop->notify_msg(__PACKAGE__.", HTTP::Parser: $@");
#  !$@;
#};

our $RE_REQUEST_GREETING = qr{
  ^
  (\w+)     # method:GET/POST/tec.
  (?:\s+)
  (\S+?)     # path:/
  (?:
    (?:\s+)
    (HTTP/.+?) # protocol:HTTP/1.0
  )?
  [ \t]*\r?\n
}ix;

our $RE_RESPONSE_GREETING = qr{
  ^
  (HTTP/\d+\.\d+) # protocol:HTTP/1.0
  (?:\s+)
  (\d+)     # status_code:200
  (?:\s+)
  (.+?)     # message:OK.
  [ \t]*\r?\n
}ix;

# constants.
our $RET_NEED_LINE_DATA = -2;
our $RET_NEED_MORE_DATA = -1;
our $RET_SUCCESS        = 0;

our %HTTP_STATUS_MESSAGE = (
  200 => 'OK',
  401 => 'Unauthorized',
  403 => 'Forbidden',
  404 => 'Not Found',
  500 => 'Server Error',
  503 => 'Temporary Unavailable',
);

our $DEBUG = 0;

1;

# -----------------------------------------------------------------------------
# $pkg->new().
# $pkg->new(request  => 1).
# $pkg->new(response => 1).
#
sub new
{
  my $pkg  = shift;
  my %opts = @_;

  my $this = bless {}, $pkg;
  $this->{parser}  = undef;
  $this->{recvbuf} = '';
  $this->{prevkey} = undef;
  $this->{rest}    = undef;
  $this->{reply}   = {
    StreamState => 'greeting', # greeting/header/body/parsed.
  };
  # [request]   / [response]  => [sample]
  # Protocol    / Protocol    => "HTTP/1.0",
  # Type        / Type        => request / response.
  # StreamState / StreamState => greeting/header/body/parsed.
  # Path        /             => "/path/to/?request",
  # Method      /             => "GET",
  #             / Code        => 200
  #             / Message     => "OK",
  # Header      / Header      => {},
  # Content     / Content     => undef,

  $this;
}

# -----------------------------------------------------------------------------
# $status = $pkg->add($packet).
#
sub add
{
  my $this = shift;
  my $packet = shift;

  $this->{recvbuf} .= $packet;

  $DEBUG and require Data::Dumper;
  $DEBUG and print __PACKAGE__."#add, StreamState = $this->{reply}{StreamState}\n";

  if( $this->{reply}{StreamState} eq 'greeting' )
  {
    my $taintness = substr($this->{recvbuf}, 0, 0);
    if( $this->{recvbuf} =~ s/$RE_REQUEST_GREETING// )
    {
      my $method = $1 . $taintness;
      my $path   = $2 . $taintness;
      my $proto  = $3 . $taintness;
      $this->{reply} = {
        StreamState => 'header', # greeting/header/body/parsed.
        Type        => 'request',
        Protocol    => $proto,
        Path        => $path,
        Method      => $method,
        Header      => {},
        Content     => undef,
      };
    }elsif( $this->{recvbuf} =~ s/$RE_RESPONSE_GREETING// )
    {
      my $proto  = $1 . $taintness;
      my $code   = $2 . $taintness;
      my $msg    = $3 . $taintness;
      $this->{reply} = {
        StreamState => 'header', # greeting/header/body/parsed.
        Type        => 'response',
        Protocol    => $proto,
        Code        => $code,
        Message     => $msg,
        Header      => {},
        Content     => undef,
      };
    }else
    {
      my $offs = index($this->{recvbuf}, "\n");
      if( $offs >= 0 )
      {
        my $line = substr($this->{recvbuf}, 0, $offs+1);
        $line =~ s/\r?\n\z//;
        die "invalid greeting: $line";
      }
      return $RET_NEED_LINE_DATA;
    }
    $this->{prevkey} = undef;
    $DEBUG and print __PACKAGE__."#add, got greeting, ".Data::Dumper->new([$this->{reply}],['reply'])->Indent(1)->Dump;
  }

  my $reply = $this->{reply};

  if( $reply->{StreamState} eq 'header' )
  {
    for(;;)
    {
      my $offs = index($this->{recvbuf}, "\n");
      if( $offs < 0 )
      {
        return $RET_NEED_LINE_DATA;
      }
      my $line = substr($this->{recvbuf}, 0, $offs+1, '');
      $line =~ s/\r?\n\z//;
      $DEBUG and print __PACKAGE__."#add, line> $line\n";
      if( $line eq '' )
      {
        last;
      }
      if( $line =~ s/^\s+/ / )
      {
        my $prevkey= $this->{prevkey};
        if( !defined($prevkey) )
        {
          die "invalid header(without previous key): $line";
        }
        $reply->{Header}{$prevkey} .= $line;
        next;
      }
      my ($key, $val) = split(/:\s*/, $line, 2);
      if( !defined($val) )
      {
        die "invalid header(no splitter): $line";
      }
      $key =~ s/(?:(?<=-)|^)([a-z])/\U$1/g;
      $reply->{Header}{$key} .= $val;
      $this->{prevkey} = $key;
    }

    $this->{rest} = $reply->{Header}{'Content-Length'};
    my $read_body = 0;
    if( defined($this->{rest}) )
    {
      # Content-Length で本文サイズが指定されているとき.
      $read_body = 1;
    }elsif( !$reply->{Method} )
    {
      # Response のとき.
      $read_body = 1;
    }elsif( $reply->{Method} eq 'POST' )
    {
      # Request/POST のとき.
      $read_body = 1;
    }else
    {
      # Request/POST以外 のとき.
      $read_body = 0;
    }
    if( !$read_body )
    {
      $reply->{StreamState} = 'parsed';
      return $RET_SUCCESS;
    }
    $reply->{StreamState} = 'body';
    $DEBUG and print __PACKAGE__."#add, got header, ".Data::Dumper->new([$this->{reply}],['reply'])->Indent(1)->Dump;
  }

  if( $reply->{StreamState} eq 'body' )
  {
    if( !defined($reply->{Content}) && $this->{recvbuf} ne '' )
    {
      $reply->{Content} = '';
    }
    my $ret;
    if( !defined($this->{rest}) )
    {
      $reply->{Content} .= $this->{recvbuf};
      $this->{recvbuf}   = '';
      $ret = $RET_NEED_MORE_DATA;
    }elsif( length($this->{recvbuf}) < $this->{rest} )
    {
      $this->{rest}     -= length($this->{recvbuf});
      $reply->{Content} .= $this->{recvbuf};
      $this->{recvbuf}   = '';
      $ret = $this->{rest};
    }else
    {
      $reply->{Content} .= substr($this->{recvbuf}, 0, $this->{rest}, '');
      $this->{rest} = undef;
      $reply->{StreamState} = 'parsed';
      $ret = $RET_SUCCESS;
    }
    $DEBUG and print __PACKAGE__."#add, got body, rest=$ret, reply=".Data::Dumper->new([$this->{reply}])->Indent(1)->Terse(1)->Dump;
    return $ret;
  }

  die "NOT REACH HERE: StreamState=$reply->{StreamState}";
}

# -----------------------------------------------------------------------------
# $obj->object().
#
sub object
{
  my $this = shift;
  $this->{reply};
}

# -----------------------------------------------------------------------------
# $len = $obj->extra().
# バッファに残っているデータサイズ(数値)を取得.
#
sub extra
{
  my $this = shift;
  length($this->{recvbuf});
}

# -----------------------------------------------------------------------------
# $str = $pkg->to_string($req).
# HTTPとして流せるテキストに変換.
# 要求行/ステータス行も含めた文字列を返します.
#
sub to_string
{
  my $pkg = shift;
  my $res = shift;

  if( !ref($res) )
  {
    $res = {
      Code => $res,
    };
  }

  my $type = $res->{Type} || ($res->{Method} ? 'request' : 'response');
  my $hdr = $res->{Header} || {};
  my $cref = defined($res->{Content}) && \$res->{Content};
  my $status_line;

  if( $type eq 'response' )
  {
    my $code    = $res->{Code}     || 500;
    my $proto   = $res->{Protocol} || 'HTTP/1.0';
    my $message = $res->{Message};
    $message ||= $HTTP_STATUS_MESSAGE{$code} || "No message";
    $status_line = "$proto $code $message\r\n";

    if( !$cref && !$res->{Header}{Location} )
    {
      $cref = \"$code $message";
    }
    if( !defined($hdr->{'Content-Length'}) && $cref )
    {
      $hdr = {%$hdr}; # sharrow-copy.
      $hdr->{'Content-Length'} = length($$cref);
    }
  }else
  {
    # request.
    my $method  = $res->{Method}   || 'GET';
    my $path    = $res->{Path}     || '/';
    my $proto   = $res->{Protocol} || 'HTTP/1.0';
    $status_line = "$method $path $proto\r\n";
  }

  my $str = '';
  $str .= $status_line;

  foreach my $key (sort keys %$hdr)
  {
    $str .= "$key: $hdr->{$key}\r\n";
  }
  $str .= "\r\n";

  if( $cref )
  {
    $str .= $$cref;
  }

  $str;
}

# -----------------------------------------------------------------------------
# $req = $pkg->from_lwp($lwp_http_request).
# $res = $pkg->from_lwp($lwp_http_response).
# LWPのHTTP::Request/HTTP::ResponseからTools::HTTPParser形式の
# オブジェクトを生成.
#
sub from_lwp
{
  my $pkg   = shift;
  my $htreq = shift;

  my $proto = $htreq->protocol;
  if( my $ver = !$proto && $htreq->header('x-http-version') )
  {
    $proto = "HTTP/$ver";
  }
  my $type = $htreq->isa('HTTP::Request') ? 'request' : 'response';
  my $obj = {
    StreamState => 'parsed',
    Type     => $type,
    Protocol => $proto,
    Header   => {
        map{ $_ => scalar($htreq->header($_)) } $htreq->headers->header_field_names
    },
    Content => $htreq->content,
    #_htreq  => $htreq,
  };
  if( $type eq 'request' )
  {
    $obj->{Method}  = $htreq->method;
    $obj->{Path}    = $htreq->uri->as_string;
  }else
  {
    $obj->{Code}    = $htreq->code;
    $obj->{Message} = $htreq->message;
  }
  $obj;
}

# -----------------------------------------------------------------------------
# $bool = $pkg->extract_forwarded_for($req, \@allows).
# ReverseProxyによって生成されるX-Forwarded-Forヘッダを
# $req->{RemoteAddr}/$req->{Header}{Host} に展開.
# @allows: 展開を許可するIPアドレスの一覧(X-Forwarded-Forの逆順).
# 書き換えると真の値を, 書き換えなかった時はundefの値を返す.
# 途中までしか一致しなかった時は RemoteAddr="-$addr-" で書き換える.
#
sub extract_forwarded_for
{
  my $pkg = shift;
  my $req = shift;
  my $allows = shift;

  $DEBUG and $pkg->_debug(__PACKAGE__."#_extract_forwarded_for.");
  $DEBUG and $pkg->_debug("- allow-chain has ".@$allows.(@$allows==1?" server":" servers"));
  $DEBUG and map{ $pkg->_debug("- allow[$_] = $allows->[$_]") } 0..$#$allows;

  my $hdr  = $req->{Header};

  if( !$req->{RemoteAddr} )
  {
    $DEBUG and $pkg->_debug("- no RemoteAddr field on request.");
    return undef;
  }
  if( !$hdr->{'X-Forwarded-For'} )
  {
    $DEBUG and $pkg->_debug("- no X-Forwarded-For header.");
    return undef;
  }
  if( !defined($hdr->{'X-Forwarded-Host'}) )
  {
    $DEBUG and $pkg->_debug("- no X-Forwarded-Host");
    return undef;
  }
  if( !defined($hdr->{'X-Forwarded-Server'}) )
  {
    $DEBUG and $pkg->_debug("- no X-Forwarded-Server");
    return undef;
  }

  my @copy_keys = qw(Host X-Forwarded-For X-Forwarded-Host X-Forwarded-Server);
  my $orig = {
    map{ exists($hdr->{$_}) ? ($_ => $hdr->{$_}) : () } @copy_keys
  };
  exists($req->{RemoteAddr}) and $orig->{RemoteAddr} = $req->{RemoteAddr};
  $DEBUG and map{ $pkg->_debug("- + $_: ".(defined($orig->{$_}) ? $orig->{$_} : exists($orig->{$_}) ? "{undef}" : "{none}")) } sort keys %$orig;

  # https://192.168.0.3/irc/
  # ==> http://localhost:8668/irc/
  # X-Forwarded-Server: fwd.example.com
  # X-Forwarded-Host:   192.168.0.3
  # X-Forwarded-For:    192.168.0.10

  # https://192.168.0.3/irc/
  # ==> https://fwd.example.com/irc2/ (fwd.example.com=10.0.0.4)
  # ==> http://localhost:8668/irc/
  # X-Forwarded-Server: fwd.example.com, fwd.example.com
  # X-Forwarded-Host:   192.168.0.3, fwd.example.com
  # X-Forwarded-For:    192.168.0.10, 10.0.0.4

  my $cur = {%$orig};
  my $is_success = 1;

  while( @$allows )
  {
    my $allow = shift @$allows;
    $DEBUG and $pkg->_debug("- next allow: $allow");
    if( $cur->{RemoteAddr} ne $allow )
    {
      $DEBUG and $pkg->_debug("- next forwarder $cur->{RemoteAddr} does not match with next allow $allow");
      $pkg->_debug(__PACKAGE__.", extract-forwarded-for is cancelled (not allowed, $cur->{RemoteAddr} for $allow)");
      $is_success = 0;
      last;
    }
    my $next = $cur;
    # 転送前情報を末尾から取り出し.
    my @fwd_keys = qw(X-Forwarded-For X-Forwarded-Host X-Forwarded-Server);
    my @vals = map{
      ($next->{$_} =~ s/(?:^|\s*,)\s*(\S+)\s*\z//) ? $1 : undef;
    } @fwd_keys;
    if( grep{ !defined($_) } @vals )
    {
      my ($idx) = grep{ !defined($vals[$_]) } 0..$#vals;
      my $key   = $fwd_keys[$idx];
      $DEBUG and $pkg->_debug("- invalid next $key [$next->{$key}]");
      $pkg->_debug(__PACKAGE__.", extract-forwarded-for is cancelled (short $key)");
      $is_success = 0;
      last;
    }
    my ($addr, $host, $svr) = @vals;
    $next->{RemoteAddr} = $addr;
    $next->{Host}     = $host;
    $DEBUG and $pkg->_debug("- extract: RemoteAddr=$addr, Host=$host");
    $cur = $next;
  }

  # $req に結果を反映.
  # 変更前のデータもついでに保持.
  $req->{_extract_orig} = $orig;
  $req->{RemoteAddr} = delete $cur->{RemoteAddr};
  %$hdr = ( %$hdr, %$cur );
  
  if( !$is_success )
  {
    $req->{RemoteAddr} = "-$req->{RemoteAddr}-";
  }
  $DEBUG and $pkg->_debug("- extract: RemoteAddr=$req->{RemoteAddr}, Host=$req->{Header}{Host}");

  1;
}

# -----------------------------------------------------------------------------
# $txt = $pkg->escapeHTML($html).
#
sub escapeHTML
{
  my $pkg = shift;
  my $html = shift;
  $html =~ s/&/&amp;/g;
  $html =~ s/</&lt;/g;
  $html =~ s/>/&gt;/g;
  $html =~ s/"/&quot;/g;
  $html =~ s/'/&#39;/g;
  $html;
}

# -----------------------------------------------------------------------------
# $pkg->_debug($msg).
# デバッグメッセージ送信用.
#
sub _debug
{
  my $this = shift;
  my $msg = shift;
  RunLoop->shared_loop->notify_msg($msg);
}

# -----------------------------------------------------------------------------
# End of Module.
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

=head1 NAME

Tools::HTTPParser - HTTP/1.0 parser for tiarra-modules.

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

 use Tools::HTTPParser;
 use Module::Use qw(Tools::HTTPParser);

 my $parser = Tools::HTTPParser->new();

 my $status = eval{ $parser->add($packet); }
 $@ and die ...;
 $status==0 or return; # in progress.
 my $res = $parser->object();
 my $req = $parser->object();

=head1 DESCRIPTION

HTTP::Parser と同様の HTTP パーサ.

tiarra モジュール Tools::HTTPClient と互換の動作.

結果の形式は以下の２種類.

  $request = {
    StreamState => 'parsed', # greeting/header/body/parsed.
    Type        => 'request',
    Protocol    => 'HTTP/1.0',
    Path        => '/path/to?request',
    Method      => 'GET',
    Header      => {},
    Content     => undef,
  };

  $response = {
    StreamState => 'parsed', # greeting/header/body/parsed.
    Type        => 'request',
    Protocol    => 'HTTP/1.0',
    Code        => 200,
    Message     => 'OK',
    Header      => {},
    Content     => undef,
  };

=head1 AUTHOR

YAMASHINA Hio, C<< <hio at cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 YAMASHINA Hio, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

