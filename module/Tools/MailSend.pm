# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

# メール送信ラッパ。複数のサーバに非同期で送信する。
# 実体は Tools::MailSend::EachServer に記述してあり、これはコントロールクラスである。

package Tools::MailSend;
use strict;
use warnings;
use Tiarra::SharedMixin;
use Module::Use qw(Tools::MailSend::EachServer);
use Tools::MailSend::EachServer;
our $_shared_instance;

sub _new {
  my ($class) = @_;
  my $this = 
    {
     # servers
     servers => [],
     # structure:
     #  server

    };
  bless $this, $class;

  return $this;
}

sub mail_send {
  # メール送信を行う。
  # 既存のサーバを探し(なければ作る)、それに丸投げします。

  my ($this, %arg) = @_;
  my ($server) = $this->_get_server(%arg);

  return $server->mail_send_reserve(%arg);
}

sub _get_server {
  my ($this, %args) = @_;

  return $this->{servers}->[$this->_get_server_index(%args)];
}

sub _get_server_index {
  my ($this, %arg) = @_;
  my (%data);

  # default value and convert struct
  $data{'use_pop3'} = $arg{'use_pop3'} || 0;
  $data{'pop3_host'} = $arg{'pop3_host'} || 'localhost';
  $data{'pop3_port'} = $arg{'pop3_port'} || getservbyname('pop3', 'tcp') || 110;
  $data{'pop3_user'} = $arg{'pop3_user'} || (getpwuid($>))[0];
  $data{'pop3_pass'} = $arg{'pop3_pass'} || '';
  $data{'pop3_expire'} = $arg{'pop3_expire'} || 0;
  $data{'smtp_host'} = $arg{'smtp_host'} || 'localhost';
  $data{'smtp_port'} = $arg{'smtp_port'} || getservbyname('smtp', 'tcp') || 25;
  $data{'smtp_fqdn'} = $arg{'smtp_fqdn'} || 'localhost';
  $data{'local'} = 
    {
     parent => $this,
    };
  $data{'cleaner'} = \&_server_cleaner;

  # find.
  my $i;
 server:
  for ($i = scalar(@{$this->{servers}}) - 1 ; $i >= 0 ; --$i) {
    my $server = $this->{servers}->[$i];
    foreach my $key (keys %data) {
      if ($key ne 'local') {
	next server unless $data{$key} eq $server->get_data($key);
      } else {
	next server unless $data{$key}->{parent} eq $server->get_data($key)->{parent};
      }
    }
    # match.
    return $i;
  }

  # make.
  my $idx = scalar(@{$this->{servers}}); # new entry!
  $data{'local'}->{parent_index} = $idx;
  my $server = Tools::MailSend::EachServer->new(%data);
  push(@{$this->{servers}}, $server);
  return $idx;
}

sub _server_cleaner {
  my ($server) = @_;

  my $this = $server->get_data('local')->{parent};
  my $idx = $server->get_data('local')->{parent_index};

  splice(@{$this->{servers}}, $idx, 1); # remove server
  return 0;
}

sub _do_nothing {
  # noop func
}

#--- class method ---
sub DATA_TYPES {
  return Tools::MailSend::EachServer::DATA_TYPES();
}

sub parse_mailaddrs {
  my $sub = sub {
    my ($temp) = @_;
    $temp =~ s/,/\\,/;
    $temp;
  };

  my (@addrs) = @_;
  @addrs = map {
    my ($temp) = $_;
    $temp =~ s/\\,/,/g;
    $temp;
  } map {
    split /\s*(?<!\\),\s*/;
  } map {
    my ($temp) = $_;
    $temp =~ s/\\,/\\\\,/g;
    $temp =~ s/("(?:[^"]+|\\")+")/$sub->($1)/eg;
    $temp;
  } @addrs;

  if (wantarray) {
    return map {
      if ($_ =~ />$/) {
	/<([^<]+)>$/;
	$1;
      } elsif ($_ =~ /"$/) {
	'';
      } else {
	$_;
      }
    } @addrs;
  } else {
    return [@addrs];
  }
}

1;
