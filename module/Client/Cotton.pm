# -----------------------------------------------------------------------------
# $Id: Cache.pm,v 1.11 2004/06/04 12:57:30 topia Exp $
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::Cotton;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;

sub PART_SHIELD_EXPIRE_TIME (){5 * 60;}

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this;
}

sub _yesno {
    my ($this, $value, $default) = @_;

    return $default || 0 if (!defined $value);
    return 0 if ($value =~ /[fn]/); # false/no
    return 1 if ($value =~ /[ty]/); # true/yes
    return 1 if ($value); # 数値判定
    return 0;
}

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client') &&
	    $this->is_cotton($io) &&
		!$this->_yesno($io->option('no-cotton'))) {
	if ($this->_yesno($this->config->use_part_shield) &&
		$type eq 'in' &&
		    $msg->command eq 'PART' &&
			Multicast::channel_p($msg->param(0)) &&
				!defined $msg->param(1)) {
	    my ($chan_short, $network_name) = Multicast::detach($msg->param(0));
	    my $network = RunLoop->shared_loop->network($network_name);
	    if (defined $network) {
		my $expire = $network->remark(__PACKAGE__.'/part-shield/expire');
		my $remark = $io->remark(__PACKAGE__.'/part-shield/'.$network_name);
		if (defined $expire &&
			$expire >= time()) {
		    if (!defined $remark ||
			    (defined $remark->{channels} &&
				 !defined $remark->{channels}->{$chan_short})) {
			$remark->{channels}->{$chan_short} = 1;
			return undef;
		    }
		} else {
		    # remove expired network info
		    $network->remark(__PACKAGE__.'/part-shield/expire', undef, 'delete');
		    $io->remark(__PACKAGE__.'/part-shield/'.$network_name, undef, 'delete');
		}
	    }
	}
    }
    return $msg;
}

sub connected_to_server {
    my ($this,$server,$new_connection) = @_;

    if (!$new_connection) {
	# reconnect
	$server->remark(__PACKAGE__.'/part-shield/expire', time() + PART_SHIELD_EXPIRE_TIME);
    }
}

sub is_cotton {
    my ($this, $client) = @_;

    return 1 if defined $client->remark('client-version') &&
	$client->remark('client-version') =~ /(Cotton|Unknown) Client/;
    return 1 if defined $client->option('client-type') &&
	$client->option('client-type') =~ /(cotton|unknown)/;
    return 0;
}

1;
=pod
info: Cotton の行うおかしな動作のいくつかを無視する
default: off

# クライアントオプションの no-cotton を指定すれば動きません。
# 該当クライアントのオプション client-type に cotton や unknown と指定するか、
# Client::GetVersion を利用してクライアントのバージョンを取得するように
# してください。

# part shield (rejoin 時に自動で行われる part の無視)を使用するか
use-part-shield: 1

=cut
