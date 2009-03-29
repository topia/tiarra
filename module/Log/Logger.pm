# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Log::Logger;
use strict;
use warnings;
use Multicast;

our $MARKER = {
  myself => {
    PRIVMSG => ['>','<'],
    NOTICE  => [')','('],
  },
  priv => {
    PRIVMSG => ['-','-'],
    NOTICE  => ['=','='],
  },
  channel => {
    PRIVMSG => ['<','>'],
    NOTICE  => ['(',')'],
  },
};

sub new {
    my ($class,$enstringed_callback,$exception_object,@exceptions) = @_;
    # enstringed_callback:
    #   メッセージをログ文字列化した時に呼ばれる関数。CODE型。
    #   引数を二つ取り、一つ目はチャンネル名、二つ目はログ文字列。
    # exception_object:
    #   exceptionsで指定されたメソッドを呼ぶとき、どのオブジェクトで呼ぶか。
    # exceptions:
    #   特定のメッセージのログ文字列化をオーバーライドする
    #   'S_PRIVMSG'等。
    #   引数は(Tiarra::IRC::Message,IrcIO)、戻り値は[チャンネル名,ログ文字列]の配列
    my $this = {
	enstringed => $enstringed_callback,
	exception_object => $exception_object,
	exceptions => do {
	    my %hash = map { $_ => 1 } @exceptions;
	    \%hash;
	},
    };
    bless $this,$class;
}

sub log {
    my ($this,$msg,$sender) = @_;
    my $prefix = do {
	if ($sender->isa('IrcIO::Server')) {
	    'S';
	}
	elsif ($sender->isa('IrcIO::Client')) {
	    'C';
	}
    };
    my $method_name = "${prefix}_".$msg->command;
    my @results;
    # このメソッドはexceptionsで定義されているか？
    if (defined $this->{exceptions}->{$method_name}) {
	eval {
	    @results = $this->{exception_object}->$method_name($msg,$sender);
	}; if ($@) {
	    RunLoop->shared->notify_error($@);
	}
    }
    else {
	# このクラスにメソッドはあるか？
	if ($this->can($method_name)) {
	    eval {
		@results = $this->$method_name($msg,$sender);
	    }; if ($@) {
		RunLoop->shared->notify_error($@);
	    }
	}
    }
    
    foreach (@results) {
	$this->{enstringed}->($_->[0],$_->[1]);
    }
}

sub S_JOIN {
    my ($this,$msg,$sender) = @_;
    
    $msg->param(0) =~ m/^([^\x07]+)(?:\x07(.*))?/;
    my ($ch_name,$mode) = ($1,(defined $2 ? $2 : ''));
    $mode =~ tr/ov/@+/;

    [$msg->param(0),
     sprintf('+ %s%s (%s) to %s',
	     $mode,$msg->nick,$msg->prefix,$msg->param(0))];
}

sub S_PART {
    my ($this,$msg,$sender) = @_;
    if (defined $msg->param(1)) {
	[$msg->param(0),
	 sprintf('- %s from %s (%s)',
		 $msg->nick,$msg->param(0),$msg->param(1))];
    } else {
	[$msg->param(0),
	 sprintf('- %s from %s',
		 $msg->nick,$msg->param(0))];
    }
}

sub S_KICK {
    my ($this,$msg,$sender) = @_;
    # RFC2812には、「サーバはクライアントに複数のチャンネルやユーザのKICKメッセージを
    # 送っては「いけません」。これは、古いクライアントソフトウェアとの下位互換のためです。」とある。
    [$msg->param(0),
     sprintf('- %s by %s from %s (%s)',
	     $msg->param(1),$msg->nick,$msg->param(0),$msg->param(2))];
}

sub S_INVITE {
    my ($this,$msg,$sender) = @_;
    [$msg->param(1),
	sprintf 'Invited by %s: %s',$msg->nick,$msg->param(1)];
}

sub S_MODE {
    my ($this,$msg,$sender) = @_;
    [$msg->param(0),
     sprintf('Mode by %s: %s %s',
	     $msg->nick,
	     $msg->param(0),
	     join(' ',@{$msg->params}[1 .. ($msg->n_params - 1)]))];
}

sub S_NICK {
    my ($this,$msg,$sender) = @_;
    my $network_name = $sender->network_name;
    my $line = do {
	sprintf(
	    do {
		if ($msg->param(0) eq $sender->current_nick) {
		    'My nick is changed (%s -> %s)';
		}
		else {
		    '%s -> %s';
		}
	    },
	    $msg->nick,
	    $msg->param(0));
    };
    my @result;
    if( my $ch_short_list = $msg->remark('affected-channels') ){
    foreach my $ch_name (@$ch_short_list) {
	push @result,[Multicast::attach($ch_name,$network_name),
		      $line];
    }
    }
    @result;
}

{
no warnings 'once';
*S_KILL = \&S_QUIT;
}

sub S_QUIT {
    my ($this,$msg,$sender) = @_;
    my $network_name = $sender->network_name;
    my @result;
    if( my $ch_short_list = $msg->remark('affected-channels') ){
    foreach my $ch_name (@$ch_short_list) {
	push @result,[Multicast::attach($ch_name,$network_name),
		      sprintf '! %s (%s)',$msg->nick,$msg->param(0)];
    }
    }
    @result;
}

sub S_TOPIC {
    my ($this,$msg,$sender) = @_;
    [$msg->param(0),
     sprintf('Topic of channel %s by %s: %s',
	     $msg->param(0),
	     $msg->nick,
	     $msg->param(1))];
}

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
  my $line = $this->_build_message($msg, $sender);
  my $channel = $line->{is_priv} ? 'priv' : $line->{ch_long};
  [$channel, $line->{formatted}];
}

# -----------------------------------------------------------------------------
# $hashref = $obj->_build_message($msg, $sender).
# Log/Channel から拝借.
# ただ
# - distinguish_myself が省かれている.
# - PRIVでも相手の名前がchannel名として使われる.
# - 好きにformat出来るように解析した情報をHASHREFで返している.
# という点で変更されている.
#
sub _build_message
{
  my ($this, $msg, $sender) = @_;

  my $raw_target = $msg->param(0);
  my ($target,$netname,$_explicit) = Multicast::detatch( $raw_target );
  my $is_priv = Multicast::nick_p($target);
  my $cmd     = $msg->command;

  my $marker_id;
  if( $sender->isa('IrcIO::Client') )
  {
    $marker_id = 'myself';
  }elsif( $is_priv )
  {
    $marker_id = 'priv';
  }else
  {
    $marker_id = 'channel';
  }
  my $marker = $MARKER->{$marker_id}{$cmd};
  $marker or die "no marker for $marker_id/$cmd";

  my ($speaker, $ch_short);
  if( $sender->isa('IrcIO::Client') )
  {
    # 自分の発言.
    $speaker  = RunLoop->shared_loop->network( $netname )->current_nick;
    $ch_short = $target;
  }else
  {
    # 相手の.
    $speaker  = $msg->nick || $sender->current_nick;
    $ch_short = $is_priv ? $speaker : $target;
  }
  my $ch_long = Multicast::attach($ch_short, $netname);

  my $line = sprintf(
    '%s%s:%s%s %s',
    $marker->[0],
    $ch_long,
    $speaker,
    $marker->[1],
    $msg->param(1),
  );

  +{
    marker_id => $marker_id, # 'myself' / 'priv' / 'channel'
    is_priv   => $is_priv,
    marker    => $marker,    # ['<', '>'], etc.
    speaker   => $speaker,
    ch_long   => $ch_long,
    ch_short  => $ch_short,
    netname   => $netname,
    msg       => $msg->param(1),
    command   => $msg->command(),
    time      => $msg->time(),
    #msg_orig  => $msg,
    formatted => $line,
  };
}

1;
