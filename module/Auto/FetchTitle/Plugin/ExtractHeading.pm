## ----------------------------------------------------------------------------
#  Auto::FetchTitle::Plugin::ExtractHeading.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::FetchTitle::Plugin::ExtractHeading;
use strict;
use warnings;
use base 'Auto::FetchTitle::Plugin';
use Mask;

our $DEBUG;
*DEBUG = \$Auto::FetchTitle::DEBUG;

1;

# -----------------------------------------------------------------------------
# $pkg->new(\%config).
#
sub new
{
  my $pkg   = shift;
  my $this = $pkg->SUPER::new(@_);
  $this;
}

# -----------------------------------------------------------------------------
# $obj->register($context).
#
sub register
{
  my $this = shift;
  my $context = shift;

  $context->register_hook($this, {
    name => 'extract-heading',
    'filter.prereq'   => \&filter_prereq,
    'filter.response' => \&filter_response,
  });
}

# -----------------------------------------------------------------------------
# $this->_config().
# config for extract-heading.
#
sub _config
{
  my $config = [
    {
      # 1. ぷりんと楽譜.
      url        => 'http://www.print-gakufu.com/*',
      recv_limit => 8*1024,
      extract    => qr{<p\s+class="topicPath">(.*?)</p>}s,
      #remove     => qr/^ぷりんと楽譜 総合案内 ＞ /;
    },
    {
      # 2. zakzak.
      url        => 'http://www.zakzak.co.jp/*',
      recv_limit => 10*1024,
      extract    => qr{<font class="kijimidashi".*?>(.*?)</font>}s,
    },
    {
      # 3. nikkei.
      url        => 'http://www.nikkei.co.jp/*',
      recv_limit => 16*1024,
      extract => [
        qr{<META NAME="TITLE" CONTENT="(.*?)">}s,
        qr{<h3 class="topNews-ttl3">(.*?)</h3>}s,
      ],
      remove => qr/^NIKKEI NET：/,
    },
    {
      # 4. nhkニュース.
      url     => 'http://www*.nhk.or.jp/news/*',
      extract => qr{<p class="newstitle">(.*?)</p>},
    },
    {
      # 5. creative (timeout).
      url     => 'http://*.creative.com/*',
      timeout => 5,
    },
    {
      # 6. soundhouse news.
      url        => 'http://www.soundhouse.co.jp/shop/News.asp?NewsNo=*',
      recv_limit => 50*1024,
      extract    => qr{(<td class='honbun'>\s*<font size='\+1'><b>.*?</b></font>.*?)<br>}s,
    },
    {
      # 7. trac changeset.
      url        => '*/changeset/*',
      extract    => qr{<dd class="message" id="searchable"><p>(.*?)</p>}s,
      recv_limit => 8*1024,
    },
    {
      # 8a. amazon (page size).
      url        => 'http://www.amazon.co.jp/*',
      recv_limit => 15*1024,
    },
    {
      # 8b. amazon (page size).
      url        => 'http://www.amazon.com/*',
      recv_limit => 15*1024,
    },
    {
      # 9. ニコニコ動画 (メンテ画面).
      status     => 503,
      url        => 'http://www.nicovideo.jp/*',
      extract    => sub{
        if( m{<div class="mb16p4 TXT12">\s*<p>現在ニコニコ動画は(メンテナンス中)です。</p>\s*<p>(.*?)<br />}s )
        {
          "$1: $2";
        }else
        {
          return;
        }
      },
    },
    {
      # 10. sanspo.
      url        => 'http://www.sanspo.com/*',
      recv_limit => 5*1024,
      extract    => qr{<h2>(.*?)</h2>}s,
    },
    {
      # 11. sakura.
      url        => 'http://www.sakura.ad.jp/news/archives/*',
      recv_limit => 10*1024,
      extract    => qr{<h3 class="newstitle">(.*?)</h3>}s,
    },
    {
      # 12. viewvc.
      url        => '*/viewcvs.cgi/*',
      extract    => qr{<pre class="vc_log">(.*?)</pre>}s,
    },
    {
      # 13. toshiba.
      url        => 'http://www.toshiba.co.jp/about/press/*',
      extract    => qr{<font size=\+2><b>(.*?)</b></font>}s,
    },
    {
      # 14. tv-asahi.
      url        => 'http://www.tv-asahi.co.jp/ann/news/*',
      extract    => qr{<FONT class=TITLE>(.*?)</FONT>}s,
    },
  ];
  $config;
}

# -----------------------------------------------------------------------------
# $this->filter_prereq($ctx, $arg).
# (impl:fetchtitle-filter)
# extract_heading/prereq.
#
sub filter_prereq
{
  my $this  = shift;
  my $ctx   = shift;
  my $arg   = shift;
  my $req  = $arg->{req};

  my $extract_list = $this->_config();

  foreach my $conf (@$extract_list)
  {
    Mask::match($conf->{url}, $req->{url}) or next;
    $DEBUG and $ctx->_debug($req, "debug: - $conf->{url}");
    if( my $new_recv_limit = $conf->{recv_limit} )
    {
      $ctx->_apply_recv_limit($req, $new_recv_limit);
      $DEBUG and $ctx->_debug($req, "debug: - recv_limit, $new_recv_limit");
    }
    if( my $new_timeout = $conf->{timeout} )
    {
      $ctx->_apply_timeout($req, $new_timeout);
      $DEBUG and $ctx->_debug($req, "debug: - timeout, $new_timeout");
    }
  }
}

# -----------------------------------------------------------------------------
# $this->filter_response($block, $req, $when, $type).
# (impl:fetchtitle-filter)
# extract_heading/response.
#
sub filter_response
{
  my $this  = shift;
  my $ctx   = shift;
  my $arg   = shift;
  my $req  = $arg->{req};

  my $response = $req->{response};
  if( !ref($response) )
  {
    $DEBUG and $ctx->_debug($req, "debug: - - skip/not ref");
    return;
  }
  my $status = $req->{result}{status_code};

  my $extract_list = $this->_config();

  my $heading;

  foreach my $conf (@$extract_list)
  {
    Mask::match($conf->{url}, $req->{url}) or next;
    $DEBUG and $ctx->_debug($req, "debug: - $conf->{url}");

    my $extract_status = $conf->{status} || 200;
    if( $status != $extract_status )
    {
      $DEBUG and $ctx->_debug($req, "debug: - - status:$status not match with $extract_status");
      next;
    }

    my $extract_list = $conf->{extract};
    if( ref($extract_list) ne 'ARRAY' )
    {
      $extract_list = [$extract_list];
    }
    foreach my $_extract (@$extract_list)
    {
      $DEBUG and $ctx->_debug($req, "debug: - $_extract");
      my $extract = $_extract; # sharrow-copy.
      $extract = ref($extract) ? $extract : qr/\Q$extract/;
      my @match;
      if( ref($extract) eq 'CODE' )
      {
        local($_) = $req->{result}{decoded_content};
        @match = $extract->($req);
      }else
      {
        @match = $req->{result}{decoded_content} =~ $extract;
      }
      @match or next;
      @match==1 && !defined($match[0]) and next;
      $heading = $match[0];
      last;
    }
    defined($heading) or next;
    $DEBUG and $ctx->_debug($req, "debug: - $heading");

    $heading = $ctx->_fixup_title($heading);

    my $remove_list = $conf->{remove};
    if( ref($remove_list) ne 'ARRAY' )
    {
      $remove_list = [$remove_list];
    }
    foreach my $_remove (@$remove_list)
    {
      my $remove = $_remove; # sharrow-copy.
      $remove = ref($remove) ? $remove : qr/\Q$remove/;
      $heading =~ s/$remove//;
    }
  }

  if( defined($heading) && $heading =~ /\S/ )
  {
    $heading =~ s/\s+/ /g;
    $heading =~ s/^\s+//;
    $heading =~ s/\s+$//;

    my $title = $req->{result}{result};
    $title = defined($title) && $title ne '' ? "$heading - $title" : $heading;

    $req->{result}{result} = $title;
  }
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

