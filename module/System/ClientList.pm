# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# System::ClientList
# -----------------------------------------------------------------------------
package System::ClientList;
use strict;
use warnings;
use base qw(Module);
use base qw(Tiarra::IRC::NewMessageMixin);
use Scalar::Util qw(weaken);

our $DEFAULT_COMMAND = 'clientlist';

sub new
{
  my $pkg = shift;
  my $this = $pkg->SUPER::new(@_);

  $this;
}

sub destruct
{
  my $this = shift;
}

sub message_arrived
{
  my ($this, $msg, $sender) = @_;

  my @result = $msg;
  eval {
    $this->_message_arrived(\@result, $sender);
  };
  if( $@ )
  {
    $this->_runloop->notify_error("$@");
  }

  @result = grep{ $_ } @result;
  @result;
}

sub _message_arrived
{
  my ($this, $result, $sender) = @_;
  my $msg = $result->[0];

  if( !$sender->isa("IrcIO::Client") )
  {
    return;
  }

  my $cmd = uc($this->config->command || $DEFAULT_COMMAND);

  if( $msg->command eq $cmd )
  {
    $this->_reply_client_list($msg, $sender);
    @$result = ();
  }
}

sub _reply_client_list
{
  my $this   = shift;
  my $msg    = shift;
  my $sender = shift;

  my $tmpl  = __PACKAGE__->construct_irc_message(
    Command => 'NOTICE',
    Params => [$this->_runloop->current_nick, undef],
  );
  my $reply = sub{
    my $res = $tmpl->clone();
    $res->param(1, "*** ".$_[0]);
    $sender->send_message($res);
  };

  my @list;
  my $runloop = $this->_runloop;
  if( ref($runloop->{clients}) eq 'ARRAY' )
  {
    @list = @{$runloop->{clients}};
  }
  my $nr_clients = @list;

  $reply->( "$nr_clients ".($nr_clients==1?"client":"clients") );
  my $i = 0;
  foreach my $client (@list)
  {
    ++$i;
    my $cl;
    if( !$client )
    {
      $cl = '-';
    }else
    {
      my $sock = $client->isa("Tiarra::Socket") && $client->sock;
      if( $sock )
      {
        my $addr = $sock->peerhost;
        my $port = $sock->peerport;
        $cl = "$addr:$port";
      }else
      {
        $cl = "$client";
      }
    }
    $reply->( "[$i] $cl");
  }
}

1;

=begin tiarra-doc

info:    Clientsの一覧を取得.
default: off
#section: important

# 接続しているクライアントを一覧.
# /clientlist を投げると, その時に接続しているクライアントの一覧を返す.
# 出力例:
# clientlist
#   *** 1 client
#   *** [1] 127.0.0.1:23695


# 一覧を返すトリガーとするコマンド.
-command: clientlist

=end tiarra-doc

=cut
