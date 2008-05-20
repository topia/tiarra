## ----------------------------------------------------------------------------
#  Auto::FetchTitle::Plugin::Mixi.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2008 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::FetchTitle::Plugin::Mixi;
use strict;
use warnings;
use base 'Auto::FetchTitle::Plugin';

# mixi のコンテンツの読み込み.
# 非公開な日記やコミュもあるので,
# 設定で許可した箇所のみの取得を基本とする.
#
# 現時点で取得できるページ:
# - ニュース
# - コミュニティ
#
# 未対応のページ:
# - マイミクページ
# - 日記
# - アルバム, 動画, ミュージッック等.

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
  $this->{cookie_jar} = [];
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
    name => 'mixi',
    'filter.prereq'   => \&filter_prereq,
    'filter.response' => \&filter_response,
  });
}

# -----------------------------------------------------------------------------
# $this->detect_page($ctx, $req, $block).
# 取得できるページか確認.
#
sub detect_page
{
  my $this  = shift;
  my $ctx   = shift;
  my $req   = shift;
  my $block = shift;

  $DEBUG and $ctx->_debug(__PACKAGE__."#detect_page, $req->{url}.");
  my @allow_pages = (
    {
      name     => 'login',
      can_show => 0,
      re       => qr{^\Qhttp://mixi.jp/login.pl\E\z},
    },
    {
      name     => 'news-login',
      can_show => 0,
      re       => qr{^\Qhttp://mixi.jp/issue_ticket.pl?},
    },
    {
      name     => 'login-check',
      can_show => 0,
      re       => qr{^\Qhttp://mixi.jp/check.pl?},
    },
    {
      name     => 'news',
      can_show => 1,
      re       => qr{^\Qhttp://news.mixi.jp/view_news.pl?},
    },
    {
      name     => 'news-list-media',
      can_show => 1,
      re       => qr{^\Qhttp://news.mixi.jp/list_news_media.pl?},
    },
    {
      name     => 'news-list-category',
      can_show => 1,
      re       => qr{^\Qhttp://news.mixi.jp/list_news_category.pl?},
    },
    {
      name     => 'community-top',
      can_show => 1,
      re       => qr{^\Qhttp://mixi.jp/view_community.pl?id=\E(\d+)\z},
      keys     => ['community'],
    },
    {
      name     => 'community-bbs-list',
      can_show => 1,
      re       => qr{^http://mixi\.jp/list_bbs\.pl\?id=(\d+)&type=(?:bbs|event|enquete)\z},
      keys     => ['community'],
    },
    {
      name     => 'community-bbs-show',
      can_show => 1,
      re       => qr{^http://mixi\.jp/view_(bbs|event|enquete)\.pl\?(?:page=\d+&)?id=\d+&(?:comment_count=\d+&)?comm_id=(\d+)(?:&page=all)?\z},
      keys     => ['','community'],
    },
    {
      name     => 'friend',
      can_show => 1,
      re       => qr{^http://mixi\.jp/show_friend.pl\?id=(\d+)\z},
      keys     => ['friend'],
    },
    {
      name     => 'friend-list-diary/album/review/comment',
      can_show => 1,
      re       => qr{^http://mixi\.jp/list_(?:diary|album|review|comment)\.pl\?(?:page=\d+&)?id=(\d+)(?:&year=\d+&month=\d+(?:&day=\d+)?)?\z},
      keys     => ['friend'],
    },
    {
      name     => 'friend-list-video/music',
      can_show => 1,
      re       => qr{^http://(video|music)\.mixi\.jp/list_\1\.pl\?id=(\d+)\z},
      keys     => ['', 'friend'],
    },
    {
      name     => 'friend-diary',
      can_show => 1,
      re       => qr{^http://mixi\.jp/view_diary\.pl\?id=\d+&owner_id=(\d+)\z},
      keys     => ['friend'],
    },
    {
      name     => 'friend-video',
      can_show => 1,
      re       => qr{^http://video\.mixi\.jp/view_video\.pl\?owner_id=(\d+)&video_id=\d+\z},
      keys     => ['friend'],
    },
    {
      name     => 'friend-review',
      can_show => 1,
      re       => qr{^http://mixi\.jp/view_item\.pl?reviewer_id=(\d+)&id=\d+\z},
      keys     => ['friend'],
    },
  );

  foreach my $page (@allow_pages)
  {
    $DEBUG and $ctx->_debug($req, "- check $page->{name}.");
    my @values = $req->{url} =~ $page->{re};
    my $keys = $page->{keys} || [''];
    if( @values != @$keys)
    {
      $DEBUG and $ctx->_debug($req, "- - not match.");
      next;
    }
    $page->{values} = \@values;

    foreach my $idx (0..$#$keys)
    {
      my $key = $keys->[$idx];
      $key or next;
      my $val = $page->{values}[$idx];
      my $conf_key = "mixi_$key";
      my $allowed;
      foreach my $conf_val ($block->$conf_key('all'))
      {
        $allowed ||= $conf_val && $conf_val == $val;
      }
      if( !$allowed )
      {
        $DEBUG and $ctx->_debug($req, "- - not match / mixi-$key = $val");
        return;
      }
    }
    $DEBUG and $ctx->_debug($req, "- - match.");
    return $page;
  }
  return undef;
}

# -----------------------------------------------------------------------------
# $this->filter_prereq($ctx, $arg).
# (impl:fetchtitle-filter)
# mixi/prereq.
#
sub filter_prereq
{
  my $this = shift;
  my $ctx  = shift;
  my $arg  = shift;

  my $req   = $arg->{req};
  my $block = $arg->{block};

  $DEBUG and $ctx->_debug($req, "- mixi.check multiple login pages.");
  my $seen = { login => 0, news_login => 0 };
  my $prev = $req;
  while( $prev )
  {
    if( $prev->{url} eq 'http://mixi.jp/login.pl' )
    {
      ++$seen->{login};
      $DEBUG and $ctx->_debug($req, "- login-page: $prev->{url}");
    }elsif( $prev->{url} =~ m{^\Qhttp://mixi.jp/issue_ticket.pl?\E} )
    {
      ++$seen->{news_login};
      $DEBUG and $ctx->_debug($req, "- news-login-page: $prev->{url}");
    }else
    {
      $DEBUG and $ctx->_debug($req, "- normal-page: $prev->{url}");
    }
    $prev = $prev->{old};
  }
  if( $seen->{login} >= 2 || $seen->{news_login} >= 3 )
  {
    my $msg = "login pages (login=$seen->{login},news_login=$seen->{news_login})";
    #$ctx->_debug($req, $msg);
    #$req->{response} = "mixi multiple login pages (login=$seen->{login},news_login=$seen->{news_login})";
    #return;
  }

  my $allowed = $this->detect_page($ctx, $req, $block);
  if( !$allowed )
  {
    $req->{response} = "requested page in mixi is not permitted";
    return;
  }

  $ctx->_apply_recv_limit($req, 12*1024);

  $ctx->_add_cookie_header($req, $this->{cookie_jar});
}

# -----------------------------------------------------------------------------
# $this->filter_response($ctx, $arg).
# (impl:fetchtitle-filter)
# mixi/response.
#
sub filter_response
{
  my $this = shift;
  my $ctx  = shift;
  my $arg  = shift;

  my $req   = $arg->{req};
  my $block = $arg->{block};

  if( $req->{parsed_cookies} )
  {
    $ctx->_merge_cookies($this->{cookie_jar}, $req->{parsed_cookies});
  }

  if( !ref($req->{response}) )
  {
    $DEBUG and $ctx->_debug($req, "debug: - - skip/not ref");
    return;
  }

  my $result = $req->{result};
  if( $result->{decoded_content} =~ m{<form action="(/login.pl)" method="post" name="login_form">(.*)</form>}s )
  {
    my $path = $1;
    my $form = $2;
    $DEBUG and $ctx->_debug($req, __PACKAGE__."#_filter_mixi_response, login form found ($path)");
    $this->_do_login($ctx, $req, $block, $form, $path);
  }else
  {
    my $page = $this->detect_page($ctx, $req, $block);
    if( !$page )
    {
      $req->{response} = "requested page in mixi is not permitted";
      return;
    }
  }
}

sub _do_login
{
  my $this = shift;
  my $ctx  = shift;
  my $req  = shift;
  my $block = shift;
  my $form = shift;
  my $path = shift;

  my @post;
  my $redir_url = 'http://'.($req->{headers}{Host}||'mixi.jp').$path;
  while( $form =~ m{<input\s+(.*?)>}sg )
  {
    my $attrs = $1;
    my %attrs = $attrs =~ /(\w+)="(.*?)"/g;
    my $name  = $attrs{name}  or next;
    my $value = $attrs{value};
    $name    = $ctx->_unescapeHTML($name);
    $value &&= $ctx->_unescapeHTML($value);
    if( $name eq 'email' )
    {
      $value = $ctx->_decode_value($this->{config}->mixi_user);
      if( !$value )
      {
        $ctx->_debug($req, "no mixi-user");
        return;
      }
    }
    if( $name eq 'password' )
    {
      $value = $ctx->_decode_value($this->{config}->mixi_pass);
      if( !$value )
      {
        $ctx->_debug($req, "no mixi-pass");
        return;
      }
    }
    defined($value) or next;
    $value =~ s{([^\w./])}{sprintf('%%%02x',unpack("C",$1))}ge;
    push(@post, "$name=$value");
  }
  if( @post )
  {
    $req->{result}{redirect} = {
      url     => $redir_url,
      method  => 'POST',
      content => join('&', @post),
      max_redirects => 7,
    };
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

info:    Mixiにログインして見出し抽出出来るようにするFetchTitleプラグイン.
default: off

# Auto::FetchTitle { ... } での設定.
#
# + Auto::FetchTitle {
#    mask: #* &mixi http://*
#    plugins {
#      Mixi {
#        mixi-user: xxx
#        mixi-pass: yyy
#      }
#    }
#    conf-mixi {
#      filter-mixi {
#        url: http://mixi.jp/*
#        url: http://news.mixi.jp/*
#        type: mixi
#        timeout: 10
#        #閲覧可能なコミュニティの指定.
#        #mixi-community: 0
#      }
#    }
#  }
#
# アカウント情報は plugins Mixi に記述.
# mixi-pass には {B}bbbb でBASE64エンコード値も可能.
#
# newsだけしか使わない場合でも, ログイン処理が必要なので
# mixi.jp/* 側も必要になります.

=end tiarra-doc

=cut

