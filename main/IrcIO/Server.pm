# -----------------------------------------------------------------------------
# $Id: Server.pm,v 1.56 2004/05/08 08:11:31 topia Exp $
# -----------------------------------------------------------------------------
# IrcIO::Server��IRC�����С�����³����IRC��å����������ꤹ�륯�饹�Ǥ���
# ���Υ��饹�ϥ����С������å������������äƥ����ͥ����丽�ߤ�nick�ʤɤ��ݻ����ޤ�����
# ������ä���å�������⥸�塼����̤�����ƥ��饤����Ȥ�ž��������Ϥ��ޤ���
# �����RunLoop�����ܤǤ���
# -----------------------------------------------------------------------------
package IrcIO::Server;
use strict;
use warnings;
use base qw(IrcIO);
use Carp;
use ChannelInfo;
use PersonalInfo;
use PersonInChannel;
use Configuration;
use UNIVERSAL;
use Multicast;
use NumericReply;

sub new {
    my ($class,$network_name) = @_;
    my $obj = $class->SUPER::new;
    $obj->{network_name} = $network_name;
    $obj->{current_nick} = ''; # ���߻������nick�������󤷤Ƥ��ʤ���ж���
    $obj->{server_hostname} = ''; # �����Ф���ĥ���Ƥ��� hostname�������������󤷤Ƥʤ���ж���
    $obj->reload_config;

    $obj->{logged_in} = 0; # ���Υ����С��ؤΥ�������������Ƥ��뤫�ɤ�����
    $obj->{new_connection} = 1;

    $obj->{receiving_namreply} = {}; # RPL_NAMREPLY���������<�����ͥ�̾,1>�ˤʤꡢRPL_ENDOFNAMES��������Ȥ��Υ����ͥ�����Ǥ��ä��롣
    $obj->{receiving_banlist} = {}; # Ʊ�塣RPL_BANLIST
    $obj->{receiving_exceptlist} = {}; # Ʊ�塣RPL_EXCEPTLIST
    $obj->{receiving_invitelist} = {}; # Ʊ�塢RPL_INVITELIST

    $obj->{channels} = {}; # ��ʸ�������ͥ�̾ => ChannelInfo
    $obj->{people} = {}; # nick => PersonalInfo

    $obj->connect;
}

sub network_name {
    shift->{network_name};
}

sub current_nick {
    shift->{current_nick};
}

sub server_hostname {
    shift->{server_hostname};
}

sub channels {
    # {��ʸ�������ͥ�̾ => ChannelInfo}�Υϥå����ե����֤���
    # @options(��ά��ǽ):
    #   'even-if-kicked-out': ���˼�ʬ������Ф���Ƥ������ͥ���֤�������ư��Ϲ�®�Ǥ��롣
    my ($this, @options) = @_;
    if (defined $options[0] && $options[0] eq 'even-if-kicked-out') {
	$this->{channels};
    }
    else {
	# kicked-out�ե饰��Ω�ĤƤ�ʤ������ͥ�Τ��֤���
	my %result;
	while (my ($name, $ch) = each %{$this->{channels}}) {
	    if (!$ch->remark('kicked-out')) {
		$result{$name} = $ch;
	    }
	}
	\%result;
    }
}

sub channels_list {
    # @options(��ά��ǽ):
    #   'even-if-kicked-out': ���˼�ʬ������Ф���Ƥ������ͥ���֤�������ư��Ϲ�®�Ǥ��롣
    my ($this, @options) = @_;
    if (defined $options[0] && $options[0] eq 'even-if-kicked-out') {
	values %{$this->{channels}};
    }
    else {
	# kicked-out�ե饰��Ω�ĤƤ�ʤ������ͥ�Τ��֤���
	grep {
	    !$_->remarks('kicked-out');
	} values %{$this->{channels}};
    }
}

sub person_list {
    values %{shift->{people}};
}

sub host {
    shift->{server_host};
}

sub fullname {
    $_[0]->{current_nick}.'!'.$_[0]->{user_shortname}.'@'.$_[0]->{server_host};
}

sub config {
    # ���Υ��֥������Ȥ��������Ѥ���줿Configuration::Block���֤���
    shift->{config};
}

sub reload_config {
    my $this = shift;
    my $conf = $this->{config} = Configuration->shared->get($this->{network_name});
    my $general = Configuration->shared->general;
    $this->{server_host} = $conf->host;
    $this->{server_port} = $conf->port;
    $this->{destination} = do {
	if ($this->{server_host} =~ m/^[0-9a-fA-F:]+$/) {
	    "[$this->{server_host}]:$this->{server_port}";
	}
	else {
	    "$this->{server_host}:$this->{server_port}";
	}
    };
    my $def = sub{defined$_[0]?$_[0]:$_[1]};
    $this->{server_password} = $conf->password;
    $this->{initial_nick} = $def->($conf->nick,$general->nick); # ������������ꤹ��nick��
    $this->{user_shortname} = $def->($conf->user,$general->user);
    $this->{user_realname} = $def->($conf->name,$general->name);
}

sub person_if_exists {
    my ($this, $nick) = @_;
    $this->{people}{$nick};
}
    
sub person {
    # nick�ʳ������ƾ�ά��ǽ��
    # ̤�Τ�nick�����ꤵ�줿���Ͽ������ɲä��롣
    my ($this,$nick,$username,$userhost,$realname,$server) = @_;
    return if !defined $nick;

    my $info = $this->{people}->{$nick};
    if (!defined($info)) {
	$info = $this->{people}->{$nick} =
	    new PersonalInfo(Nick => $nick,
			     UserName => $username,
			     UserHost => $userhost,
			     RealName => $realname,
			     Server => $server);
    }
    else {
	$info->username($username);
	$info->userhost($userhost);
	$info->realname($realname);
	$info->server($server);
    }
    $info;
}

sub channel {
    my $this = $_[0];
    my $channel_name = Multicast::lc($_[1]);
    $this->{channels}->{$channel_name};
}

sub connect {
    my $this = shift;
    return if $this->connected;

    # ��������٤��ե�����ɤ�����
    $this->{nick_retry} = 0;
    $this->{logged_in} = undef;

    my $server_host = $this->{server_host};
    my $server_port = $this->{server_port};

    # �ɲåѥ�᡼��
    my $conf = Configuration->shared;
    my $additional_ipv4 = {};
    my $ipv4_bind_addr =
	$conf->get($this->{network_name})->ipv4_bind_addr ||
	$conf->general->ipv4_bind_addr ||
	$conf->get($this->{network_name})->bind_addr ||
	$conf->general->bind_addr; # �ʾ���Ĥϲ��ߴ����ΰ٤˻Ĥ���
    if (defined $ipv4_bind_addr) {
	$additional_ipv4->{LocalAddr} = $ipv4_bind_addr;
    }
    my $additional_ipv6 = {};
    my $ipv6_bind_addr =
	Configuration->shared->get($this->{network_name})->ipv6_bind_addr ||
	Configuration->shared->general->ipv6_bind_addr;
    if (defined $ipv6_bind_addr) {
	$additional_ipv6->{LocalAddr} = $ipv6_bind_addr;
    }

    # �����åȤ򳫤��������ʤ��ä���die��
    # ��³�ϼ��Τ褦�ˤ��ƹԤʤ���
    # 1. �ۥ��Ȥ�IPv4���ɥ쥹�Ǥ���С�IPv4�Ȥ�����³���ߤ롣
    # 2. �ۥ��Ȥ�IPv6���ɥ쥹�Ǥ���С�IPv6�Ȥ�����³���ߤ롣
    # 3. �ɤ���η����Ǥ�ʤ�(�Ĥޤ�ۥ���̾)�Ǥ���С�
    #    a. IPv6�����Ѳ�ǽ�ʤ�IPv6�Ǥ���³���ߤ��塢���ܤʤ�IPv4�˥ե�����Хå�
    #    b. IPv6�����Ѳ�ǽ�Ǥʤ���С��ǽ餫��IPv4�Ǥ���³���ߤ롣
    my @new_socket_args = (
	PeerAddr => $server_host,
	PeerPort => $server_port,
	Proto => 'tcp',
	Timeout => 5,
    );
    my $sock = do {
	if ($server_host =~ m/^(?:\d+\.){3}\d+$/) {
	    IO::Socket::INET->new(@new_socket_args,%$additional_ipv4);
	}
	elsif ($server_host =~ m/^[0-9a-fA-F:]+$/) {
	    if (&::ipv6_enabled) {
		IO::Socket::INET6->new(@new_socket_args,%$additional_ipv6);
	    }
	    else {
		die qq{Host $server_host seems to be an IPv6 address, }.
		    qq{but IPv6 support is not enabled. }.
		    qq{Use IPv4 server or install Socket6.pm if possible.\n};
	    }
	}
	else {
	    if (&::ipv6_enabled) {
		my $s = IO::Socket::INET6->new(@new_socket_args,%$additional_ipv6);
		if (defined $s) {
		    # IPv6�Ǥ���³��������
		    $s;
		}
		else {
		    # IPv4�˥ե�����Хå���
		    IO::Socket::INET->new(@new_socket_args,%$additional_ipv4);
		}
	    }
	    else {
		IO::Socket::INET->new(@new_socket_args,%$additional_ipv4);
	    }
	}
    };
    if (defined $sock) {
	$sock->autoflush(1);
	$this->{sock} = $sock;
	$this->{connected} = 1;
	my $ip_version = do {
	    if ($sock->isa('IO::Socket::INET')) {
		'IPv4';
	    }
	    else {
		'IPv6';
	    }
	};
	::printmsg("Opened connection to $this->{destination} ($ip_version)");
    }
    else {
	die "Couldn't connect to $this->{destination}\n";
    }

    # (PASS) -> NICK -> USER�ν����������������롣
    # NICK�������������ɤ�������³���receive�᥽�åɤ�Ƚ�Ǥ��롣
    my $server_password = $this->{server_password};
    if (defined $server_password && $server_password ne '') {
	$this->send_message(new IRCMessage(
				Command => 'PASS',
				Param => $this->{server_password}));
    }
    if (!defined $this->{current_nick} || $this->{current_nick} eq '') {
	$this->{current_nick} = $this->{initial_nick};
    }
    $this->send_message(new IRCMessage(
			    Command => 'NICK',
			    Param => $this->{current_nick}));

    # +i�ʤɤ�ʸ���󤫤�桼�����⡼���ͤ򻻽Ф��롣
    my $usermode = 0;
    if (my $usermode_str = Configuration->shared->general->user_mode) {
	if ($usermode_str =~ /^\+/) {
	    foreach my $c (split //,substr($usermode_str,1)) {
		if ($c eq 'w') {
		    $usermode |= (1 << 2);
		}
		elsif ($c eq 'i') {
		    $usermode |= (1 << 3);
		}
	    }
	}
    }
    $this->send_message(new IRCMessage(
			    Command => 'USER',
			    Params => [$this->{user_shortname},
				       $usermode,
				       '*',
				       $this->{user_realname}]));
    $this;
}

sub disconnect {
    my $this = shift;

    $this->SUPER::disconnect;
    ::printmsg("Disconnected from $this->{destination}.");
}

sub send_message {
    my ($this,$msg) = @_;

    if (!defined $msg) {
	croak "IrcIO::Server->send_message, Arg[1] was undef.\n";
    }
    elsif (!ref($msg)) {
	croak "IrcIO::Server->send_message, Arg[1] was not ref.\n";
    }
    elsif (!UNIVERSAL::isa($msg, 'IRCMessage')) {
	croak "IrcIO::Server->send_message, Arg[1] was bad ref: ".ref($msg)."\n";
    }

    # �ƥ⥸�塼�������
    #RunLoop->shared->notify_modules('notification_of_message_io',$msg,$this,'out');

    $this->SUPER::send_message(
	$msg,
	Configuration->shared->get($this->{network_name})->out_encoding ||
	Configuration->shared->general->server_out_encoding);
}

sub receive {
    my $this = shift;
    $this->SUPER::receive(
	Configuration->shared->get($this->{network_name})->in_encoding ||
	Configuration->shared->general->server_in_encoding);

    # ��³���ڤ줿�顢�ƥ⥸�塼���RunLoop������
    if (!$this->connected) {
	RunLoop->shared->notify_modules('disconnected_from_server',$this);
	RunLoop->shared->disconnected_server($this);
    }
}

sub pop_queue {
    my ($this) = shift;
    my $msg = $this->SUPER::pop_queue;

    # ���Υ᥽�åɤϥ����󤷤Ƥ��ʤ���Х����󤹤뤬��
    # �ѥ���ɤ��㤦�ʤɤǲ��٤��ľ���Ƥ���������븫���ߤ�̵�����
    # ��³���ڤäƤ���die���ޤ���
    if (defined $msg) {
	# �ƥ⥸�塼�������
	#RunLoop->shared->notify_modules('notification_of_message_io',$msg,$this,'in');

	# ���������椫��
	if ($this->{logged_in}) {
	    # ����������Ǥʤ���
	    return $this->_receive_after_logged_in($msg);
	}
	else {
	    return $this->_receive_while_logging_in($msg);
	}
    }
    return $msg;
}

sub _receive_while_logging_in {
    my ($this,$first_msg) = @_;

    # �ޤ�����������Ǥ���Τʤ顢������������������ɤ�����
    # �ǽ�˼�����ä��Ԥ�001(����)��433(nick��ʣ)������ʳ�����Ƚ�Ǥ��롣
    my $reply = $first_msg->command;
    if ($reply eq RPL_WELCOME) {
	# ����������
	$this->{current_nick} = $first_msg->param(0);
	$this->{server_hostname} = $first_msg->prefix;
	if (!RunLoop->shared->multi_server_mode_p &&
		RunLoop->shared_loop->current_nick ne $this->{current_nick}) {
	    RunLoop->shared->broadcast_to_clients(
		IRCMessage->new(
		    Command => 'NICK',
		    Param => $first_msg->param(0),
		    Remarks => {'fill-prefix-when-sending-to-client' => 1
			       }));

	    RunLoop->shared_loop->set_current_nick($first_msg->param(0));
	}
	$this->{logged_in} = 1;
	$this->person($this->{current_nick},
		      $this->{user_shortname},
		      $this->{user_realname});

	::printmsg("Logged-in successfuly into $this->{destination}.");

	# �ƥ⥸�塼��˥����С��ɲä����Τ�Ԥʤ���
	RunLoop->shared->notify_modules('connected_to_server',$this,$this->{new_connection});
	# ����³���ä����ν���
	if (!$this->{new_connection}) {
	    RunLoop->shared->reconnected_server($this);
	}
	$this->{new_connection} = undef;
    }
    elsif ($reply eq ERR_NICKNAMEINUSE) {
	# nick��ʣ��
	$this->_set_to_next_nick($first_msg->param(1));
	return; # �����֤��ʤ������饤����ȤˤϤ��η�̤��Τ餻�ʤ���
    }
    elsif ($reply eq ERR_UNAVAILRESOURCE) {
	# nick/channel is temporarily unavailable(���ξ��� nick)
	$this->_set_to_next_nick($first_msg->param(1));
	return; # �����֤��ʤ������饤����ȤˤϤ��η�̤��Τ餻�ʤ���
    }
    elsif ($reply eq RPL_HELLO) {
	# RPL_HELLO (irc2.11.x)
	return; # ���⤷�ʤ�
    }
    else {
	# ����ʳ�������Ǥ��褦���ʤ��Τ�connection�������Ǥ��Ƥ��ޤ���
	# â�����˥塼���å���ץ饤�Ǥ�ERROR�Ǥ�ʤ����̵�뤹�롣
	if ($reply eq 'ERROR' or $reply =~ m/^\d+/) {
	    $this->disconnect;
	    die "Server replied $reply.\n".$first_msg->serialize."\n";
	}
	else {
	    return;
	}
    }
    return $first_msg;
}

sub _receive_after_logged_in {
    my ($this,$msg) = @_;
      
    $this->person($msg->nick,$msg->name,$msg->host); # name��host��Ф��Ƥ�����

    if ($msg->command eq 'NICK') {
	# nick���Ѥ����Τ���ʬ�ʤ顢����򥯥饤����Ȥˤ������ʤ���
	my $current_nick = $this->{current_nick};
	if ($msg->nick eq $current_nick) {
	    $this->{current_nick} = $msg->param(0);

	    if (RunLoop->shared->multi_server_mode_p) {
		# �����Ǿä��Ƥ��ޤ��ȥץ饰����ˤ���NICK���Ԥ��ʤ��ʤ롣
		# �ä������"do-not-send-to-clients => 1"�Ȥ��������դ��롣
		$msg->remark('do-not-send-to-clients',1);

		# ������nick�Ȱ�äƤ���С����λݤ����Τ��롣
		# â����networks/always-notify-new-nick�����ꤵ��Ƥ���о�����Τ��롣
		my $local_nick = RunLoop->shared_loop->current_nick;
		if (Configuration->shared->networks->always_notify_new_nick ||
		    $this->{current_nick} ne $local_nick) {

		    my $old_nick = $msg->nick;
		    RunLoop->shared_loop->broadcast_to_clients(
			IRCMessage->new(
			    Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv nick::system)),
			    Command => 'NOTICE',
			    Params => [$local_nick,
				       "*** Your global nick in ".
					   $this->{network_name}." changed ".
					       "$old_nick -> ".
						   $this->{current_nick}."."]));
		}
	    } else {
		RunLoop->shared_loop->set_current_nick($msg->param(0));
	    }
	}
	$this->_NICK($msg);
    }
    elsif ($msg->command eq ERR_NICKNAMEINUSE) {
	# nick�����˻�����
	if (RunLoop->shared->multi_server_mode_p) {
	    $this->_set_to_next_nick($msg->param(1));

	    # ����⥯�饤����Ȥˤ������ʤ���
	    $msg = undef;
	}
    }
    elsif ($msg->command eq ERR_UNAVAILRESOURCE) {
	# nick/channel temporary unavaliable
	if (Multicast::nick_p($msg->param(1)) && RunLoop->shared->multi_server_mode_p) {
	    $this->_set_to_next_nick($msg->param(1));

	    # ����⥯�饤����Ȥˤ������ʤ���
	    $msg = undef;
	}
    }
    elsif ($msg->command eq 'JOIN') {
	$this->_JOIN($msg);
    }
    elsif ($msg->command eq 'KICK') {
	$this->_KICK($msg);
    }
    elsif ($msg->command eq 'MODE') {
	$this->_MODE($msg);
    }
    elsif ($msg->command eq 'NJOIN') {
	$this->_NJOIN($msg);
    }
    elsif ($msg->command eq 'PART') {
	$this->_PART($msg);
    }
    elsif ($msg->command eq 'QUIT' || $msg->command eq 'KILL') {
	# QUIT��KILL��Ʊ���褦�˰�����
	$this->_QUIT($msg);
    }
    elsif ($msg->command eq 'TOPIC') {
	$this->_TOPIC($msg);
    }
    else {
	my $name = NumericReply::fetch_name($msg->command);
	if (defined $name) {
	    foreach (
		map("RPL_$_",
		    qw(CHANNELMODEIS NOTOPIC TOPIC TOPICWHOTIME
		       CREATIONTIME WHOREPLY NAMREPLY ENDOFNAMES
		       WHOISUSER WHOISSERVER AWAY ENDOFWHOIS
		       ISUPPORT YOURID),
		    map({("${_}LIST", "ENDOF${_}LIST");}
			    qw(INVITE EXCEPT BAN)),
		   )) {
		if ($name eq $_) {
		    no strict 'refs';
		    my $funcname = "_$_";
		    &$funcname($this, $msg); # $this->$funcname($msg)
		    last;
		}
	    }
	}
    }
    return $msg;
}

sub _KICK {
    my ($this,$msg) = @_;
    my @ch_names = split(/,/,$msg->param(0));
    my @nicks = split(/,/,$msg->param(1));
    my $kick = sub {
	my ($ch,$nick_to_kick) = @_;
	if ($nick_to_kick eq $this->{current_nick}) {
	    # KICK���줿�Τ���ʬ���ä�
	    $ch->remarks('kicked-out','1');
	}
	else {
	    $ch->names($nick_to_kick,undef,'delete');
	}
    };
    if (@ch_names == @nicks) {
	# �����ͥ�̾��nick��1��1���б�
	map {
	    my ($ch_name,$nick) = ($ch_names[$_],$nicks[$_]);
	    my $ch = $this->channel($ch_name);
	    if (defined $ch) {
		#$ch->names($nick,undef,'delete');
		$kick->($ch,$nick);
	    }
	} 0 .. $#ch_names;
    }
    elsif (@ch_names == 1) {
	# ��ĤΥ����ͥ뤫��1�Ͱʾ��kick
	my $ch = $this->channel($ch_names[0]);
	if (defined $ch) {
	    map {
		#$ch->names($_,undef,'delete');
		$kick->($ch,$_);
	    } @nicks;
	}
    }
}

sub _MODE {
    my ($this,$msg) = @_;
    if ($msg->param(0) eq $this->{current_nick}) {
	# MODE���оݤ���ʬ�ʤΤǤ����Ǥ�̵�롣
	return;
    }

    my $ch = $this->channel($msg->param(0));
    if (defined $ch) {
	my $n_params = @{$msg->params};

	my $plus = 0; # ����ɾ����Υ⡼�ɤ�+�ʤΤ�-�ʤΤ���
	my $mode_char_pos = 1; # ����ɾ�����mode character�ΰ��֡�
	my $mode_param_offset = 0; # $mode_char_pos������Ĥ��ɲåѥ�᥿�򽦤ä�����

	my $fetch_param = sub {
	    $mode_param_offset++;
	    return $msg->param($mode_char_pos + $mode_param_offset);
	};

	for (;$mode_char_pos < $n_params;$mode_char_pos += $mode_param_offset + 1) {
	    $mode_param_offset = 0; # ��������ꥻ�åȤ��롣
	    foreach my $c (split //,$msg->param($mode_char_pos)) {
		my $add_or_delete = ($plus ? 'add' : 'delete');
		my $undef_or_delete = ($plus ? undef : 'delete');
		if ($c eq '+') {
		    $plus = 1;
		}
		elsif ($c eq '-') {
		    $plus = 0;
		}
		elsif (index('aimnpqrst',$c) != -1) {
		    $ch->switches($c,1,$undef_or_delete);
		}
		elsif ($c eq 'b') {
		    $ch->banlist($add_or_delete,&$fetch_param);
		}
		elsif ($c eq 'e') {
		    $ch->exceptionlist($add_or_delete,&$fetch_param);
		}
		elsif ($c eq 'I') {
		    $ch->invitelist($add_or_delete,&$fetch_param);
		}
		elsif ($c eq 'k') {
		    $ch->parameters('k',&$fetch_param,$undef_or_delete);
		}
		elsif ($c eq 'l') {
		    $ch->parameters('l',($plus ? &$fetch_param : undef),$undef_or_delete);
		}
		elsif ($c eq 'o' || $c eq 'O') {
		    # o��O��Ʊ���
		    eval {
			$ch->names(&$fetch_param)->has_o($plus);
		    };
		}
		elsif ($c eq 'v') {
		    eval {
			$ch->names(&$fetch_param)->has_v($plus);
		    };
		}
	    }
	}
    }
}

sub _JOIN {
    my ($this,$msg) = @_;

    map {
	m/^([^\x07]+)(?:\x07(.*))?/;
	my ($ch_name,$mode) = ($1,(defined $2 ? $2 : ''));

	my $ch = $this->channel($ch_name);
	if (defined $ch) {
	    # �ΤäƤ�������ͥ롣�⤷kicked�ե饰��Ω�äƤ����饯�ꥢ��
	    $ch->remarks('kicked-out',undef,'delete');
	}
	else {
	    # �Τ�ʤ������ͥ롣
	    $ch = ChannelInfo->new($ch_name,$this->{network_name});
	    $this->{channels}{Multicast::lc($ch_name)} = $ch;
	}
	$ch->names($msg->nick,
		   new PersonInChannel(
		       $this->person($msg->nick,$msg->name,$msg->host),
		       index($mode,"o") != -1 || index($mode,"O") != -1, # o��O�⺣��Ʊ���
		       index($mode,"v") != -1));
    } split(/,/,$msg->param(0));
}

sub _NJOIN {
    my ($this,$msg) = @_;
    my $ch_name = $msg->param(0);
    my $ch = $this->channel($ch_name);
    unless (defined $ch) {
		# �Τ�ʤ������ͥ롣
	$ch = ChannelInfo->new($ch_name,$this->{network_name});
	$this->{channels}{Multicast::lc($ch_name)} = $ch;
    }
    map {
	m/^([@+]*)(.+)$/;
	my ($mode,$nick) = ($1,$2);

	$ch->names($nick,
		   new PersonInChannel(
		       $this->person($nick),
		       index($mode,"@") != -1, # ����@��@@��Ʊ��롣
			       index($mode,"+") != -1));
    } split(/,/,$msg->param(1));
}

sub _PART {
    my ($this,$msg) = @_;
    map {
	my $ch_name = $_;
	my $ch = $this->channel($ch_name);
	if (defined $ch) {
	    if ($msg->nick eq $this->{current_nick}) {
		# PART�����Τ���ʬ���ä�
		delete $this->{channels}->{Multicast::lc($ch_name)};
	    }
	    else {
		$ch->names($msg->nick,undef,'delete');
	    }
	}
    } split(/,/,$msg->param(0));

    # �������ͥ��������������nick����Ŀ�ʪ����ͤ��ʤ��ʤĤƤ𤿤�people�����ä���
    my $alive;
    foreach my $ch (values %{$this->{channels}}) {
	if (defined $ch->names($msg->nick)) {
	    $alive = 1;
	}
    }
    if (!$alive) {
	delete $this->{people}{$msg->nick};
    }
}

sub _NICK {
    my ($this,$msg) = @_;
    # PersonalInfo��ChannelInfo��nick����äƤ���Τǽ񤭴����롣
    my ($old,$new) = ($msg->nick,$msg->param(0));

    if (!defined $this->{people}->{$old}) {
	return;
    }

    $this->{people}->{$old}->nick($new);
    $this->{people}->{$new} = $this->{people}->{$old};
    delete $this->{people}->{$old};

    my @channels = grep {
	defined $_->names($old);
    } values %{$this->{channels}};

    # ����NICK���ƶ���ڤܤ����������ͥ�̾�Υꥹ�Ȥ�
    # "affected-channels"�Ȥ��������դ��롣
    my @affected = map {
	my $ch = $_;
	$ch->names($new,$ch->names($old));
	$ch->names($old,undef,'delete');
	$ch->name;
    } @channels;
    $msg->remark('affected-channels',\@affected);
}

sub _QUIT {
    my ($this,$msg) = @_;
    # people�ڤ�channels���������롣
    delete $this->{people}->{$msg->nick};

    my @channels = grep {
	defined $_->names($msg->nick);
    } values %{$this->{channels}};

    # ����NICK���ƶ���ڤܤ����������ͥ�̾�Υꥹ�Ȥ�
    # "affected-channels"�Ȥ��������դ��롣
    my @affected = map {
	my $ch = $_;
	$ch->names($msg->nick,undef,'delete');
	$ch->name;
    } @channels;
    $msg->remark('affected-channels',\@affected);
}

sub _TOPIC {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(0));
    if (defined $ch) {
	# �Ť��ȥԥå���"old-topic"�Ȥ��������դ��롣
	$msg->remark('old-topic', $ch->topic);
	$ch->topic($msg->param(1));

	# topic_who �� topic_time ����ꤹ��
	$ch->topic_who($msg->prefix);
	$ch->topic_time(time);
    }
}

sub _RPL_NAMREPLY {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(2));
    return unless defined $ch;

    my $receiving_namreply = $this->{receiving_namreply}->{$msg->param(2)};
    unless (defined $receiving_namreply &&
	    $receiving_namreply == 1) {
	# NAMES������
	$ch->names(undef,undef,'clear');
	# NAMREPLY������ե饰��Ω�Ƥ�
	$this->{receiving_namreply}->{$msg->param(2)} = 1;
    }

    if (defined $ch) {
	# @�ʤ�+s,*�ʤ�+p��=�ʤ餽�Τɤ���Ǥ�ʤ��������ꤷ�Ƥ��롣
	my $ch_property = $msg->param(1);
	if ($ch_property eq '@') {
	    $ch->switches('s',1);
	    $ch->switches('p',undef,'delete');
	}
	elsif ($ch_property eq '*') {
	    $ch->switches('s',undef,'delete');
	    $ch->switches('p',1);
	}
	else {
	    $ch->switches('s',undef,'delete');
	    $ch->switches('p',undef,'delete');
	}

	my @people = map {
	    m/^([@\+]{0,2})(.+)$/;
	    my ($mode,$nick) = ($1,$2);

	    $ch->names($nick,
		       new PersonInChannel(
			   $this->person($nick),
			   index($mode,"@") != -1,
			   index($mode,"+") != -1));
	} split(/ /,$msg->param(3));
    }
}

sub _RPL_ENDOFNAMES {
    my ($this,$msg) = @_;
    delete $this->{receiving_namreply}->{$msg->param(1)};
}

sub _RPL_WHOISUSER {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	$p->username($msg->param(2));
	$p->userhost($msg->param(3));
	$p->realname($msg->param(5));
	$this->_START_WHOIS_REPLY($p);
    }
}

sub _START_WHOIS_REPLY {
    my ($this,$p) = @_;
    $p->remark('wait-rpl_away', 1);
}

sub _RPL_ENDOFWHOIS {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	if ($p->remark('wait-rpl_away')) {
	    $p->remark('wait-rpl_away', 0);
	    $p->away('');
	}
    }
}

sub _RPL_AWAY {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	$p->remark('wait-rpl_away', 0);
	$p->away($msg->param(2));
    }
}

sub _RPL_WHOISSERVER {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(1)};
    if (defined $p) {
	$p->server($msg->param(2));
    }
}

sub _RPL_NOTOPIC {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->topic('');
    }
}

sub _RPL_TOPIC {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->topic($msg->param(2));
    }
}

sub _RPL_TOPICWHOTIME {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->topic_who($msg->param(2));
	$ch->topic_time($msg->param(3));
    }
}

sub _RPL_CREATIONTIME {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->remark('creation-time', $msg->param(2));
    }
}

sub _RPL_INVITELIST {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));

    my $receiving_invitelist = $this->{receiving_invitelist}->{$msg->param(1)};
    if (defined $receiving_invitelist &&
	$receiving_invitelist == 1) {
	# +I�ꥹ�Ȥ�����
	$ch->invitelist(undef,undef,'clear');
	# INVITELIST������ե饰��Ω�Ƥ�
	$this->{receiving_invitelist}->{$msg->param(1)} = 1;
    }

    if (defined $ch) {
	# ��ʣ�ɻߤΤ��ᡢ��ödelete���Ƥ���add��
	$ch->invitelist('delete',$msg->param(2));
	$ch->invitelist('add',$msg->param(2));
    }
}

sub _RPL_ENDOFINVITELIST {
    my ($this,$msg) = @_;
    delete $this->{receiving_invitelist}->{$msg->param(1)};
}

sub _RPL_EXCEPTLIST {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));

    my $receiving_exceptlist = $this->{receiving_exceptlist}->{$msg->param(1)};
    if (defined $receiving_exceptlist &&
	$receiving_exceptlist == 1) {
	# +e�ꥹ�Ȥ�����
	$ch->exceptionlist(undef,undef,'clear');
	# EXCEPTLIST������ե饰��Ω�Ƥ�
	$this->{receiving_exceptlist}->{$msg->param(1)} = 1;
    }

    if (defined $ch) {
	# ��ʣ�ɻߤΤ��ᡢ��ödelete���Ƥ���add��
	$ch->exceptionlist('delete',$msg->param(2));
	$ch->exceptionlist('add',$msg->param(2));
    }
}

sub _RPL_ENDOFEXCEPTLIST {
    my ($this,$msg) = @_;
    delete $this->{receiving_exceptlist}->{$msg->param(1)};
}

sub _RPL_BANLIST {
    my ($this,$msg) = @_;
    my $ch = $this->channel($msg->param(1));

    my $receiving_banlist = $this->{receiving_banlist}->{$msg->param(1)};
    if (defined $receiving_banlist &&
	$receiving_banlist == 1) {
	# +b�ꥹ�Ȥ�����
	$ch->banlist(undef,undef,'clear');
	# BANLIST������ե饰��Ω�Ƥ�
	$this->{receiving_banlist}->{$msg->param(1)} = 1;
    }

    if (defined $ch) {
	# ��ʣ�ɻߤΤ��ᡢ��ödelete���Ƥ���add��
	$ch->banlist('delete',$msg->param(2));
	$ch->banlist('add',$msg->param(2));
    }
}

sub _RPL_ENDOFBANLIST {
    my ($this,$msg) = @_;
    delete $this->{receiving_banlist}->{$msg->param(1)};
}

sub _RPL_WHOREPLY {
    my ($this,$msg) = @_;
    my $p = $this->{people}->{$msg->param(5)};
    if (defined $p) {
	$p->username($msg->param(2));
	$p->userhost($msg->param(3));
	$p->server($msg->param(4));
	$p->realname((split / /,$msg->param(7),2)[1]);
	if ($msg->param(6) =~ /^G/) {
	    $p->away('Gone.');
	} else {
	    $p->away('');
	}
	my $hops = $this->remark('server-hops') || {};
	$hops->{$p->server} = (split / /,$msg->param(7),2)[0];
	$this->remark('server-hops', $hops);
    }

    #use Data::Dumper;
    #open(LOG,"> log.txt");
    #print LOG "------- people --------\n";
    #print LOG Dumper($this->{people}),"\n";
    #print LOG "------- channels --------\n";
    #print LOG Dumper($this->{channels}),"\n";
    #close(LOG);
}

sub _RPL_CHANNELMODEIS {
    my ($this,$msg) = @_;
    # ���ΤΥ����ͥ�ʤ顢���Υ����ͥ��
    # switches-are-known => 1�Ȥ������ͤ��դ��롣
    my $ch = $this->channel($msg->param(1));
    if (defined $ch) {
	$ch->remarks('switches-are-known',1);

	# switches �� parameters ��ɬ��������Ȳ��ꤷ�ơ����ꥢ������Ԥ�
	$ch->switches(undef, undef, 'clear');
	$ch->parameters(undef, undef, 'clear');
    }

    # ����MODE��¹Ԥ������Ȥˤ��ơ�_MODE�˽�������Ԥ����롣
    my @args = @{$msg->params};
    @args = @args[1 .. $#args];

    $this->_MODE(
	new IRCMessage(Prefix => $msg->prefix,
		       Command => 'MODE',
		       Params => \@args));
}

sub _RPL_ISUPPORT {
    # ���Ū����ͳ�ǡ� RPL_ISUPPORT(005) ��
    # RPL_BOUNCE(005) �Ȥ��ƻȤ��Ƥ��뤳�Ȥ����롣
    my ($this,$msg) = @_;
    if ($msg->n_params >= 2 && # nick + [params] + 'are supported by this server'
	    $msg->param($msg->n_params - 1) =~ /supported/i) {
	my $isupport = $this->remark('isupport');
	foreach my $param ((@{$msg->params})[1...($msg->n_params - 2)]) {
	    my ($negate, $key, $value) = $param =~ /^(-)?([[:alnum:]]+)(?:=(.+))?$/;
	    if (!defined $negate) {
		# empty value
		$value = '' unless defined $value;
		$isupport->{$key} = $value;
	    } elsif (!defined $value) {
		# negate a previously specified parameter
		delete $isupport->{$key};
	    } else {
		# inconsistency param
		carp("inconsistency RPL_ISUPPORT param: $param");
	    }
	}
	$this->remark('isupport', $isupport);
    }
}

sub _RPL_YOURID {
    my ($this,$msg) = @_;

    $this->remark('uid', $msg->param(1));
}

sub _set_to_next_nick {
    my ($this,$failed_nick) = @_;
    # failed_nick�μ���nick���ޤ���nick��ʣ�ǥ�����˼��Ԥ������˻Ȥ��ޤ���
    my $nicklen = do {
	if (defined $this->remark('isupport') &&
		defined $this->remark('isupport')->{NICKLEN}) {
	    $this->remark('isupport')->{NICKLEN};
	} else {
	    9;
	}
    };
    my $next_nick = modify_nick($failed_nick, $nicklen);

    my $msg_for_user = "Nick $failed_nick was already in use in the ".$this->network_name.". Trying ".$next_nick."...";
    $this->send_message(
	new IRCMessage(
	    Command => 'NICK',
	    Param => $next_nick));
    RunLoop->shared_loop->broadcast_to_clients(
	new IRCMessage(
	    Prefix => RunLoop->shared_loop->sysmsg_prefix(qw(priv nick::system)),
	    Command => 'NOTICE',
	    Params => [RunLoop->shared_loop->current_nick,$msg_for_user]));
    main::printmsg($msg_for_user);
}

sub modify_nick {
    my $nick = shift;
    my $nicklen = shift || 9;

    if ($nick =~ /^(.*\D)?(\d+)$/) {
	# �Ǹ�ο�ʸ�����������ä��顢����򥤥󥯥����
	my $base = $1;
	my $next_num = $2 + 1;
	if (($next_num - 1) eq $next_num) {
	    # �夢�դ줷�Ƥ���Τǿ�����ʬ�������ä���
	    $nick = $base;
	} elsif (length($base . $next_num) <= $nicklen) {
	    # $nicklen ʸ������˼��ޤ�ΤǤ���ǻ��
	    $nick = $base . $next_num;
	}
	else {
	    # ���ޤ�ʤ��Τ� $nicklen ʸ���˽̤�롣
	    $nick = substr($base,0,$nicklen - length($next_num)) . $next_num;
	}
    }
    elsif ($nick =~ /_$/ && length($nick) >= $nicklen) {
	# �Ǹ��ʸ����_�ǡ�����ʾ�_���դ����ʤ���硢�����0�ˡ�
	$nick =~ s/_$/0/;
    }
    else {
	# �Ǹ��_���դ��롣
	if (length($nick) >= $nicklen) {
	    $nick =~ s/.$/_/;
	}
	else {
	    $nick .= '_';
	}
    }
    return $nick;
}

1;
