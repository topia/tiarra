# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# 掲示板のdo-not-touch-mode-of-channels (HASH*)に記述されているチャンネルのモードは弄らない。
# -----------------------------------------------------------------------------
package Channel::Mode::Set;
use strict;
use warnings;
use base qw(Module);
use BulletinBoard;
use Mask;
use Multicast;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	    $msg->command eq '366') {
	my $ch_fullname = $msg->param(1);
	my $ch_plainname = Multicast::detatch($ch_fullname);
	my $ch = $sender->channel($ch_plainname);
	if (defined $ch) {
	    my $myself = $ch->names($sender->current_nick);
	    # 自分は入っているか？(バグでもない限り常にdefined。)
	    if (defined $myself) {
		# 自分は@を持っているか？
		my $i_have_o = $myself->has_o;
		# チャンネル内に自分一人だけか？
		my $only_me = ($ch->names(undef,undef,'size') == 1);
		# MODEの変更が許されているか？
		my $allowed_mode =
		    $this->is_allowed_changing_mode($ch_fullname);
		if ($i_have_o && $only_me && $allowed_mode) {
		    $this->set_modes($ch_fullname,$ch_plainname,$sender);
		}
	    }
	}
    }
    $msg;
}

sub is_allowed_changing_mode {
    my ($this,$ch_name) = @_;
    my $untouchables = BulletinBoard->shared
	->do_not_touch_mode_of_channels;
    if (defined $untouchables) {
	if ($untouchables->{$ch_name}) {
	    return undef;
	}
    }
    1;
}

sub set_modes {
    my ($this,$ch_fullname,$ch_plainname,$sender) = @_;
    foreach ($this->config->channel('all')) {
	my ($ch_mask,$modes) = (m/^(.+?)\s+(.+)$/);
	# このチャンネルのマスクに$ch_nameはマッチするか？
	if (Mask::match($ch_mask,$ch_fullname)) {
	    foreach my $mode (split /,/,$modes) {
		$sender->send_message(
		    IRCMessage->new(
			Command => 'MODE',
			Params => [$ch_plainname,$mode]));
	    }
	}
    }
}

1;

=pod
info: チャンネルを作成した時に自動的にモードを設定するモジュール。
default: off
section: important

# 書式は<チャンネル名にマッチするマスク> <設定するモード>[,<設定するモード>,...]です。
# #IRC談話室@ircnetなら+t+nを、それ以外なら+nを設定する例。
-channel: #IRC談話室@ircnet +t
-channel: *                +n
# LimeChat 標準設定を模倣する設定例。
-channel: * +sn
=cut
