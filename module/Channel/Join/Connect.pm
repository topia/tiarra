# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2002 Topia <topia@clovery.jp>. all rights reserved.
package Channel::Join::Connect;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use RunLoop;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{servers} = {}; # servername => channellist
    # channellist : HASH
    #   shortname => チャンネルショートネーム
    #   key => channel key
    $this->_init;
}

sub _init {
    my $this = shift;
    foreach ($this->config->channel('all')) {
	s/(,)\s+/$1/g; # コンマの直後にスペースがあった場合、削除する
	my ($fullname, $key) = split(/\s+/, $_, 2);
	my @fullnames = split(/\,/, $fullname);
	my @keys = split(/,/, $key || '');
	for (my $i = 0; $i < @fullnames; $i++) {
	    my $ch_fullname = $fullnames[$i];
	    my $ch_key = $keys[$i];
	    $ch_key = '' unless defined($ch_key);
	    if (!defined($ch_fullname) || $ch_fullname eq '') {
		die "Illegal definition in Channel::Join::Connect/channel : $_\n";
	    }
	    my ($ch_shortname, $server_name) = Multicast::detach($ch_fullname);
	    push @{$this->{servers}->{$server_name}},{
		shortname => $ch_shortname,
		key => $ch_key
		};
	}
    }

    $this;
}

sub connected_to_server {
    my ($this,$server,$new_connection) = @_;
    my ($session) = $this->{servers}->{$server->network_name};
    return if !$new_connection;

    if (defined($session)) {
	Timer->new(
	    Interval => 1,
	    Repeat => 1,
	    Code => sub {
		my $timer = shift;
		if (@$session > 0) {
		    # 一度に五つずつ送り出す。
		    my $msg_per_trigger = 5;
		    my (@param_chan, @param_key);
		    for (my $i = 0; $i < @$session && $i < $msg_per_trigger; $i++) {
			if (!defined($session->[$i]->{key}) || $session->[$i]->{key} eq '') {
			    push (@param_chan, $session->[$i]->{shortname});
			    push (@param_key, '');
			} else {
			    unshift (@param_chan, $session->[$i]->{shortname});
			    unshift (@param_key, $session->[$i]->{key});
			}
		    }
		    splice @$session,0,$msg_per_trigger;
		    $server->send_message(
			IRCMessage->new(
			    Command => 'JOIN',
			    Params => [join(',', @param_chan), join(',', @param_key)]));
		}
		if (@$session == 0) {
		    delete $this->{sessions}->{$server->network_name};
		    $timer->uninstall;
		}
	    })->install;
    }
}

1;
=pod
info: サーバーに初めて接続した時、指定したチャンネルに入るモジュール。
default: off
section: important

# 書式: <チャンネル1>[,<チャンネル2>,...] [<チャンネル1のキー>,...]
#     コンマの直後のスペースは無視されます。
#
# 例:
#   「#aaaaa@ircnet」に「aaaaa」というキーで入る。
-channel: #aaaaa@ircnet aaaaa
#
#   「#aaaaa@ircnet」、「#bbbbb@ircnet:*.jp」、「#ccccc@ircnet」、「#ddddd@ircnet」の4つのチャンネルに入る。
-channel: #aaaaa@ircnet,#bbbbb@ircnet:*.jp, #ccccc@ircnet
-channel: #ddddd@ircnet
=cut
