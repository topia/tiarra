# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# このクラスはTiarraローカルなチャンネルを管理します。
# 各クライアントに、そのクライアントが入っているTiarraローカルチャンネルを
# 註釈`tiarra-local-channels'として持たせます。
# この註釈はチャンネル名の配列です。
# -----------------------------------------------------------------------------
# 使い方:
#
# -----------------------------------------------------------------------------
package LocalChannelManager;
use strict;
use warnings;
use Carp;
use Tiarra::SharedMixin;
use NumericReply;
use base qw(Tiarra::IRC::NewMessageMixin);
our $_shared_instance;

sub _new {
    my $class = shift;
    my $this = {
	registered => {}, # {チャンネル名 => [トピック(文字列), ハンドラ(クロージャ)]}
    };
    bless $this => $class;
}

sub register {
    # Name => チャンネル名
    # Topic => トピック
    # Handler => ハンドラ; $handler->($client, $msg)のように呼ばれる。
    my ($class_or_this, %args) = @_;
    my $this = $class_or_this->_this;

    foreach my $arg (qw/Name Topic Handler/) {
	if (!defined $args{$arg}) {
	    croak "LocalChannelManager->register, Arg{Name} is undef.\n";
	}
    }
    if (ref($args{Handler}) ne 'CODE') {
	croak "LocalChannelManager->register, Arg{Handler} is not a function.\n";
    }

    if (defined $this->{registered}{$args{Name}}) {
	croak "LocalChannelManager->register, channel `$args{Name}' is already registered.\n";
    }

    $this->{registered}{$args{Name}} = [@args{'Topic', 'Handler'}];
    $this;
}

sub unregister {
    my ($class_or_this, $channel) = @_;
    my $this = $class_or_this->_this;

    delete $this->{registered}{$channel};
    $this;
}

sub registered_p {
    my ($class_or_this, $channel) = @_;
    my $this = $class_or_this->_this;

    defined $this->{registered}{$channel};
}

sub message_arrived {
    # Tiarra::IRC::Messageまたはundefを返す。
    my ($class_or_this, $msg, $sender) = @_;
    my $this = $class_or_this->_this;

    my $method = '_'.$msg->command;
    if ($this->can($method)) {
	$this->$method($msg, $sender);
    }
    else {
	$msg;
    }
}

sub _JOIN {
    my ($this, $msg, $sender) = @_;

    # チャンネル名のリストから、Tiarraローカルチャンネルを抜き取る。
    my @new_list;
    foreach my $ch_name (split m/,/, $msg->param(0)) {
	if ($this->registered_p($ch_name)) {
	    my ($topic, $handler) = @{$this->{registered}{$ch_name}};

	    # このクライアントの`tiarra-local-channels'に入っているか？
	    my $list = $sender->remark('tiarra-local-channels');
	    if (!defined $list) {
		$list = [];
		$sender->remark('tiarra-local-channels', $list);
	    }
	    if (!{map {$_ => 1} @$list}->{$ch_name}) {
		# 入っていないのでJOIN処理を行う。
		push @$list, $ch_name;

		my $local_nick = RunLoop->shared->current_nick;
		# まずJOIN
		$sender->send_message(
		    $this->construct_irc_message(
			Prefix => $sender->fullname,
			Command => 'JOIN',
			Param => $ch_name));
		# 次にRPL_TOPIC(あれば)
		if ($topic ne '') {
		    $sender->send_message(
			$this->construct_irc_message(
			    Prefix => 'Tiarra',
			    Command => RPL_TOPIC,
			    Params => [
				$local_nick,
				$ch_name,
				$topic,
			    ]));
		}
		# 次にRPL_NAMREPLY。この本人だけ。
		$sender->send_message(
		    $this->construct_irc_message(
			Prefix => 'Tiarra',
			Command => RPL_NAMREPLY,
			Params => [$local_nick,
				   '=',
				   $ch_name,
				   $local_nick]));
		# そしてRPL_ENDOFNAMES
		$sender->send_message(
		    $this->construct_irc_message(
			Prefix => 'Tiarra',
			Command => RPL_ENDOFNAMES,
			Params => [$local_nick,
				   $ch_name,
				   'End of NAMES list']));
	    }
	}
	else {
	    push @new_list, $ch_name;
	}
    }
    $msg->param(0, join(',', @new_list));
    
    $msg;
}

1;
