# -----------------------------------------------------------------------------
# $Id: Joined.pm,v 1.1 2003/04/05 08:45:28 admin Exp $
# -----------------------------------------------------------------------------
package Auto::Joined;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Multicast;
use IRCMessage;

sub new {
    my ($class) = @_;
    my $this = $class->SUPER::new;
    $this->{last_message_time} = 0; # 最後にこのモジュールが発言した時刻。
    $this->{table} = do {
	my %hash = map {
	    my ($ch_long,$msg) = m/^(.+?)\s+(.+)$/;
	    $ch_long => $msg;
	} $this->config->channel('all');
	\%hash;
    };
    $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

    if ($sender->isa('IrcIO::Server') &&
	defined $msg->nick &&
	$msg->nick ne RunLoop->shared->current_nick &&
	$msg->command eq 'JOIN') {

	foreach (split /,/,$msg->param(0)) {
	    my ($ch_long) = m/^([^\x07]+)/;
	    # このチャンネルに割り当てられたメッセージはあるか？
	    my $msg_for_ch = $this->{table}->{$ch_long};
	    if (defined $msg_for_ch) {
		# 発言してから1秒以上経っていれば、発言。
		if (time > $this->{last_message_time} + 1) {
		    $reply_anywhere->($msg_for_ch);
		    $this->{last_message_time} = time;
		}
	    }
	}
    }
    
    @result;
}

1;

