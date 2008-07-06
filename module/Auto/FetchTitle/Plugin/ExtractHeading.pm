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
  *DEBUG = \$Auto::FetchTitle::DEBUG;

  $this->{extra} = undef;
  $this->_parse_extra_config();

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
# $this->_parse_extra_config().
# parse user config.
#
sub _parse_extra_config
{
  my $this = shift;
  my @config;
  $this->{extra} = \@config;

  $DEBUG and $this->notice(__PACKAGE__."#_parse_extra_config");
  $DEBUG and $this->notice(">> ".join(", ", map{split(' ', $_)}$this->config->extra('all')));

  foreach my $token (map{split(' ', $_)}$this->config->extra('all'))
  {
     $this->notice("extra: $token");
     my $name  = "extra-$token";
     my $block = $this->config->$name;
     if( !$block )
     {
       $this->notice("no such extra config: $name");
       next;
     }
     if( !ref($block) )
     {
       my $literal = $block;
       $block = Configuration::Block->new($name);
       $block->extract($literal);
     }
     my $has_param;
     my $config = {};
     $config->{name} = $name;
     $config->{url}  = $block->url;
     if( !$config->{url} )
     {
       $this->notice("no url on $name");
       next;
     }
     if( my $recv_limit = $block->get('recv_limit') )
     {
       while( $recv_limit =~ s/^\s*(\d+)\*(\d+)/$1*$2/e )
       {
       }
       $config->{recv_limit} = $recv_limit;
       $has_param = 1;
     }
     my @extract;
     foreach my $line ($block->extract('all'))
     {
       $has_param ||= 1;
       my $type;
       my $value = $line;
       if( $value =~ s/^(\w+)(:\s*|\s+)// )
       {
         $type = $1;
       }
       $type ||= 're';
       if( $type eq 're' )
       {
         $value =~ s{^/(.*)/(\w*)\z/}{(?$2:$1)};
         my $re = eval{
           local($SIG{__DIE__}) = 'DEFAULT';
           qr/$value/s;
         };
         if( my $err = $@ )
         {
           chomp $err;
           $this->notice("invalid regexp $re on $name, $err");
           next;
         }
         push(@extract, $re);
       }else
       {
         $this->notice("unknown extract type $type on $name");
         next;
       }
     }
     if( @extract )
     {
       $config->{extract} = @extract==1 ? $extract[0] : \@extract;
     }
     if( keys %$config==1 )
     {
       $this->notice("no config on $name");
       next;
     }
     push(@config, $config);
  }

  $this;
}

# -----------------------------------------------------------------------------
# $this->_config().
# config for extract-heading.
#
sub _config
{
  my $this = shift;
  my $config = [
    @{$this->{extra}},
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
      # 3a. nikkei.
      url        => 'http://www.nikkei.co.jp/*',
      recv_limit => 16*1024,
      extract => [
        qr{<META NAME="TITLE" CONTENT="(.*?)">}s,
        qr{<h3 class="topNews-ttl3">(.*?)</h3>}s,
      ],
      remove => qr/^NIKKEI NET：/,
    },
    {
      # 3b. nikkei.
      url        => 'http://release.nikkei.co.jp/*',
      recv_limit => 18*1024,
      extract => qr{<h1 id="heading" class="heading">(.*)</h1>}s,
    },
    {
      # 4a. nhkニュース.
      url     => 'http://www*.nhk.or.jp/news/*',
      extract => qr{<p class="newstitle">(.*?)</p>},
    },
    {
      # 4b. nhk関西のニュース.
      url        => 'http://www*.nhk.or.jp/*/lnews/*',
      recv_limit => 8*1024,
      extract    => qr{<h3>(.*?)</h3>},
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
      recv_limit => 10*1024,
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
    {
      # 15. game?
      url        => 'http://splax.net/jun.html?p=*',
      extract    => sub{
        my $req = shift;
        if( $req->{url} =~ /\?p=([^&;=#]+)/ )
        {
          my $q = $1;
          $q =~ s/%([0-9A-F]{2})/pack("H*",$1)/gie;
          $q =~ s/\*([0-9A-F]{2})/pack("H*",$1)/gie;
          $q = Unicode::Japanese->new($q, "sjis")->utf8;
          $q =~ s/\*.*//;
          $q = "「$qの唄」";
        }else
        {
          return;
        }
      },
    },
    {
      # 16. recordchina.
      url        => 'http://www.recordchina.co.jp/group/*',
      recv_limit => 12*1024,
      extract    => qr{<div id="news_detail_title" class="ft04">(.*?)</div>}s,
    },
    {
      # 17. oricon.groumet.
      url        => 'http://gourmet.oricon.co.jp/*',
      recv_limit => 15*1024,
      extract    => qr{<h1>(.*?)</h1>}s,
    },
    {
      # 18. biglobe.
      url        => 'http://news.biglobe.ne.jp/*',
      recv_limit => 30*1024,
      extract    => qr{<h4 class="ch15">(.*?)(?:&nbsp;.*)?</h4>}s,
    },
    {
      # 19. i-revo.
      url        => 'http://www.i-revo.jp/corporate/news/*',
      extract    => qr{<h2>.*?<h2>(.*?)</h2>}s,
    },
    {
      # 20. dq-status
      url        => 'http://u-enterprise.com/dqstatus/*',
      extract    => qr{<h1 id=maga_title>(.*?)</h1>}s,
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
    if( !$extract_list )
    {
      $DEBUG and $ctx->_debug($req, "debug: - - no extract");
      next;
    }
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
      $remove_list = defined($remove_list) ? [$remove_list] : [];
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

=begin tiarra-doc

info:    本文から見出しを抽出するFetchTitleプラグイン.
default: off

# Auto::FetchTitle { ... } での設定.
# + Auto::FetchTitle {
#     plugins {
#       ExtractHeading {
#         extra: name1 name2 ...
#         extra-name1 {
#           url:        http://www.example.com/*
#           recv_limit: 10*1024
#           extract:    re:<div id="title">(.*?)</div>
#         }
#       }
#    }
#  }

=end tiarra-doc

=cut

