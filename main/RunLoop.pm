# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# ���Υ��饹��Tiarra�Υᥤ��롼�פ�������ޤ���
# select()��¹Ԥ��������С��䥯�饤����ȤȤ�I/O��Ԥ��ΤϤ��Υ��饹�Ǥ���
# -----------------------------------------------------------------------------
# �եå�`before-select'�ڤ�`after-select'�����Ѳ�ǽ�Ǥ���
# �����Υեå��ϡ����줾��select()�¹�ľ����ľ��˸ƤФ�ޤ���
# -----------------------------------------------------------------------------
package RunLoop;
use strict;
use warnings;
use UNIVERSAL;
use Carp;
use IO::Socket::INET;
use IO::Select;
use Configuration;
use IrcIO;
use IrcIO::Server;
use IrcIO::Client;
use Unicode::Japanese;
use Mask;
use ModuleManager;
use Multicast;
use Timer;
use ControlPort;
use Hook;
our @ISA = 'HookTarget';
use Tiarra::ShorthandConfMixin;
use Tiarra::SharedMixin qw(shared shared_loop);
use Tiarra::Utils;
use Tiarra::Resolver;
use Tiarra::TerminateManager;
our $_shared_instance;

BEGIN {
    # Time::HiRes�ϻȤ��뤫��
    eval q{
        use Time::HiRes qw(time);
    }; if ($@) {
	# �Ȥ��ʤ���
    }
}

sub _new {
    shift->new(Configuration->shared);
}

sub new {
    my ($class, $conf) = @_;
    carp 'conf is not specified!' unless defined $conf;
    # early initialization
    my $this = {
	conf => $conf,
	mod_manager => undef,
    };
    bless $this, $class;

    # update
    %$this = (
	%$this,

	# �����ѥ��쥯���������륽���åȤϾ�˼�����ɬ�פ����뤿�ᡢ�����륽���åȤ���Ͽ����Ƥ��롣
	receive_selector => new IO::Select,

	# �����ѥ��쥯���������åȤ��Ф����������٤��ǡ�����������ϸ¤��Ƥ��ơ����ξ��ˤΤ���Ͽ����ƽ���꼡��������롣
	send_selector => new IO::Select,

	# Tiarra���ꥹ�˥󥰤��ƥ��饤����Ȥ�����դ��뤿��Υ����åȡ�IO::Socket��
	tiarra_server_socket => undef,

	# ���ߤ�nick�����ƤΥ����С��ȥ��饤����Ȥδ֤����������ݤ��Ĥ�nick���ѹ�������ʤ�RunLoop���Ѱդ��롣
	current_nick => $this->_conf_general->nick,

	# ���������Ǥ��줿����ư�
	action_on_disconnected => do {
	    my $actions = {
		'part-and-join' => \&_action_part_and_join,
		'one-message' => \&_action_one_message,
		'message-for-each' => \&_action_message_for_each,
	    };
	    my $action_name = $this->_conf_networks->action_when_disconnected;
	    unless (defined $action_name) {
		$action_name = 'part-and-join';
	    }
	    my $act = $actions->{$action_name};
	    if (defined $act) {
		$act;
	    }
	    else {
		die "Unknown action specified as networks/action-when-disconnected: $action_name\n";
	    }
	},

	multi_server_mode => 1, # �ޥ�������С��⡼�ɤ����äƤ��뤫�ݤ�

	default_network => undef, # �ǥե���ȤΥͥåȥ��̾
	networks => {}, # �ͥåȥ��̾ �� IrcIO::Server
	disconnected_networks => {}, # ���Ǥ��줿�ͥåȥ����
	terminated_networks => {}, # ��λ�����ͥåȥ����
	clients => [], # ��³����Ƥ������ƤΥ��饤����� IrcIO::Client

	timers => [], # ���󥹥ȡ��뤵��Ƥ������Ƥ�Timer
	external_sockets => [], # ���󥹥ȡ��뤵��Ƥ������Ƥ�ExternalSocket

	conf_reloaded_hook => undef, # ���β��ǥ��󥹥ȡ��뤹��եå�

	terminating => 0, # ���ΤȤ��Ͻ�λ�����档
       );

    $this->{conf_reloaded_hook} = Configuration::Hook->new(
	sub {
	    # �ޥ�������С��⡼�ɤ�On/Off���Ѥ�ä�����
	    my $old = $this->{multi_server_mode} ? 1 : 0;
	    my $new = $this->_conf_networks->multi_server_mode ? 1 : 0;
	    if ($old != $new) {
		# �Ѥ�ä�
		$this->_multi_server_mode_changed;
	    }
	},
       )->install(undef, $this->_conf);

    $this;
}

sub DESTROY {
    my $this = shift;
    if (defined $this->{conf_reloaded_hook}) {
	$this->{conf_reloaded_hook}->uninstall;
    }
}

sub network {
    my ($class_or_this,$network_name) = @_;
    my $this = $class_or_this->_this;
    my $network;
    foreach my $genre (qw(networks disconnected_networks terminated_networks)) {
	$network = $this->{$genre}->{$network_name};
	next unless defined $network;
	return wantarray ? ($network, $genre) : $network;
    }
    return wantarray ? () : undef;
}

Tiarra::Utils->define_attr_getter(1, qw(default_network networks clients),
				  [qw(multi_server_mode_p multi_server_mode)],
				  [qw(_mod_manager mod_manager)]);

# ���饤����Ȥ��鸫�������ߤ�nick��
# ����nick�ϼºݤ˻Ȥ��Ƥ���nick�ȤϰۤʤäƤ����礬���롣
# ���ʤ������˾��nick�����˻Ȥ��Ƥ������Ǥ��롣
Tiarra::Utils->define_attr_getter(1, qw(current_nick));

sub networks_list { values %{shift->networks}; }
sub clients_list { @{shift->clients}; }

sub channel {
    # $ch_long: �ͥåȥ��̾�����դ������ͥ�̾
    # ���դ��ä���ChannelInfo�����դ���ʤ����undef���֤���
    my ($class_or_this,$ch_long) = @_;
    my $this = $class_or_this->_this;

    my ($ch_short,$net_name) = Multicast::detach($ch_long);
    my $network = $this->{networks}->{$net_name};
    if (!defined $network) {
	return undef;
    }

    $network->channel($ch_short);
}

sub set_current_nick {
    my ($class_or_this,$new_nick) = @_;
    my $this = $class_or_this->_this;
    $this->{current_nick} = $new_nick;
    $this->call_hooks('set-current-nick');
}

sub change_nick {
    my ($class_or_this,$new_nick) = @_;
    my $this = $class_or_this->_this;

    foreach my $io (values %{$this->{networks}}) {
	$io->send_message(
	    new IRCMessage(
		Command => 'NICK',
		Param => $new_nick));
    }
}

sub find_io_with_socket {
    my ($class_or_this,$sock) = @_;
    my $this = $class_or_this->_this;
    # networks��clients���椫����ꤵ�줿�����åȤ����IrcIO��õ���ޤ���
    # ���դ���ʤ����undef���֤��ޤ���
    foreach my $io (values %{$this->{networks}}) {
	return $io if defined $io->sock && $io->sock == $sock;
    }
    foreach my $io (@{$this->{clients}}) {
	return $io if defined $io->sock && $io->sock == $sock;
    }
    undef;
}

sub _runloop { shift->_this; }

sub sysmsg_prefix {
    my ($class_or_this,$purpose,$category) = @_;
    my $this = $class_or_this->_this;
    $category = (caller)[0] . (defined $category ? "::$category" : '');
    # $purpose �ϡ����δؿ������� prefix �򲿤˻Ȥ����򼨤���
    #     ���ޤΤȤ��� system(NumericReply �ʤ�)/priv/channel
    # $category �ϡ���ޤ��ʥ��ƥ��ꡣ
    #     ���ޤΤȤ��� log/system/notify �����뤬��
    #     ���Τʻ��ͤϤޤ��ʤ���

    if (Mask::match_array([
	$this->_conf_general->sysmsg_prefix_use_masks('block')->
	    get($purpose, 'all')], $category)) {
	$this->_conf_general->sysmsg_prefix;
    } else {
	undef
    }
}

sub _multi_server_mode_changed {
    my $this = shift;
    # ��ö���ƤΥ����ͥ�ˤĤ���PART��ȯ�Ԥ����塢
    # �⡼�ɤ��Ѥ���³��ͥåȥ���򹹿�����NICK��JOIN��ȯ�Ԥ��롣
    my $new = !$this->{multi_server_mode};

    foreach my $string (
	'Multi server mode *'.($new ? 'enabled' : 'disabled').'*',
	q{It looks as if you would part all channels, but it's just an illusion.}) {
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Prefix => $this->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [$this->current_nick, $string]));
    }

    my $iterate = sub {
	my $func = shift;
	foreach my $network ($this->networks_list) {
	    foreach my $ch ($network->channels_list) {
		foreach my $client ($this->clients_list) {
		    $func->($network, $ch, $client);
		}
	    }
	}
    };

    $iterate->(
	sub {
	    my ($network, $ch, $client) = @_;
	    $client->send_message(
		IRCMessage->new(
		    Prefix => $client->fullname,
		    Command => 'PART',
		    Params => [
			do {
			    if ($new) {
				# ����ޤǤϥͥåȥ��̾���դ��Ƥ��ʤ��ä���
				$ch->name;
			    }
			    else {
				scalar Multicast::attach(
				    $ch->name, $network->network_name);
			    }
			},
			'[Caused by Tiarra] Clients have to part all channels.',
		       ],
		   )
	       );
	}
       );
    $this->{multi_server_mode} = $new;
    $this->update_networks;
    my $global_nick = (($this->networks_list)[0])->current_nick;
    if ($global_nick ne $this->current_nick) {
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Command => 'NICK',
		Param => $global_nick,
		Remarks => {'fill-prefix-when-sending-to-client' => 1
			   }));

	$this->set_current_nick($global_nick);
    }
    foreach my $client ($this->clients_list) {
	$client->inform_joinning_channels;
    }
}

sub _update_send_selector {
    my $this = shift;
    # ��������ɬ�פΤ���IrcIO������ȴ���Ф������Υ����åȤ��������쥯������Ͽ���롣

    #my $add_or_remove = sub {
    #	my $io = shift;
    #	my $action = ($io->need_to_send ? 'add' : 'remove');
    #	$this->{send_selector}->$action($io->sock);
    #};

    #foreach my $io (values %{$this->{networks}}) {
    #	$add_or_remove->($io);
    #}
    #foreach my $io (@{$this->{clients}}) {
    #	$add_or_remove->($io);
    #}

    # �ɤ��⤳��ư���������̵���˺����Ѥ��ʤ��Ƥ��ɤ��褦�ʵ������롣
    my $sel = $this->{send_selector} = IO::Select->new;
    foreach my $io (values %{$this->{networks}}) {
	if ($io->need_to_send) {
	    $sel->add($io->sock);
	}
    }
    foreach my $io (@{$this->{clients}}) {
	if ($io->need_to_send) {
	    $sel->add($io->sock);
	}
    }
    foreach my $esock (@{$this->{external_sockets}}) {
	if ($esock->want_to_write) {
	    $sel->add($esock->sock);
	}
    }
}

sub _cleanup_closed_link {
    # networks��clients���椫�����Ǥ��줿��󥯤�õ����
    # ���Υ����åȤ򥻥쥯�����鳰����
    # networks�ʤ饯�饤����Ȥ�����٤����Τ򤷡�����³���륿���ޡ��򥤥󥹥ȡ��뤹�롣
    my $this = shift;

    my %networks_closed = ();
    while (my ($network_name,$io) = each %{$this->{networks}}) {
	$networks_closed{$network_name} = $io unless $io->connected;
    }
    my $do_update_networks_after = 0;
    while (my ($network_name,$io) = each %networks_closed) {
	# ���쥯�����鳰����
	$this->unregister_receive_socket($io->sock);
	# networks���������롣
	delete $this->{networks}->{$network_name};
	if (!defined $io->state || $io->state eq 'reconnecting') {
	    $this->{disconnected_networks}->{$network_name} = $io;
	    $do_update_networks_after = 3;
	} elsif ($io->state eq 'terminating') {
	    $this->{terminated_networks}->{$network_name} = $io;
	    $do_update_networks_after = 1;
	} elsif ($io->state eq 'finalizing') {
	    # remove
	} else {
	    $this->notify_warn('Unknown network state('.$io->state.') on '.$network_name);
	}
    }
    if ($do_update_networks_after) {
	Timer->new(
	    After => $do_update_networks_after,
	    Code => sub {
		$this->update_networks;
	    },
	)->install($this);
    }

    for (my $i = 0; $i < @{$this->{clients}}; $i++) {
	my $io = $this->{clients}->[$i];
	unless ($io->connected) {
	    ::printmsg("Connection with ".$io->fullname." has been closed.");
	    $this->unregister_receive_socket($io->sock);
	    splice @{$this->{clients}},$i,1;
	    $i--;
	}
    }
}

sub _action_part_and_join {
    # $event: 'connected' �㤷���� 'disconnected'
    # ���ΤȤ������Υ᥽�åɤ�conf����κ���ˤ�����ǻ��ˤ�ή�Ѥ���Ƥ��롣
    my ($this,$network,$event) = @_;
    my $network_name = $network->network_name;
    if ($event eq 'connected') {
	$this->_rejoin_all_channels($network);
    }
    elsif ($event eq 'disconnected') {
	foreach my $client (@{$this->clients}) {
	    foreach my $ch (values %{$network->channels}) {
		$client->send_message(
		    IRCMessage->new(
			Prefix => $client->fullname,
			Command => 'PART',
			Params => [Multicast::attach_for_client($ch->name,$network_name),
				   $network->host." closed the connection."]));
	    }
	}
    }
}
sub _action_one_message {
    my ($this,$network,$event) = @_;
    my $network_name = $network->network_name;
    if ($event eq 'connected') {
	$this->_rejoin_all_channels($network);
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Prefix => $this->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [$this->current_nick,
			   '*** The connection has been revived between '.$network->network_name.'.']));
    }
    elsif ($event eq 'disconnected') {
	$this->broadcast_to_clients(
	    IRCMessage->new(
		Prefix => $this->sysmsg_prefix(qw(priv system)),
		Command => 'NOTICE',
		Params => [$this->current_nick,
			   '*** The connection has been broken between '.$network->network_name.'.']));
    }
}
sub _action_message_for_each {
    my ($this,$network,$event) = @_;
    my $network_name = $network->network_name;
    if ($event eq 'connected') {
	$this->_rejoin_all_channels($network);

	my $msg = IRCMessage->new(
	    Prefix => $this->sysmsg_prefix(qw(channel system)),
	    Command => 'NOTICE',
	    Params => ['', # �����ͥ�̾�ϸ�����ꡣ
		       '*** The connection has been revived between '.$network->network_name.'.']);
	foreach my $ch (values %{$network->channels}) {
	    $msg->param(0,Multicast::attach_for_client($ch->name,$network_name));
	    $this->broadcast_to_clients($msg);
	}
    }
    elsif ($event eq 'disconnected') {
	my $msg = IRCMessage->new(
	    Prefix => $this->sysmsg_prefix(qw(channel system)),
	    Command => 'NOTICE',
	    Params => ['', # �����ͥ�̾�ϸ�����ꡣ
		       '*** The connection has been broken between '.$network->network_name.'.']);
	foreach my $ch (values %{$network->channels}) {
	    $msg->param(0,Multicast::attach_for_client($ch->name,$network_name));
	    $this->broadcast_to_clients($msg);
	}
    }
}
sub _rejoin_all_channels {
    my ($this,$network) = @_;
    # network���������Ƥ������ƤΥ����ͥ��JOIN���롣
    # ���⤽��JOIN���Ƥ��ʤ������ͥ���̾�IrcIO::Server�ϵ������Ƥ��ʤ�����
    # �����С��������Ǥ��줿���������㳰�Ǥ��롣
    # �������kicked-out���դ����Ƥ�������ͥ�ˤ�JOIN���ʤ���
    my @ch_with_key; # �ѥ���ɤ���ä������ͥ���������Ǥ�["�����ͥ�̾","�ѥ����"]
    my @ch_without_key; # �ѥ���ɤ�����ʤ������ͥ���������Ǥ�"�����ͥ�̾"
    foreach my $ch (values %{$network->channels}) {
	next if $ch->remarks('kicked-out');

	my $password = $ch->parameters('k');
	if (defined $password && $password ne '') {
	    push @ch_with_key,[$ch->name,$password];
	}
	else {
	    push @ch_without_key,$ch->name;
	}
    }
    # JOIN�¹�
    my ($buf_ch,$buf_key) = ('','');
    my $buf_flush = sub {
	return if ($buf_ch eq '');
	my $params = do {
	    if ($buf_key eq '') {
		[$buf_ch];
	    }
	    else {
		[$buf_ch,$buf_key];
	    }
	};
	$network->send_message(
	    IRCMessage->new(
		Command => 'JOIN',
		Params => $params));
	$buf_ch = $buf_key = '';
    };
    my $buf_put = sub {
	my ($ch,$key) = @_;
	$buf_ch .= ($buf_ch eq '' ? $ch : ",$ch");
	$buf_key .= ($buf_key eq '' ? $key : ",$key") if defined $key;
	if (length($buf_ch) + length($buf_key) > 400) {
	    # 400�Х��Ȥ�ۤ����鼫ư�ǥե�å��夹�롣
	    $buf_flush->();
	}
    };
    # �ѥ�����դ��Υ����ͥ��JOIN
    foreach (@ch_with_key) {
	$buf_put->($_->[0],$_->[1]);
    }
    $buf_flush->();
    # �ѥ����̵���Υ����ͥ��JOIN
    foreach (@ch_without_key) {
	$buf_put->($_);
    }
    $buf_flush->();
}

sub update_networks {
    my $this = shift;
    # networks/name���ɤߡ�������ˤޤ���³���Ƥ��ʤ��ͥåȥ��������Ф������³����
    # ��³��Υͥåȥ���Ǵ���networks/name����󤵤�Ƥ��ʤ���Τ�����Ф�������Ǥ��롣
    my @net_names = $this->_conf_networks->name('all');
    my $do_update_networks_after = 0; # �ÿ�
    my $do_cleanup_closed_links_after = 0;
    my $host_tried = {}; # {��³���ߤ��ۥ���̾ => 1}

    $this->{default_network} = $this->_conf_networks->default;

    # �ޥ�������С��⡼�ɤǤʤ���С�@net_names�����Ǥϰ�Ĥ˸¤���٤���
    # �����Ǥʤ���зٹ��Ф�����Ƭ�Τ�Τ�����Ĥ��Ƹ�ϼΤƤ롣
    if (!$this->{multi_server_mode}) {
	if (@net_names > 1) {
	    $this->notify_warn(
		"In single server mode, Tiarra will connect to just a one network; `".
		    $net_names[0]."'");
	    @net_names = $net_names[0];
	}
	if (@net_names > 0) {
	    $this->{default_network} = $net_names[0];
	}
    }

    my ($net_conf, $network, $genre);
    foreach my $net_name (@net_names) {
	$net_conf = $this->_conf->get($net_name);

	($network, $genre) = $this->network($net_name);
	eval {
	    if (!defined $genre || !defined $network) {
		# �������ͥåȥ��
		if ($host_tried->{$net_conf->host}) {
		    $do_update_networks_after = 15;
		    $network = undef;
		}
		else {
		    $host_tried->{$net_conf->host} = 1;

		    $network = IrcIO::Server->new($this, $net_name);
		    $this->{networks}->{$net_name} = $network; # networks����Ͽ
		}
	    }
	    elsif ($genre eq 'networks') {
		# ������³����Ƥ��롣
		# ���Υ����С��ˤĤ��Ƥ����꤬�Ѥ�äƤ����顢��ö��³���ڤ롣
		if (!$net_conf->equals($network->config)) {
		    #$network->disconnect;
		    #$do_cleanup_closed_links_after = 1;
		    $network->state('reconnecting');
		    $network->quit(
			$this->_conf_messages->quit->netconf_changed_reconnect);
		}
	    }
	    elsif ($genre eq 'terminated_networks') {
		# ��λ���Ƥ���
		# ���Υ����С��ˤĤ��Ƥ����꤬�Ѥ�äƤ����顢��³���롣
		if (!$net_conf->equals($network->config)) {
		    $this->reconnect_server($net_name);
		}
	    }
	    elsif ($genre eq 'disconnected_networks') {
		# ���Ǥ���Ƥ���
		$this->reconnect_server($net_name);
	    }
	}; if ($@) {
	    if ($@ =~ /^[Cc]ouldn't connect to /i) {
		::printmsg($@);
	    } else {
		$this->notify_error($@);
	    }
	    # �����ޡ����ľ����
	    $do_update_networks_after = 3;
	}
    }

    if ($do_cleanup_closed_links_after) {
	$this->_cleanup_closed_link;
    }

    my @nets_to_disconnect;
    my @nets_to_forget;
    my $is_there_in_net_names = sub {
	my $network_name = shift;
	# ���Υͥåȥ����@net_names�����󤵤�Ƥ��뤫��
	foreach my $enumerated_net (@net_names) {
	    return 1 if $network_name eq $enumerated_net;
	}
	return 0;
    };
    # networks�������פʥͥåȥ������
    while (my ($net_name,$server) = each %{$this->{networks}}) {
	# ���äƤ��ʤ��ä���selector���鳰�������Ǥ��롣
	unless ($is_there_in_net_names->($net_name)) {
	    push @nets_to_disconnect,$net_name;
	}
    }
    foreach my $net_name (@nets_to_disconnect) {
	my $server = $this->{networks}->{$net_name};
	$server->state('finalizing');
	$server->quit(
	    $this->_conf_messages->quit->netconf_changed_disconnect);
    }
    # ���פʥͥåȥ������
    foreach my $genre (qw(disconnected_networks terminated_networks)) {
	while (my ($net_name,$server) = each %{$this->{$genre}}) {
	    # ���äƤ��ʤ��ä���˺��롣
	    unless ($is_there_in_net_names->($net_name)) {
		if (!$server->connected) {
		    push @nets_to_forget,$net_name;
		} else {
		    $do_update_networks_after ||= 3;
		}
	    }
	}
	foreach (@nets_to_forget) {
	    delete $this->{$genre}->{$_};
	}
    }

    if ($do_update_networks_after) {
	Timer->new(
	    After => $do_update_networks_after,
	    Code => sub {
		$this->update_networks;
	    },
	)->install($this);
    }
}

sub terminate_server {
    my ($class_or_this,$network, $msg) = @_;
    my $this = $class_or_this->_this;

    $network->state('terminating');
    $network->quit($msg);
}

sub reconnect_server {
    # terminate/disconnect(�����Ф���)���줿�����Ф���³���ʤ�����
    my ($class_or_this,$network_name) = @_;
    my $this = $class_or_this->_this;
    my ($network, $genre) = $this->network($network_name);

    if (defined $genre && $genre ne 'networks') {
	$network->reload_config;
	$network->connect;
	# ���Υ����뤫��networks�ذܤ���
	$this->{networks}->{$network_name} = $network;
	delete $this->{$genre}->{$network_name};
    }
}

sub disconnect_server {
    # ���ꤵ�줿�����С��Ȥ���³���ڤ롣
    # fd�δƻ����Ƥ��ޤ��Τǡ����θ�IrcIO::Server��receive�Ϥ⤦�ƤФ�ʤ�������ա�
    # $server: IrcIO::Server
    my ($class_or_this,$server) = @_;
    my $this = $class_or_this;
    $server->disconnect;
    delete $this->{networks}->{$server->network_name};
}

sub close_client {
    # ���ꤷ�����饤����ȤȤ���³���ڤ롣
    # $client: IrcIO::Client
    my ($class_or_this, $client, $message) = @_;
    my $this = $class_or_this->_this;
    $client->send_message(
	IRCMessage->new(
	    Command => 'ERROR',
	    Param => 'Closing Link: ['.$client->fullname_from_client.
		'] ('.$message.')',
	    Remarks => {'send-error-as-is-to-client' => 1},
	   ));
    $client->disconnect_after_writing;
}

sub reconnected_server {
    my ($class_or_this,$network) = @_;
    my $this = $class_or_this->_this;
    # ����³���ä����ν���
    $this->{action_on_disconnected}->($this,$network,'connected');
}

sub disconnected_server {
    my ($class_or_this,$network) = @_;
    my $this = $class_or_this->_this;
    $this->{action_on_disconnected}->($this,$network,'disconnected');
}

sub install_socket {
    my ($this,$esock) = @_;
    if (!defined $esock) {
	croak "RunLoop->install_socket, Arg[1] was undef.\n";
    }

    push @{$this->{external_sockets}},$esock;
    $this->register_receive_socket($esock->sock); # �������쥯������Ͽ
    undef;
}

sub uninstall_socket {
    my ($this,$esock) = @_;
    if (!defined $esock) {
	croak "RunLoop->uninstall_socket, Arg[1] was undef.\n";
    }

    for (my $i = 0; $i < @{$this->{external_sockets}}; $i++) {
	if ($this->{external_sockets}->[$i] == $esock) {
	    splice @{$this->{external_sockets}},$i,1;
	    $this->unregister_receive_socket($esock->sock); # �������쥯��������Ͽ���
	    $i--;
	}
    }
    $this;
}

sub register_receive_socket {
    # ���� API �Ǥ�����������Ȥ��Ȥ��� ExternalSocket ����Ѥ��Ƥ���������
    shift->{receive_selector}->add(@_);
}

sub unregister_receive_socket {
    # ���� API �Ǥ�����������Ȥ��Ȥ��� ExternalSocket ����Ѥ��Ƥ���������
    shift->{receive_selector}->remove(@_);
}

sub find_esock_with_socket {
    my ($this,$sock) = @_;
    foreach my $esock (@{$this->{external_sockets}}) {
	if ($esock->sock == $sock) {
	    return $esock;
	}
    }
    undef;
}

sub install_timer {
    my ($this,$timer) = @_;
    push @{$this->{timers}},$timer;
    $this;
}

sub uninstall_timer {
    my ($this,$timer) = @_;
    for (my $i = 0; $i < scalar(@{$this->{timers}}); $i++) {
	if ($this->{timers}->[$i] == $timer) {
	    splice @{$this->{timers}},$i,1;
	    $i--;
	}
    }
    $this;
}

sub get_earliest_timer {
    # ��Ͽ����Ƥ�����ǺǤⵯư���֤��ᤤ�����ޡ����֤���
    # �����ޡ�����Ĥ�̵�����undef���֤���
    my $this = shift;
    return undef if (scalar(@{$this->{timers}}) == 0);

    my $eariest = $this->{timers}->[0];
    foreach my $timer (@{$this->{timers}}) {
	if ($timer->time_to_fire < $eariest->time_to_fire) {
	    $eariest = $timer;
	}
    }
    return $eariest;
}

sub _execute_all_timers_to_fire {
    my $this = shift;

    # execute���٤������ޡ��򽸤��
    my @timers_to_execute = ();
    foreach my $timer (@{$this->{timers}}) {
	push @timers_to_execute,$timer if $timer->time_to_fire <= time;
    }

    # �¹�
    foreach my $timer (@timers_to_execute) {
	$timer->execute;
    }
}

sub run {
    my $this = shift->_this;
    my $conf_general = $this->_conf_general;

    # �ޥ�������С��⡼��
    $this->{multi_server_mode} =
	$this->_conf_networks->multi_server_mode;

    # FIXME: only shared
    $this->{mod_manager} =
	ModuleManager->shared($this);

    # �ޤ���tiarra-port��listen���륽���åȤ��롣
    # ��ά����Ƥ�����listen���ʤ���
    # �����ͤ����ͤǤʤ��ä���die��
    my $tiarra_port = $conf_general->tiarra_port;
    if (defined $tiarra_port) {
	if ($tiarra_port !~ /^\d+/) {
	    die "general/tiarra-port must be integer. '$tiarra_port' is invalid.\n";
	}

	# v4��v6�β����Ȥ�����
	my @serversocket_args = (
	    LocalPort => $tiarra_port,
	    Proto => 'tcp',
	    Reuse => 1,
	    Listen => 0);
	my $ip_version = $conf_general->tiarra_ip_version || 'v4';
	my $tiarra_server_socket = do {
	    if ($ip_version eq 'v4') {
		my $bind_addr = $conf_general->tiarra_ipv4_bind_addr;
		my @args = do {
		    if (defined $bind_addr) {
			@serversocket_args,LocalAddr => $bind_addr;
		    }
		    else {
			@serversocket_args;
		    }
		};
		IO::Socket::INET->new(@args);
	    }
	    elsif ($ip_version eq 'v6') {
		if (!&::ipv6_enabled) {
		    ::printmsg("*** IPv6 support is not enabled ***");
		    ::printmsg("Set general/tiarra-ip-version to 'v4' or install Socket6.pm if possible.\n");
		    die;
		}
		my $bind_addr = $conf_general->tiarra_ipv6_bind_addr;
		my @args = do {
		    if (defined $bind_addr) {
			@serversocket_args,LocalAddr => $bind_addr;
		    }
		    else {
			@serversocket_args;
		    }
		};
		IO::Socket::INET6->new(@args);
	    }
	    else {
		die "Unknown ip-version '$ip_version' specified as general/tiarra-ip-version.\n";
	    }
	};
	if (defined $tiarra_server_socket) {
	    $tiarra_server_socket->autoflush(1);
	    $this->{tiarra_server_socket} = $tiarra_server_socket;
	    $this->register_receive_socket($tiarra_server_socket); # ���쥯������Ͽ��
	    main::printmsg("Tiarra started listening ${tiarra_port}/tcp. (IP$ip_version)");
	}
	else {
	    # �����åȺ��ʤ��ä���
	    die "Couldn't make server socket to listen ${tiarra_port}/tcp. (IP$ip_version)\n";
	}
    }

    # ������³
    $this->update_networks;

    # 3ʬ������Ƥλ���PING�����륿���ޡ��򥤥󥹥ȡ��롣
    # �����tcp��³�����Ǥ˵��դ��ʤ��������뤿�ᡣ
    # ������PONG�ϼΤƤ롣���Τ����PONG�˴������󥿤򥤥󥯥���Ȥ��롣
    # PONG�˴������󥿤�IrcIO::Server��remark�ǡ�������'pong-drop-counter'
    Timer->new(
	Interval => 3 * 60,
	Code => sub {
	    foreach my $network (values %{$this->{networks}}) {
		$network->send_message(
		    IRCMessage->new(
			Command => 'PING',
			Param => $network->server_hostname));

		my $cntr = $network->remark('pong-drop-counter');
		if (defined $cntr) {
		    $cntr++;
		}
		else {
		    $cntr = 1;
		}
		$network->remark('pong-drop-counter',$cntr);
	    }
	},
	Repeat => 1,
    )->install;

    # control-socket-name�����ꤵ��Ƥ����顢ControlPort�򳫤���
    if ($conf_general->control_socket_name) {
	eval {
	    ControlPort->new($conf_general->control_socket_name);
	}; if ($@) {
	    ::printmsg($@);
	}
    }

    my $zerotime = {
	limit => 300,
	minimum_to_reset => 2,
	interval => 10,

	count => 0,
	last_warned => 0,
    };
    my $zerotime_warn = sub {
	my $elapsed = shift;

	if ($elapsed == 0) {
	    $zerotime->{count}++;
	    if ($zerotime->{count} >= $zerotime->{limit}) {
		$zerotime->{count} = 0;

		if ($zerotime->{last_warned} + $zerotime->{interval} < CORE::time) {
		    $zerotime->{last_warned} = CORE::time;

		    $this->notify_warn("Tiarra seems to be slowing down your system!");
		}
	    }
	}
	elsif ($elapsed > $zerotime->{minimum_to_reset}) {
	    $zerotime->{count} = 0;
	}
    };

    while (1) {
	# ������ή��
	#
	# �񤭤��߲�ǽ�ʥ����åȤ򽸤�ơ�ɬ�פ�����н񤭹��ࡣ
	# �����ɤ߹��߲�ǽ�ʥ����åȤ򽸤�ơ�(�ɤ�ɬ�פϾ�ˤ���Τ�)�ɤࡣ
	# �ɤ�������̾�IRCMessage�������֤äƤ���Τǡ�
	# ɬ�פ����ƤΥץ饰����˽��֤��̤���(�ץ饰����ϥե��륿���Ȥ��ƹͤ��롣)
	# ���줬�����С������ɤ����å��������ä��ʤ顢�ץ饰������̤����塢��³����Ƥ������ƤΥ��饤����Ȥˤ����ž�����롣
	# ���饤����Ȥ���Ĥ���³����Ƥ��ʤ���С�����IRCMessage���ϼΤƤ롣
	# ���饤����Ȥ����ɤ����å��������ä��ʤ顢�ץ饰������̤����塢�Ϥ��٤������С���ž�����롣
	#
	# select�ˤ����륿���ॢ���Ȥϼ��Τ褦�ˤ��롣
	# (���ʤϲ���������Ͽ����Ƥ���Ȼפ���)�����ޡ�����Ĥ���Ͽ����Ƥ��ʤ���С������ॢ���Ȥ�undef�Ǥ��롣���ʤ�������ॢ���Ȥ��ʤ���
	# �����ޡ�����ĤǤ���Ͽ����Ƥ������ϡ����ƤΥ����ޡ�����ǺǤ�ȯư���֤��ᤤ��Τ�Ĵ�١�
	# ���줬ȯư����ޤǤλ��֤�select�Υ����ॢ���Ȼ��֤Ȥ��롣
	
	# select���եå���Ƥ�
	$this->call_hooks('before-select');

	# �եå���ǥ����ޡ���install/ȯư�����ѹ��򤷤�����������
	# �����ॢ���Ȥη׻���before-select�եå��μ¹Ը�ˤ��롣
	my $timeout = undef;
	my $eariest_timer = $this->get_earliest_timer;
	if (defined $eariest_timer) {
	    $timeout = $eariest_timer->time_to_fire - time;
	}
	if ($timeout < 0) {
	    $timeout = 0;
	}

	# �񤭹���٤��ǡ��������륽���åȤ�����send_selector����Ͽ���롣�����Ǥʤ������åȤϽ�����
	$this->_update_send_selector;
	
	# select�¹�
	my $time_before_select = CORE::time;
	my ($readable_socks,$writable_socks) =
	    IO::Select->select($this->{receive_selector},$this->{send_selector},undef,$timeout);
	$zerotime_warn->(CORE::time - $time_before_select);
	# select��եå���Ƥ�
	$this->call_hooks('after-select');

	foreach my $sock ($this->{receive_selector}->can_read(0)) {
	    if (defined $this->{tiarra_server_socket} &&
		$sock == $this->{tiarra_server_socket}) {

		# ���饤����Ȥ���ο�������³
		my $new_sock = $sock->accept;
		if (defined $new_sock) {
		    if (!$this->{terminating}) {
			eval {
			    my $client = new IrcIO::Client($this, $new_sock);
			    push @{$this->{clients}},$client;
			}; if ($@) {
			    $this->notify_msg($@);
			}
		    } else {
			$new_sock->close;
		    }
		}
	    }
	    elsif (my $io = $this->find_io_with_socket($sock)) {
		eval {
		    $io->receive;

		    while (1) {
			my $msg = eval {
			    $io->pop_queue;
			}; if ($@) {
			    if (ref($@) && UNIVERSAL::isa($@,'QueueIsEmptyException')) {
				last;
			    }
			    else {
				::printmsg($@);
				last;
			    }
			}

			if (!defined $msg) {
			    next;
			}

			if ($io->isa("IrcIO::Server")) {
			    # ���Υ�å�������PONG�Ǥ����pong-drop-counter�򸫤롣
			    if ($msg->command eq 'PONG') {
				my $cntr = $io->remark('pong-drop-counter');
				if (defined $cntr && $cntr > 0) {
				    # ����PONG�ϼΤƤ롣
				    $cntr--;
				    $io->remark('pong-drop-counter',$cntr);
				    next;
				}
			    }

			    # ��å�������Multicast�Υե��륿���̤���
			    my @received_messages =
				Multicast::from_server_to_client($msg,$io);
			    # �⥸�塼����̤���
			    my $filtered_messages = $this->_apply_filters(\@received_messages,$io);
			    # ���󥰥륵���С��⡼�ɤʤ顢�ͥåȥ��̾���곰����
			    if (!$this->{multi_server_mode}) {
				@$filtered_messages = map {
				    Multicast::detach_network_name($_, $io);
				} @$filtered_messages;
			    }
			    # ���do-not-send-to-clients => 1���դ��Ƥ��ʤ���å�������ƥ��饤����Ȥ����롣
			    $this->broadcast_to_clients(
				grep {
				    !($_->remark('do-not-send-to-clients'));
				} @$filtered_messages);
			}
			else {
			    # ���󥰥륵���С��⡼�ɤʤ顢��å�������Multicast�Υե��륿���̤���
			    my @received_messages =
				(!$this->{multi_server_mode}) ? Multicast::from_server_to_client($msg,$this->networks_list) : $msg;

			    # �⥸�塼����̤���
			    my $filtered_messages = $this->_apply_filters(\@received_messages,$io);
			    # �оݤȤʤ뻪�����롣
			    # NOTICE�ڤ�PRIVMSG���������֤äƤ��ʤ��Τǡ�Ʊ���ˤ���ʳ��Υ��饤����Ȥ�ž�����롣
			    # ���do-not-send-to-servers => 1���դ��Ƥ����å������Ϥ������˴����롣
			    foreach my $msg (@$filtered_messages) {
				if ($msg->remark('do-not-send-to-servers')) {
				    next;
				}

				my $cmd = $msg->command;
				if ($cmd eq 'PRIVMSG' || $cmd eq 'NOTICE') {
				    my $new_msg = undef; # ������ɬ�פˤʤä����롣
				    foreach my $client (@{$this->{clients}}) {
					if ($client != $io) {
					    unless (defined $new_msg) {
						# �ޤ���äƤʤ��ä�
						$new_msg = $msg->clone;
						$new_msg->prefix($io->fullname);
						# ���󥰥륵���С��⡼�ɤʤ顢�ͥåȥ��̾���곰����
						if (!$this->{multi_server_mode}) {
						    Multicast::detach_network_name($new_msg,$this->networks_list);
						}

					    }
					    $client->send_message($new_msg);
					}
				    }
				}

				Multicast::from_client_to_server($msg,$io);
			    }
			}
		    }
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	    elsif (my $esock = $this->find_esock_with_socket($sock)) {
		eval {
		    $esock->read;
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	}
	
	foreach my $sock ($this->{send_selector}->can_write(0)) {
	    if (my $io = $this->find_io_with_socket($sock)) {
		next unless $io->need_to_send;

		eval {
		    $io->send;
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	    elsif (my $esock = $this->find_esock_with_socket($sock)) {
		next unless $esock->want_to_write;

		eval {
		    $esock->write;
		}; if ($@) {
		    $this->notify_error($@);
		}
	    }
	}

	# ���Ǥ��줿�����åȤ�õ���ơ�����٤�������Ԥʤ���
	$this->_cleanup_closed_link;
	
	# ȯư���٤����ƤΥ����ޡ���ȯư������
	$this->_execute_all_timers_to_fire;

	# ��λ������ǥ����Ф⥯�饤����Ȥ⤤�ʤ��ʤ�Х롼�׽�λ��
	if ($this->{terminating}) {
	    if ((scalar $this->networks_list <= 0) &&
		    (scalar $this->clients_list <= 0)
		   ) {
		last;
	    } else {
		++$this->{terminating};
		if ($this->{terminating} >= 400) {
		    # quit loop �Ǥ���ʤ˲��Ȥϻפ��ʤ���
		    $this->notify_error(
			"very long terminating loop!".
			    "(".$this->{terminating}." count(s))\n".
				"maybe something is wrong; exit force...");
		    last;
		}
	    }
	}
    }

    # ��λ����
    if (defined $this->{tiarra_server_socket}) {
	$this->{tiarra_server_socket}->close;
	$this->unregister_receive_socket($this->{tiarra_server_socket});
    }
    $this->_mod_manager->terminate;
    Tiarra::TerminateManager->shared->terminate('main');
}

sub terminate {
    my ($class_or_this, $message) = @_;
    my $this = $class_or_this->_this;

    $this->{terminating} = 1;
    map { $this->terminate_server($_, $message) } $this->networks_list;
    map { $this->close_client($_, $message) } $this->clients_list;
    # �ʤ������ΰ��֤ǥ����Х����åȤ��Ĥ���Ȥ��������ʤ롣
    # accept �ǽ������뤳�Ȥˤ��롣
}

sub broadcast_to_clients {
    # IRCMessage���������Ǥʤ����ƤΥ��饤����Ȥ��������롣
    # fill-prefix-when-sending-to-client�Ȥ�����᤬�դ��Ƥ����顢
    # Prefix�򤽤Υ��饤����Ȥ�fullname�����ꤹ�롣
    my ($class_or_this,@messages) = @_;
    my $this = $class_or_this->_this;
    foreach my $client (@{$this->{clients}}) {
	next if $client->logging_in;
	
	foreach my $msg (@messages) {
	    if ($msg->remark('fill-prefix-when-sending-to-client')) {
		$msg = $msg->clone;
		$msg->prefix($client->fullname);
	    }
	    $client->send_message($msg);
	}
    }
}

sub broadcast_to_servers {
    # IRC��å����������ƤΥ����С����������롣
    my ($class_or_this,@messages) = @_;
    my $this = $class_or_this->_this;
    foreach my $network (values %{$this->{networks}}) {
	foreach my $msg (@messages) {
	    $network->send_message($msg);
	}
    }
}

sub notify_modules {
    my ($class_or_this,$method,@args) = @_;
    my $this = $class_or_this->_this;
    foreach my $mod (@{$this->_mod_manager->get_modules}) {
	eval {
	    $mod->$method(@args);
	}; if ($@) {
	    $this->notify_error("Exception in ".ref($mod).".\n".
				"when calling $method.\n".
				"   $@");
	}
    }
}

sub apply_filters {
    # @extra_args: �⥸�塼�����������������ʹߡ��������Ͼ��IRCMessage��
    my ($this, $src_messages, $method, @extra_args) = @_;

    my $source = $src_messages;
    my $filtered = [];
    foreach my $mod (@{$this->_mod_manager->get_modules}) {
	# (���̤ʤ��Ϥ�����) $mod �� undef ���ä��餳�Υ⥸�塼���ȤФ���
	next unless defined $mod;
	# source�������ä��餳���ǽ���ꡣ
	if (scalar(@$source) == 0) {
	    return $source;
	}
	
	foreach my $src (@$source) {
	    my @reply = ();
	    # �¹�
	    eval {
		@reply = $mod->$method($src, @extra_args);
	    }; if ($@) {
		my $modname = ref($mod);
		# �֥�å��ꥹ�Ȥ�����Ƥ���
		$this->_mod_manager->add_to_blacklist($modname);
		$this->notify_error(
		    "Exception in ".$modname.".\n".
			"This module added to blacklist!\n".
			    "The message was '".$src->serialize."'.\n".
				"   $@");
		$this->_mod_manager->remove_from_blacklist($modname);
	    }
	    
	    if (defined $reply[0]) {
		# �ͤ���İʾ��֤äƤ�����
		# ����IRCMessage�Υ��֥������Ȥʤ��ɤ����������Ǥʤ���Х��顼��
		foreach my $msg_reply (@reply) {
		    unless (UNIVERSAL::isa($msg_reply,'IRCMessage')) {
			$this->notify_error(
			    "Reply of ".ref($mod)."::${method} contains illegal value.\n".
			      "It is ".ref($msg_reply).".");
			return $source;
		    }
		}
		
		# �����filtered���ɲá�
		push @$filtered,@reply;
	    }
	}

	# ����source��filtered�ˡ�filtered�϶�������ˡ�
	$source = $filtered;
	$filtered = [];
    }
    return $source;
}

sub _apply_filters {
    # src_messages���ѹ����ʤ���
    my ($this, $src_messages, $sender) = @_;
    $this->apply_filters(
	$src_messages, 'message_arrived', $sender);
}

sub notify_error {
    my ($class_or_this,$str) = @_;
    $class_or_this->notify_msg("===== ERROR =====\n$str");
}
sub notify_warn {
    my ($class_or_this,$str) = @_;
    $class_or_this->notify_msg(":: WARNING :: $str");
}
sub notify_msg {
    # �Ϥ��줿ʸ�����STDOUT�˽��Ϥ����Ʊ���������饤����Ȥ�NOTICE���롣
    # ���ԥ�����LF�ǹԤ�ʬ�䤹�롣
    # ʸ�������ɤ�UTF-8�Ǥʤ���Фʤ�ʤ���
    my ($class_or_this,$str) = @_;
    my $this = $class_or_this->_this;
    $str =~ s/\n+$//s; # ������LF�Ͼõ�

    # STDOUT��
    ::printmsg($str);

    # ���饤����Ȥ�
    my $needed_sending = $this->_conf_general->notice_error_messages;
    if ($needed_sending) {
	my $client_charset = $this->_conf_general->client_out_encoding;
	if (@{$this->clients} > 0) {
	    $this->broadcast_to_clients(
		map {
		    IRCMessage->new(
			Prefix => $this->sysmsg_prefix(qw(priv notify)),
			Command => 'NOTICE',
			Params => [$this->current_nick,
				   "*** $_"]);
		} split /\n/,$str
	    );
	}
    }
}

# -----------------------------------------------------------------------------
# RunLoop�����¹Ԥ�����٤˸ƤФ��եå���
#
# my $hook = RunLoop::Hook->new(sub {
#     my $hook_itself = shift;
#     # ���餫�ν�����Ԥʤ���
# })->install('after-select'); # select�¹�ľ��ˤ��Υեå���Ƥ֡�
# -----------------------------------------------------------------------------
package RunLoop::Hook;
use FunctionalVariable;
use base 'Hook';

our $HOOK_TARGET_NAME = 'RunLoop';
our @HOOK_NAME_CANDIDATES = qw(before-select after-select set-current-nick);
our $HOOK_NAME_DEFAULT = 'after-select';
our $HOOK_TARGET_DEFAULT;
FunctionalVariable::tie(
    \$HOOK_TARGET_DEFAULT,
    FETCH => sub {
	$HOOK_TARGET_NAME->shared_loop;
    },
   );

1;
