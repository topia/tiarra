# -----------------------------------------------------------------------------
# $Id: RunLoop.pm,v 1.47 2003/10/15 16:23:42 admin Exp $
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
use ModuleManager;
use Multicast;
use Timer;
use ControlPort;
use Hook;
our @ISA = 'HookTarget';
our $_shared_instance;

BEGIN {
    # Time::HiRes�ϻȤ��뤫��
    eval q{
        use Time::HiRes qw(time);
    }; if ($@) {
	# �Ȥ��ʤ���
    }
}

*shared = \&shared_loop;
sub shared_loop {
    if (!defined $_shared_instance) {
	$_shared_instance = _new RunLoop;
    }
    $_shared_instance;
}

sub _new {
    my $class = shift;
    my $this = {
	# �����ѥ��쥯���������륽���åȤϾ�˼�����ɬ�פ����뤿�ᡢ�����륽���åȤ���Ͽ����Ƥ��롣
	receive_selector => new IO::Select,

	# �����ѥ��쥯���������åȤ��Ф����������٤��ǡ�����������ϸ¤��Ƥ��ơ����ξ��ˤΤ���Ͽ����ƽ���꼡��������롣
	send_selector => new IO::Select,

	# Tiarra���ꥹ�˥󥰤��ƥ��饤����Ȥ�����դ��뤿��Υ����åȡ�IO::Socket��
	tiarra_server_socket => undef,

	# ���ߤ�nick�����ƤΥ����С��ȥ��饤����Ȥδ֤����������ݤ��Ĥ�nick���ѹ�������ʤ�RunLoop���Ѱդ��롣
	current_nick => Configuration->shared_conf->general->nick,

	# ���������Ǥ��줿����ư�
	action_on_disconnected => do {
	    my $actions = {
		'part-and-join' => \&_action_part_and_join,
		'one-message' => \&_action_one_message,
		'message-for-each' => \&_action_message_for_each,
	    };
	    my $action_name = Configuration->shared_conf->networks->action_when_disconnected;
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

	networks => {}, # �ͥåȥ��̾ �� IrcIO::Server
	disconnected_networks => {}, # ���Ǥ��줿�ͥåȥ����
	clients => [], # ��³����Ƥ������ƤΥ��饤����� IrcIO::Client

	timers => [], # ���󥹥ȡ��뤵��Ƥ������Ƥ�Timer
	external_sockets => [], # ���󥹥ȡ��뤵��Ƥ������Ƥ�ExternalSocket
	#hooks_before_select => [], # ���󥹥ȡ��뤵��Ƥ������Ƥ�before-select�եå�
	#hooks_after_select => [], # ���󥹥ȡ��뤵��Ƥ������Ƥ�after-select�եå�

	conf_reloaded_hook => undef, # ���β��ǥ��󥹥ȡ��뤹��եå�
    };
    bless $this, $class;

    $this->{conf_reloaded_hook} = Configuration::Hook->new(
	sub {
	    # �ޥ�������С��⡼�ɤ�On/Off���Ѥ�ä�����
	    my $old = $this->{multi_server_mode} ? 1 : 0;
	    my $new = Configuration->shared->networks->multi_server_mode ? 1 : 0;
	    if ($old != $new) {
		# �Ѥ�ä�
		$this->_multi_server_mode_changed;
	    }
	},
       )->install;

    $this;
}

sub DESTROY {
    my $this = shift;
    if (defined $this->{conf_reloaded_hook}) {
	$this->{conf_reloaded_hook}->uninstall;
    }
}

sub network {
    my ($this,$network_name) = @_;
    $this->{networks}->{$network_name};
}

sub networks {
    shift->{networks};
}

sub networks_list {
    values %{shift->{networks}};
}

sub clients {
    shift->{clients};
}

sub clients_list {
    @{shift->{clients}};
}

sub channel {
    # $ch_long: �ͥåȥ��̾�����դ������ͥ�̾
    # ���դ��ä���ChannelInfo�����դ���ʤ����undef���֤���
    my ($this,$ch_long) = @_;

    my ($ch_short,$net_name) = Multicast::detach($ch_long);
    my $network = $this->{networks}->{$net_name};
    if (!defined $network) {
	return undef;
    }

    $network->channel($ch_short);
}

sub current_nick {
    # ���饤����Ȥ��鸫�������ߤ�nick��
    # ����nick�ϼºݤ˻Ȥ��Ƥ���nick�ȤϰۤʤäƤ����礬���롣
    # ���ʤ������˾��nick�����˻Ȥ��Ƥ������Ǥ��롣
    shift->{current_nick};
}

sub set_current_nick {
    my ($this,$new_nick) = @_;
    $this->{current_nick} = $new_nick;
}

sub change_nick {
    my ($this,$new_nick) = @_;

    foreach my $io (values %{$this->{networks}}) {
	$io->send_message(
	    new IRCMessage(
		Command => 'NICK',
		Param => $new_nick));
    }
}

sub multi_server_mode_p {
    shift->{multi_server_mode};
}

sub find_io_with_socket {
    my ($this,$sock) = @_;
    # networks��clients���椫����ꤵ�줿�����åȤ����IrcIO��õ���ޤ���
    # ���դ���ʤ����undef���֤��ޤ���
    foreach my $io (values %{$this->{networks}}) {
	return $io if $io->sock == $sock;
    }
    foreach my $io (@{$this->{clients}}) {
	return $io if $io->sock == $sock;
    }
    undef;
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
    my $do_update_networks = 0;
    while (my ($network_name,$io) = each %networks_closed) {
	# ���쥯�����鳰����
	$this->{receive_selector}->remove($io->sock);
	$this->{send_selector}->remove($io->sock);
	# networks����Ϻ�����ơ������disconnected_networks������롣
	delete $this->{networks}->{$network_name};
	$this->{disconnected_networks}->{$network_name} = $io;
	$do_update_networks = 1;
    }
    if ($do_update_networks) {
	Timer->new(
	    After => 3,
	    Code => sub {
		$this->update_networks;
	    },
	)->install($this);
    }

    for (my $i = 0; $i < @{$this->{clients}}; $i++) {
	my $io = $this->{clients}->[$i];
	unless ($io->connected) {
	    ::printmsg("Connection with ".$io->fullname." has been closed.");
	    $this->{receive_selector}->remove($io->sock);
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
			Params => [Multicast::attach($ch->name,$network_name),
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
		Command => 'NOTICE',
		Params => [$this->current_nick,
			   '*** The connection has been revived between '.$network->network_name.'.']));
    }
    elsif ($event eq 'disconnected') {
	$this->broadcast_to_clients(
	    IRCMessage->new(
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
	    Prefix => 'Tiarra',
	    Command => 'NOTICE',
	    Params => ['', # �����ͥ�̾�ϸ�����ꡣ
		       '*** The connection has been revived between '.$network->network_name.'.']);
	foreach my $ch (values %{$network->channels}) {
	    $msg->param(0,Multicast::attach($ch->name,$network_name));
	    $this->broadcast_to_clients($msg);
	}
    }
    elsif ($event eq 'disconnected') {
	my $msg = IRCMessage->new(
	    Prefix => 'Tiarra',
	    Command => 'NOTICE',
	    Params => ['', # �����ͥ�̾�ϸ�����ꡣ
		       '*** The connection has been broken between '.$network->network_name.'.']);
	foreach my $ch (values %{$network->channels}) {
	    $msg->param(0,Multicast::attach($ch->name,$network_name));
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
    my $general_conf = Configuration::shared_conf->get('general');
    my @net_names = Configuration::shared_conf->get('networks')->name('all');
    my $do_update_networks_after = 0; # �ÿ�
    my $do_cleanup_closed_links_after = 0;
    my $host_tried = {}; # {��³���ߤ��ۥ���̾ => 1}

    # �ޥ�������С��⡼�ɤǤʤ���С�@net_names�����Ǥϰ�Ĥ˸¤���٤���
    # �����Ǥʤ���зٹ��Ф�����Ƭ�Τ�Τ�����Ĥ��Ƹ�ϼΤƤ롣
    if (!$this->{multi_server_mode} && @net_names > 1) {
	$this->notify_warn("In single server mode, Tiarra will connect to just a one network; `".
			     $net_names[0]."'");
	@net_names = $net_names[0];
    }

    foreach my $net_name (@net_names) {
	my $net_conf = Configuration::shared_conf->get($net_name);

	if (defined($_ = $this->{networks}->{$net_name})) {
	    # ������³����Ƥ��롣
	    # ���Υ����С��ˤĤ��Ƥ����꤬�Ѥ�äƤ����顢��ö��³���ڤ롣
	    if (!$net_conf->equals($_->config)) {
		$_->disconnect;
		$do_cleanup_closed_links_after = 1;
	    }
	    next;
	}

	# ���Ǥ��줿�ͥåȥ�������Τ�ʤ���
	my $network = $this->{disconnected_networks}->{$net_name};
	eval {
	    if (defined $network) {
		# ����³
		$network->reload_config;
		$network->connect;
		# disconnected_networks����networks�ذܤ���
		$this->{networks}->{$net_name} = $network;
		delete $this->{disconnected_networks}->{$net_name};
	    }
	    else {
		if ($host_tried->{$net_conf->host}) {
		    $do_update_networks_after = 15;
		    $network = undef;
		}
		else {
		    $host_tried->{$net_conf->host} = 1;

		    $network = IrcIO::Server->new($net_name);
		    $this->{networks}->{$net_name} = $network; # networks����Ͽ
		}
	    }
	    if (defined $network) {
		$this->{receive_selector}->add($network->sock); # �������쥯������Ͽ
	    }
	}; if ($@) {
	    print $@;
	    # �����ޡ����ľ����
	    $do_update_networks_after = 3;
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
	$this->disconnect_server($server);
	# ��ư���������ͥ�ؤ�PART������
	$this->_action_part_and_join($server, 'disconnected');
    }
    # disconnected_networks�������פʥͥåȥ������
    while (my ($net_name,$server) = each %{$this->{disconnected_networks}}) {
	# ���äƤ��ʤ��ä���˺��롣
	unless ($is_there_in_net_names->($net_name)) {
	    push @nets_to_forget,$net_name;
	}
    }
    foreach (@nets_to_forget) {
	delete $this->{disconnected_networks}->{$_};
    }
}

sub disconnect_server {
    # ���ꤵ�줿�����С��Ȥ���³���ڤ롣
    # fd�δƻ����Ƥ��ޤ��Τǡ����θ�IrcIO::Server��receive�Ϥ⤦�ƤФ�ʤ�������ա�
    # $server: IrcIO::Server
    my ($this,$server) = @_;
    $this->{receive_selector}->remove($server->sock);
    $this->{send_selector}->remove($server->sock);
    $server->disconnect;
    delete $this->{networks}->{$server->network_name};
}

sub reconnected_server {
    my ($this,$network) = @_;
    # ����³���ä����ν���
    $this->{action_on_disconnected}->($this,$network,'connected');
}

sub disconnected_server {
    my ($this,$network) = @_;
    $this->{action_on_disconnected}->($this,$network,'disconnected');
}

sub install_socket {
    my ($this,$esock) = @_;
    if (!defined $esock) {
	croak "RunLoop->install_socket, Arg[1] was undef.\n";
    }

    push @{$this->{external_sockets}},$esock;
    $this->{receive_selector}->add($esock->sock); # �������쥯������Ͽ
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
	    $this->{receive_selector}->remove($esock->sock); # �������쥯��������Ͽ���
	    $i--;
	}
    }
    $this;
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

=pod
sub install_hook {
    my ($this,$hook_name,$hook) = @_;
    my $array = do {
	if ($hook_name eq 'before-select') {
	    $this->{hooks_before_select};
	}
	elsif ($hook_name eq 'after-select') {
	    $this->{hooks_after_select};
	}
	else {
	    croak "RunLoop->install_hook, hook name '$hook_name' is invalid.\n";
	}
    };
    push @$array,$hook;
    $this;
}

sub uninstall_hook {
    my ($this,$hook_name,$hook) = @_;
    my $array = do {
	if ($hook_name eq 'before-select') {
	    $this->{hooks_before_select};
	}
	elsif ($hook_name eq 'after-select') {
	    $this->{hooks_after_select};
	}
	else {
	    croak "RunLoop->uninstall_hook, hook name '$hook_name' is invalid.\n";
	}
    };
    @$array = grep {
	$_ != $hook;
    } @$array;
    $this;
}

sub call_hooks {
    my ($this,$hook_name) = @_;
    my $array = do {
	if ($hook_name eq 'before-select') {
	    $this->{hooks_before_select};
	}
	elsif ($hook_name eq 'after-select') {
	    $this->{hooks_after_select};
	}
	else {
	    croak "RunLoop->call_hooks, hook name '$hook_name' is invalid.\n";
	}
    };
    foreach my $hook (@$array) {
	eval {
	    $hook->call;
	}; if ($@) {
	    die "RunLoop: Exception in calling hook.\n$@\n";
	}
    }
}

=cut

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
    my $this = shift;
    my $conf_general = Configuration::shared_conf->get('general');

    # �ޥ�������С��⡼��
    $this->{multi_server_mode} =
      Configuration::shared->networks->multi_server_mode;

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
	    $this->{receive_selector}->add($tiarra_server_socket); # ���쥯������Ͽ��
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
			Param => $network->host));

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
	limit => 100,
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
	elsif ($elapsed < $zerotime->{minimum_to_reset}) {
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
	my $timeout = undef;
	my $eariest_timer = $this->get_earliest_timer;
	if (defined $eariest_timer) {
	    $timeout = $eariest_timer->time_to_fire - time;
	}
	if ($timeout < 0) {
	    $timeout = 0;
	}

	$this->_update_send_selector; # �񤭹���٤��ǡ��������륽���åȤ�����send_selector����Ͽ���롣�����Ǥʤ������åȤϽ�����
	# select���եå���Ƥ�
	$this->call_hooks('before-select');
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
		    eval {
			my $client = new IrcIO::Client($new_sock);
			push @{$this->{clients}},$client;
			$this->{receive_selector}->add($new_sock);
		    }; if ($@) {
			print "$@\n";
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
			    # �⥸�塼����̤���
			    my $filtered_messages = $this->_apply_filters([$msg],$io);		    
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
    }
}

sub broadcast_to_clients {
    # IRCMessage���������Ǥʤ����ƤΥ��饤����Ȥ��������롣
    # fill-prefix-when-sending-to-client�Ȥ�����᤬�դ��Ƥ����顢
    # Prefix�򤽤Υ��饤����Ȥ�fullname�����ꤹ�롣
    my ($this,@messages) = @_;
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
    my ($this,@messages) = @_;
    foreach my $network (values %{$this->{networks}}) {
	foreach my $msg (@messages) {
	    $network->send_message($msg);
	}
    }
}

sub notify_modules {
    my ($this,$method,@args) = @_;
    my $mods = ModuleManager->shared->get_modules;
    foreach my $mod (@$mods) {
	eval {
	    $mod->$method(@args);
	}; if ($@) {
	    $this->notify_error("Exception in ".ref($mod).".\n".
				"when calling $method.\n".
				"   $@");
	}
    }
}

sub _apply_filters {
    # src_messages���ѹ����ʤ���
    my ($this,$src_messages,$sender) = @_;
    my $mods = ModuleManager->shared_manager->get_modules;

    my $source = $src_messages;
    my $filtered = [];
    foreach my $mod (@$mods) {
	# source�������ä��餳���ǽ���ꡣ
	if (scalar(@$source) == 0) {
	    return $source;
	}
	
	foreach my $src (@$source) {
	    my @reply = ();
	    # �¹�
	    eval {
		@reply = $mod->message_arrived($src,$sender);
		
	    }; if ($@) {
		$this->notify_error("Exception in ".ref($mod).".\n".
				    "The message was '".$src->serialize."'.\n".
				    "   $@");
	    }
	    
	    if (defined $reply[0]) {
		# �ͤ���İʾ��֤äƤ�����
		# ����IRCMessage�Υ��֥������Ȥʤ��ɤ����������Ǥʤ���Х��顼��
		foreach my $msg_reply (@reply) {
		    unless (UNIVERSAL::isa($msg_reply,'IRCMessage')) {
			$this->notify_error("Reply of ".ref($mod)."::message_arived contains illegal value.\n".
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

sub notify_error {
    my ($this,$str) = @_;
    $this->notify_msg("===== ERROR =====\n$str");
}
sub notify_warn {
    my ($this,$str) = @_;
    $this->notify_msg(":: WARNING :: $str");
}
sub notify_msg {
    # �Ϥ��줿ʸ�����STDOUT�˽��Ϥ����Ʊ���������饤����Ȥ�NOTICE���롣
    # ���ԥ�����LF�ǹԤ�ʬ�䤹�롣
    # ʸ�������ɤ�UTF-8�Ǥʤ���Фʤ�ʤ���
    my ($this,$str) = @_;
    $str =~ s/\n+$//s; # ������LF�Ͼõ�

    # STDOUT��
    ::printmsg($str);

    # ���饤����Ȥ�
    my $needed_sending = Configuration->shared_conf->general->notice_error_messages;
    if ($needed_sending) {
	my $client_charset = Configuration->shared_conf->general->client_out_encoding;
	if (@{$this->clients} > 0) {
	    $this->broadcast_to_clients(
		map {
		    IRCMessage->new(
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
#use strict;
#use warnings;
#use Carp;
use FunctionalVariable;
use base 'Hook';

our $HOOK_TARGET_NAME = 'RunLoop';
our @HOOK_NAME_CANDIDATES = qw/before-select after-select/;
our $HOOK_NAME_DEFAULT = 'after-select';
our $HOOK_TARGET_DEFAULT;
FunctionalVariable::tie(
    \$HOOK_TARGET_DEFAULT,
    FETCH => sub {
	RunLoop->shared;
    },
   );

=pod
sub new {
    my ($class,$code) = @_;
    my $this = {
	runloop => undef,
	hook_name => undef,

	code => $code,
    };

    if (!defined $code) {
	croak "RunLoop::Hook->new, Arg[0] was undef.\n";
    }
    elsif (ref($code) ne 'CODE') {
	croak "RunLoop::Hook->new, Arg[0] was bad type.\n";
    }

    bless $this,$class;
}

sub install {
    # $hook_name: 'before-select' �ޤ��� 'after-select'��
    #             ���줾��selectľ����ľ��˸ƤФ�롣��ά���줿��undef���Ϥ��줿����after-select�ˤʤ롣
    # $runloop:   ���󥹥ȡ��뤹��RunLoop����ά���줿����RunLoop->shared��
    my ($this,$hook_name,$runloop) = @_;
    $hook_name = 'after-select' if !defined $hook_name;
    $runloop = RunLoop->shared if !defined $runloop;

    if (defined $this->{runloop}) {
	croak "RunLoop::Hook->install, this hook is already installed.\n";
    }

    $this->{runloop} = $runloop;
    $this->{hook_name} = $hook_name;
    $runloop->install_hook($hook_name,$this);

    $this;
}

sub uninstall {
    my $this = shift;

    $this->{runloop}->uninstall_hook($this->{hook_name},$this);
    $this->{runloop} = undef;
    $this->{hook_name} = undef;

    $this;
}

sub call {
    my $this = shift;

    my ($caller_pkg) = caller;
    if ($caller_pkg->isa('RunLoop')) {
	$this->{code}->($this);
    }
    else {
	croak "Only RunLoop can call RunLoop::Hook->call\n";
    }
}

=cut

1;
