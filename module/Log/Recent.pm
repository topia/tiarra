# -----------------------------------------------------------------------------
# $Id: Recent.pm,v 1.5 2003/09/23 15:26:10 admin Exp $
# -----------------------------------------------------------------------------
# Local: $Clovery: tiarra/module/Log/Recent.pm,v 1.5 2003/02/11 07:59:32 topia Exp $
package Log::Recent;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Tools::DateConvert Log::Logger);
use Tools::DateConvert;
use Log::Logger;
use IRCMessage;
use Mask;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    # チャンネル管理の手間を省くため、チャンネルのログはChannelInfoのremarksに保存する。
    # privのログだけこのクラスで保持。
    $this->{priv_log} = []; # 中身は単なる文字列
    $this->{logger} =
	Log::Logger->new(
	    sub {
		$this->log(@_);
	    },
	    $this,
	    'S_PRIVMSG','C_PRIVMSG','S_NOTICE','C_NOTICE');
    $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    # Log::Recent/commandにマッチするか？
    if (Mask::match(lc($this->config->command) || '*', lc($msg->command))) {
	$this->{logger}->log($msg,$sender);
    }
    $msg;
}

sub client_attached {
    my ($this,$client) = @_;
    # まずはpriv
    my $local_nick = RunLoop->shared->current_nick;
    foreach my $elem (@{$this->{priv_log}}) {
	$client->send_message(
	    IRCMessage->new(
		Command => 'NOTICE',
		Params => [$local_nick,$elem->[1]])); # $elem->[0]は常に'priv'
    }
    # 次に各チャンネル
    foreach my $network (values %{RunLoop->shared->networks}) {
	foreach my $ch (values %{$network->channels}) {
	    # ログはあるか？
	    my $vec = $ch->remarks('recent-log');
	    if (defined $vec) {
		my $ch_name;
		foreach my $elem (@$vec) {
		    $ch_name =
			RunLoop->shared->multi_server_mode_p ?
			    $elem->[0] : $ch->name;
		    $client->send_message(
			IRCMessage->new(
			    Prefix => 'Tiarra',
			    Command => 'NOTICE',
			    Params => [$ch_name,$elem->[1]]));
		}
	    }
	}
    }
}

*S_PRIVMSG = \&PRIVMSG_or_NOTICE;
*S_NOTICE = \&PRIVMSG_or_NOTICE;
*C_PRIVMSG = \&PRIVMSG_or_NOTICE;
*C_NOTICE = \&PRIVMSG_or_NOTICE;
sub PRIVMSG_or_NOTICE {
    my ($this,$msg,$sender) = @_;
    my $target = Multicast::detatch($msg->param(0));
    my $is_priv = Multicast::nick_p($target);
    my $cmd = $msg->command;

    my $line = do {
	if ($is_priv) {
	    if ($sender->isa('IrcIO::Client')) {
		sprintf(
		    $cmd eq 'PRIVMSG' ? '>%s< %s' : ')%s( %s',
		    $msg->param(0),
		    $msg->param(1));
	    }
	    else {
		sprintf(
		    $cmd eq 'PRIVMSG' ? '-%s- %s' : '=%s= %s',
		    $msg->nick || $sender->current_nick,
		    $msg->param(1));
	    }
	}
	else {
	    my $format = do {
		if ($this->config->distinguish_myself && $sender->isa('IrcIO::Client')) {
		    $cmd eq 'PRIVMSG' ? '>%s< %s' : ')%s( %s';
		}
		else {
		    $cmd eq 'PRIVMSG' ? '<%s> %s' : '(%s) %s';
		}
	    };
	    my $nick = do {
		if ($sender->isa('IrcIO::Client')) {
		    RunLoop->shared_loop->network(
		      (Multicast::detatch($msg->param(0)))[1])
			->current_nick;
		}
		else {
		    $msg->nick || $sender->current_nick;
		}
	    };
	    sprintf $format,$nick,$msg->param(1);
	}
    };
    
    [$is_priv ? 'priv' : $msg->param(0),$line];
}

sub log {
    my ($this,$ch_full,$log_line) = @_;
    my $vec = do {
	if ($ch_full eq 'priv') {
	    # privは自分で保存
	    $this->{priv_log};
	}
	else {
	    # privでなければChannelInfoに'recent-log'として保存。
	    my ($ch_short,$network_name) = Multicast::detach($ch_full);
	    my $ch = RunLoop->shared->
		network($network_name)->channel($ch_short);
	    if (!defined $ch) {
		return;
	    }
	    my $log_vec = $ch->remarks('recent-log');
	    if (!defined $log_vec) {
		$log_vec = [];
		$ch->remarks('recent-log',$log_vec);
	    }
	    $log_vec;
	}
    };

    my $header = Tools::DateConvert::replace(
	$this->config->header || '%H:%M'
    );
    
    # ログに追加
    # 要素は[チャンネル名,ログ行]
    push @$vec,[$ch_full,"$header $log_line"];

    # 溢れた分を消す
    if (@$vec > $this->config->line) {
	splice @$vec,0,(@$vec - $this->config->line);
    }
}

1;
