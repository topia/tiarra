# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# ���Υ��饹��Tiarra������ʥ����ͥ��������ޤ���
# �ƥ��饤����Ȥˡ����Υ��饤����Ȥ����äƤ���Tiarra����������ͥ��
# ���`tiarra-local-channels'�Ȥ��ƻ������ޤ���
# �������ϥ����ͥ�̾������Ǥ���
# -----------------------------------------------------------------------------
# �Ȥ���:
#
# -----------------------------------------------------------------------------
package LocalChannelManager;
use strict;
use warnings;
use Carp;
our $_shared_instance;

sub shared {
    if (!defined $_shared_instance) {
	$_shared_instance = LocalChannelManager->_new;
    }
    $_shared_instance;
}

sub _new {
    my $class = shift;
    my $this = {
	registered => {}, # {�����ͥ�̾ => [�ȥԥå�(ʸ����), �ϥ�ɥ�(��������)]}
    };
    bless $this => $class;
}

sub register {
    # Name => �����ͥ�̾
    # Topic => �ȥԥå�
    # Handler => �ϥ�ɥ�; $handler->($client, $msg)�Τ褦�˸ƤФ�롣
    my ($this, %args) = @_;

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
    my ($this, $channel) = @_;
    delete $this->{registered}{$channel};
    $this;
}

sub registered_p {
    my ($this, $channel) = @_;
    defined $this->{registered}{$channel};
}

sub message_arrived {
    # IRCMessage�ޤ���undef���֤���
    my ($this, $msg, $sender) = @_;

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

    # �����ͥ�̾�Υꥹ�Ȥ��顢Tiarra����������ͥ��ȴ����롣
    my @new_list;
    foreach my $ch_name (split m/,/, $msg->param(0)) {
	if ($this->registered_p($ch_name)) {
	    my ($topic, $handler) = @{$this->{registered}{$ch_name}};

	    # ���Υ��饤����Ȥ�`tiarra-local-channels'�����äƤ��뤫��
	    my $list = $sender->remark('tiarra-local-channels');
	    if (!defined $list) {
		$list = [];
		$sender->remark('tiarra-local-channels', $list);
	    }
	    if (!{map {$_ => 1} @$list}->{$ch_name}) {
		# ���äƤ��ʤ��Τ�JOIN������Ԥ���
		push @$list, $ch_name;

		my $local_nick = RunLoop->shared->current_nick;
		# �ޤ�JOIN
		$sender->send_message(
		    IRCMessage->new(
			Prefix => $sender->fullname,
			Command => 'JOIN',
			Param => $ch_name));
		# ����RPL_TOPIC(�����)
		if ($topic ne '') {
		    $sender->send_message(
			IRCMessage->new(
			    Prefix => 'Tiarra',
			    Command => '332',
			    Params => [
				$local_nick,
				$ch_name,
				$topic,
			    ]));
		}
		# ����RPL_NAMREPLY�������ܿͤ�����
		$sender->send_message(
		    IRCMessage->new(
			Prefix => 'Tiarra',
			Command => '353',
			Params => [$local_nick,
				   '=',
				   $ch_name,
				   $local_nick]));
		# ������RPL_ENOFNAMES
		$sender->send_message(
		    IRCMessage->new(
			Prefix => 'Tiarra',
			Command => '366',
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
