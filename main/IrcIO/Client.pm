# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IrcIO::Client�ϥ��饤����Ȥ������³�������
# IRC��å����������ꤹ�륯�饹�Ǥ���
# -----------------------------------------------------------------------------
package IrcIO::Client;
use strict;
use warnings;
use Carp;
use IrcIO;
use base qw(IrcIO);
use Net::hostent;
use Crypt;
use Multicast;
use Mask;
use LocalChannelManager;
use NumericReply;
use Tiarra::Utils;
# shorthand
my $utils = Tiarra::Utils->shared;

# ʣ���Υѥå������򺮺ߤ����Ƥ��SelfLoader���Ȥ��ʤ��ġ�
#use SelfLoader;
#SelfLoader->load_stubs; # ���Υ��饹�ˤϿƥ��饹�����뤫�顣(SelfLoader��pod�򻲾�)
#1;
#__DATA__

sub new {
    my ($class,$runloop,$sock) = @_;
    my $this = $class->SUPER::new($runloop);
    $this->{sock} = $sock;
    $this->{connected} = 1;
    $this->{client_host} = do {
	my $hostent = Net::hostent::gethost($sock->peerhost); # �հ���
	defined $hostent ? $hostent->name : $sock->peerhost;
    };
    $this->{pass_received} = ''; # ���饤����Ȥ��������ä��ѥ����
    $this->{nick} = ''; # ��������˥��饤����Ȥ��������ä�nick���ѹ�����ʤ���
    $this->{username} = ''; # Ʊusername
    $this->{logging_in} = 1; # ��������ʤ�1
    $this->{options} = {}; # ���饤����Ȥ���³����$key=value$�ǻ��ꤷ�����ץ����

    # ���Υۥ��Ȥ������³�ϵ��Ĥ���Ƥ��뤫��
    my $allowed_host = $this->_conf_general->client_allowed;
    if (defined $allowed_host) {
	unless (Mask::match($allowed_host,$this->{client_host})) {
	    # �ޥå����ʤ��Τ�die��
	    die "One client at ".$this->{client_host}." connected to me, but the host is not allowed.\n";
	}
    }
    ::printmsg("One client at ".$this->{client_host}." connected to me.");
    $this->_runloop->register_receive_socket($sock);
    $this;
}

sub logging_in {
    shift->{logging_in};
}

sub username {
    shift->{username};
}

sub client_host {
    shift->{client_host};
}

sub fullname {
    # ���Υ��饤����Ȥ�tiarra���鸫��nick!username@userhost�η�����ɽ�����롣
    my ($this,$type) = @_;
    if (defined $type && $type eq 'error') {
	$this->_runloop->current_nick.'['.$this->{username}.'@'.$this->{client_host}.']';
    }
    else {
	$this->_runloop->current_nick.'!'.$this->{username}.'@'.$this->{client_host};
    }
}

sub fullname_from_client {
    # ���Υ��饤����Ȥ򥯥饤����Ȥ��鸫��nick!username@userhost�η�����ɽ�����롣
    # ���δؿ����֤�nick�Ͻ��˼�����ä���ΤǤ���������ա�
    my $this = shift;
    $this->{nick}.'!'.$this->{username}.'@'.$this->{client_host};
}

sub parse_realname {
    my ($this,$realname) = @_;
    return if !defined $realname;
    # $key=value;key=value;...$
    #
    # �ʲ�������ͭ���ǡ�Ʊ����̣�Ǥ��롣
    # $ foo = bar; key=  value$
    # $ foo=bar;key=value $
    # $foo    =bar;key=  value    $

    my $key = qr{[^=]+?}; # �����Ȥ��Ƶ������ѥ�����
    my $value = qr{[^;]*?}; # �ͤȤ��Ƶ������ѥ�����
    my $lastpair = qr{$key\s*=\s*$value};
    my $pair = qr{$lastpair\s*;};

    my $line = qr{^\$(?:\s*($pair)\s*)*\s*($lastpair)\s*\$$};
    if (my @pairs = ($realname =~ m/$line/g)) {
	%{$this->{options}} = map {
	    m/^\s*($key)\s*=\s*($value)\s*;?$/;
	} grep {
	    defined;
	} @pairs;
    }
}

sub option {
    # ���������$key=value$�ǻ��ꤵ�줿���ץ�����������롣
    # ���ꤵ�줿�������Ф����ͤ�¸�ߤ��ʤ��ä�����undef���֤���
    my ($this,$key) = @_;
    if (defined $key) {
	$this->{options}->{$key};
    }
    else {
	croak "IrcIO::Client->option, Arg[1] was undef.";
    }
}

sub option_or_default {
    my ($this, $base, $config_prefix, $option_prefix, $default) = @_;
    my $value;

    $utils->get_first_defined(
	$this->option($utils->to_str($option_prefix).$base),
	$this->_conf_general->get($utils->to_str($option_prefix).$base),
	$default);
}

sub option_or_default_multiple {
    my ($this, $base, $types, $config_prefix) = @_;

    return $utils->get_first_defined(
	(map {
	    $this->option(join('',$utils->to_str($_, $base)));
	} @$types),
	(map {
	    $this->_conf_general->get(
		join('',$utils->to_str($config_prefix, $_, $base)));
	} @$types));
}

sub send_message {
    my ($this,$msg) = @_;

    # �ƥ⥸�塼�������
    #$this->_runloop->notify_modules('notification_of_message_io',$msg,$this,'out');

    $this->SUPER::send_message(
	$msg,
	$this->option_or_default_multiple('encoding', ['out-', ''], 'client-'));
}

sub receive {
    my ($this) = shift;
    $this->SUPER::receive(
	$this->option_or_default_multiple('encoding', ['in-', ''], 'client'));

    # ��³���ڤ줿�顢�ƥ⥸�塼�������
    if (!$this->connected) {
	$this->_runloop->notify_modules('client_detached',$this);
    }
}

sub pop_queue {
    my $this = shift;
    my $msg = $this->SUPER::pop_queue;

    # ���饤����Ȥ���������ʤ顢�����������դ��롣
    if (defined $msg) {
	# �ƥ⥸�塼�������
	#$this->_runloop->notify_modules('notification_of_message_io',$msg,$this,'in');

	# ���������椫��
	if ($this->{logging_in}) {
	    return $this->_receive_while_logging_in($msg);
	}
	else {
	    return $this->_receive_after_logged_in($msg);
	}
    }
    return $msg;
}

sub _receive_while_logging_in {
    my ($this,$msg) = @_;

    # NICK�ڤ�USER�������ä������Ǥ��Υ���������������ǧ������Ȥ�λ���롣
    my $command = $msg->command;
    if ($command eq 'PASS') {
	$this->{pass_received} = $msg->params->[0];
    }
    elsif ($command eq 'NICK') {
	$this->{nick} = $msg->params->[0];
    }
    elsif ($command eq 'USER') {
	$this->{username} = $msg->param(0);
	$this->parse_realname($msg->param(3));
    }
    elsif ($command eq 'PING') {
	$this->send_message(
	    new IRCMessage(
		Command => 'PONG',
		Param => $msg->param(0)));
    }
    elsif ($command eq 'QUIT') {
	$this->send_message(
	    IRCMessage->new(
		Command => 'ERROR',
		Param => 'Closing Link: ['.$this->fullname_from_client.'] ()'));
	$this->disconnect_after_writing;
    }

    if ($this->{nick} ne '' && $this->{username} ne '') {
	# general/tiarra-password�����
	my $valid_password = $this->_conf_general->tiarra_password;
	my $prefix = $this->_runloop->sysmsg_prefix('system');
	if (defined $valid_password && $valid_password ne '' &&
	    ! Crypt::check($this->{pass_received},$valid_password)) {
	    # �ѥ���ɤ��������ʤ���
	    ::printmsg("Refused login of ".$this->fullname_from_client." because of bad password.");

	    $this->send_message(
		new IRCMessage(Prefix => $prefix,
			       Command => ERR_PASSWDMISMATCH,
			       Params => [$this->{nick},'Password incorrect']));
	    $this->send_message(
		new IRCMessage(Command => 'ERROR',
			       Param => 'Closing Link: ['.$this->fullname_from_client.'] (Bad Password)'));
		$this->disconnect_after_writing;
	}
	else {
	    # �ѥ���ɤ��������������ꤵ��Ƥ��ʤ���
	    ::printmsg('Accepted login of '.$this->fullname_from_client.'.');
	    if ((my $n_options = keys %{$this->{options}}) > 0) {
		# ���ץ���󤬻��ꤵ��Ƥ�����ɽ�����롣
		my $options = join ' ; ',map {
		    "$_ = $this->{options}->{$_}";
		} keys %{$this->{options}};
		::printmsg('Given option'.($n_options == 1 ? '' : 's').': '.$options);
	    }
	    $this->{logging_in} = 0;

	    $this->send_message(
		new IRCMessage(Prefix => $prefix,
			       Command => RPL_WELCOME,
			       Params => [$this->{nick},'Welcome to the Internet Relay Network '.$this->fullname_from_client]));

	    my $current_nick = $this->_runloop->current_nick;
	    if ($this->{nick} ne $current_nick) {
		# ���饤����Ȥ����äƤ���nick�ȥ������nick��������äƤ���Τ�������nick�򶵤��롣
		$this->send_message(
		    new IRCMessage(Prefix => $this->fullname_from_client,
				   Command => 'NICK',
				   Param => $current_nick));
	    }

	    my $send_message = sub {
		my ($command, @params) = @_;
		$this->send_message(
		    new IRCMessage(
			Prefix => $prefix,
			Command => $command,
			Params => [$current_nick,
				   @params],
		       ));
	    };

	    map {
		# ������nick�ȥ����Х�nick��������äƤ����餽�λݤ������롣
		my $network_name = $_->network_name;
		my $global_nick = $_->current_nick;
		if ($global_nick ne $current_nick) {
		    $this->send_message(
			new IRCMessage(
			    Prefix => $this->_runloop->sysmsg_prefix(qw(priv system)),
			    Command => 'NOTICE',
			    Params => [$current_nick,
				       "*** Your global nick in $network_name is currently '$global_nick'."]));
		}
	    } values %{$this->_runloop->networks};
	    
	    $send_message->(RPL_YOURHOST, "Your host is $prefix, running version ".::version());
	    if (!$this->_runloop->multi_server_mode_p) {
		# single server mode
		my $network = ($this->_runloop->networks_list)[0];

		if (defined $network) {
		    # send isupport
		    my $msg_tmpl = IRCMessage->new(
			Prefix => $prefix,
			Command => RPL_ISUPPORT,
			Params => [$current_nick],
		       );
		    # last param is reserved for 'are supported...'
		    my $max_params = IRCMessage::MAX_PARAMS - 1;
		    my @params = ();
		    my $length = 0;
		    my $flush_msg = sub {
			if (@params) {
			    my $msg = $msg_tmpl->clone;
			    $msg->push(@params);
			    $msg->push('are supported by this server');
			    $this->send_message($msg);
			}
			@params = ();
			$length = 0;
		    };
		    foreach my $key (keys %{$network->isupport}) {
			my $value = $network->isupport->{$key};
			my $str = length($value) ? ($key.'='.$value) : $key;
			$length += length($str) + 1; # $str and space
			# ;͵�򸫤�400�Х��Ȥ�ۤ�����Ԥ�ʬ���롣
			if ($length >= 400 || scalar(@params) >= $max_params) {
			    $flush_msg->();
			    $length = length($str);
			}
			push(@params, $str);
		    }
		    $flush_msg->();
		}
	    }
	    $send_message->(RPL_MOTDSTART, "- $prefix Message of the Day -");
	    foreach my $line (main::get_credit()) {
		$send_message->(RPL_MOTD, "- ".$line);
	    }
	    $send_message->(RPL_ENDOFMOTD, "End of MOTD command.");

	    # join���Ƥ������ƤΥ����ͥ�ξ���򥯥饤��������롣
	    $this->inform_joinning_channels;

	    # �ƥ⥸�塼��˥��饤������ɲä����Τ�Ф���
	    $this->_runloop->notify_modules('client_attached',$this);
	}
    }
    # ����������˥��饤����Ȥ��������ä������ʤ��å������⥵���С��ˤ�����ʤ���
    return undef;
}

sub _receive_after_logged_in {
    my ($this,$msg) = @_;

    # ��������Ǥʤ���
    my $command = $msg->command;

    if ($command eq 'NICK') {
	if (defined $msg->params) {
	    # �������������¤�NICK�ˤϾ���������ơ�RunLoop�Υ�����nick���ѹ��ˤʤ롣
	    # �������ͥåȥ��̾����������Ƥ������ϥ����Ȥ��ѹ����ʤ���
	    my ($nick,undef,$specified) = Multicast::detach($msg->params->[0]);
	    if (Multicast::nick_p($nick)) {
		unless ($specified) {
		    #$this->send_message(
		    #    new IRCMessage(
		    #	Prefix => $this->fullname,
		    #	Command => 'NICK',
		    #	Param => $msg->params->[0]));
		    if ($this->_runloop->multi_server_mode_p) {
			$this->_runloop->broadcast_to_clients(
			    IRCMessage->new(
				Command => 'NICK',
				Param => $msg->param(0),
				Remarks => {'fill-prefix-when-sending-to-client' => 1}));

			$this->_runloop->set_current_nick($msg->params->[0]);
		    }
		}
	    } else {
		$this->send_message(
		    new IRCMessage(
			Prefix => $this->_runloop->sysmsg_prefix('system'),
			Command => ERR_ERRONEOUSNICKNAME,
			Params => [$this->_runloop->current_nick,
				   $msg->params->[0],
				   'Erroneous nickname']));
		# ����ϻ�������ʤ���
		$msg = undef;
	    }
	} else {
	    $this->send_message(
		new IRCMessage(
		    Prefix => $this->_runloop->sysmsg_prefix('system'),
		    Command => ERR_NONICKNAMEGIVEN,
		    Params => [$this->_runloop->current_nick,
			       'No nickname given']));
	    # ����ϻ�������ʤ���
	    $msg = undef;
	}
    }
    elsif ($command eq 'QUIT') {
	my $quit_message = $msg->param(0);
	$quit_message = '' unless defined $quit_message;

	$this->send_message(
	    new IRCMessage(Command => 'ERROR',
			   Param => 'Closing Link: '.$this->fullname('error').' ('.$quit_message.')'));
	$this->disconnect_after_writing;

	# ��³���ڤ줿���ˤ��롣
	$this->_runloop->notify_modules('client_detached',$this);

	# ����ϻ�������ʤ���
	$msg = undef;
    }
    else {
	$msg = LocalChannelManager->shared
	    ->message_arrived($msg, $this);
    }
    return $msg;
}

sub do_namreply {
    my ($this, $ch, $network, $max_length, $flush_func) = @_;

    $max_length = 400 if !defined $max_length;
    croak('$ch is not specified') if !defined $ch;
    croak('$network is not specified') if !defined $network;
    croak('$flush_func is not specified') if !defined $flush_func;
    my $global_to_local = sub {
	Multicast::global_to_local(shift, $network);
    };
    my $ch_property_char = do {
	if ($ch->switches('s')) {
	    '@';
	}
	elsif ($ch->switches('p')) {
	    '*';
	}
	else {
	    '=';
	}
    };
    # ;͵�򸫤�nick��������� $max_length(�ǥե����:400) �Х��Ȥ�ۤ�����Ԥ�ʬ���롣
    my $nick_enumeration = '';
    my $flush_enum_buffer = sub {
	if ($nick_enumeration ne '') {
	    $flush_func->(
		IRCMessage->new(
		    Prefix => $this->fullname,
		    Command => RPL_NAMREPLY,
		    Params => [$this->_runloop->current_nick,
			       $ch_property_char,
			       Multicast::attach_for_client($ch->name, $network->network_name),
			       $nick_enumeration]));
	    $nick_enumeration = '';
	}
    };
    my $append_to_enum_buffer = sub {
	my $nick_to_append = shift;
	if ($nick_enumeration eq '') {
	    $nick_enumeration = $nick_to_append;
	}
	else {
	    $nick_enumeration .= ' '.$nick_to_append;
	}
    };
    map {
	my $person = $_;
	my $mode_char = do {
	    if ($person->has_o) {
		'@';
	    }
	    elsif ($person->has_v) {
		'+';
	    }
	    else {
		'';
	    }
	};
	$append_to_enum_buffer->($mode_char . $global_to_local->($person->person->nick));
	if (length($nick_enumeration) > $max_length) {
	    $flush_enum_buffer->();
	}
    } values %{$ch->names};
    $flush_enum_buffer->();

    undef;
}

sub inform_joinning_channels {
    my $this = shift;
    my $local_nick = $this->_runloop->current_nick;

    my $send_channelinfo = sub {
	my ($network, $ch) = @_;
	my $ch_name = Multicast::attach_for_client($ch->name, $network->network_name);

	# �ޤ�JOIN
	$this->send_message(
	    IRCMessage->new(
		Prefix => $this->fullname,
		Command => 'JOIN',
		Param => $ch_name));
	# ����RPL_TOPIC(�����)
	if ($ch->topic ne '') {
	    $this->send_message(
		IRCMessage->new(
		    Prefix => $this->fullname,
		    Command => RPL_TOPIC,
		    Params => [$local_nick,$ch_name,$ch->topic]));
	}
	# ����RPL_TOPICWHOTIME(�����)
	if (defined($ch->topic_who)) {
	    $this->send_message(
		IRCMessage->new(
		    Prefix => $this->fullname,
		    Command => RPL_TOPICWHOTIME,
		    Params => [$local_nick,$ch_name,$ch->topic_who,$ch->topic_time]));
	}
	# ����RPL_NAMREPLY
	my $flush_namreply = sub {
	    my $msg = shift;
	    $this->send_message($msg);
	};
	$this->do_namreply($ch, $network, undef, $flush_namreply);
	# �Ǹ��RPL_ENDOFNAMES
	$this->send_message(
	    IRCMessage->new(
		Prefix => $this->fullname,
		Command => RPL_ENDOFNAMES,
		Params => [$local_nick,$ch_name,'End of NAMES list']));

	# channel-info�եå��ΰ����� (IrcIO::Client, �����ѥ����ͥ�̾, �ͥåȥ��, ChannelInfo)
	eval {
	    IrcIO::Client::HookTarget->shared->call(
		'channel-info', $this, $ch_name, $network, $ch);
	}; if ($@) {
	    # ���顼��å�������ɽ�����뤬������������³����
	    $this->_runloop->notify_error(__PACKAGE__." hook call error: $@");
	}
    };

    my %channels = map {
	my $network = $_;
	map {
	    my $ch = $_;
	    (Multicast::attach($ch->name, $network->network_name) =>
		    [$network, $ch]);
	} values %{$network->channels};
    } values %{$this->_runloop->networks};

    # Mask ��Ȥäơ��ޥå�������Τ����
    foreach ($this->_conf_networks->
		 fixed_channels('block')->channel('all')) {
	my $mask = $_;
	foreach (keys %channels) {
	    my $ch_name = $_;
	    if (Mask::match($mask, $ch_name)) {
		$send_channelinfo->(@{$channels{$ch_name}});
		delete $channels{$ch_name};
	    }
	}
    }

    # �Τ�������
    foreach (values %channels) {
	$send_channelinfo->(@$_);
    }
}

# -----------------------------------------------------------------------------
# ���饤����Ȥ˥����ͥ����(JOIN,TOPIC,NAMES��)���Ϥ���ľ��˸ƤФ��եå���
# �����ͥ�̾(multi server mode�ʤ�ͥåȥ��̾�դ�)������Ȥ��ơ�
# �����ͥ��ĤˤĤ����٤��ĸƤФ�롣
#
# my $hook = IrcIO::Client::Hook->new(sub {
#     my $hook_itself = shift;
#     # ���餫�ν�����Ԥʤ���
# })->install('channel-info'); # �����ͥ����ž�����ˤ��Υեå���Ƥ֡�
# -----------------------------------------------------------------------------
package IrcIO::Client::Hook;
use FunctionalVariable;
use base 'Hook';

our $HOOK_TARGET_NAME = 'IrcIO::Client::HookTarget';
our @HOOK_NAME_CANDIDATES = qw/channel-info/;
our $HOOK_NAME_DEFAULT = 'channel-info';
our $HOOK_TARGET_DEFAULT;
FunctionalVariable::tie(
    \$HOOK_TARGET_DEFAULT,
    FETCH => sub {
	IrcIO::Client::HookTarget->shared;
    },
   );

# -----------------------------------------------------------------------------
package IrcIO::Client::HookTarget;
use Hook;
our @ISA = 'HookTarget';
our $_shared;

sub shared {
    my $class = shift;
    if (!defined $_shared) {
	$_shared = bless {} => $class; # �뾵����ʤ�����ˤʤ뤬��
    }
    $_shared;
}

sub call {
    my ($this, $name, @args) = @_;
    $this->call_hooks($name, @args);
}

1;
