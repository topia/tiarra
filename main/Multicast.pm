# -----------------------------------------------------------------------------
# $Id: Multicast.pm,v 1.20 2004/02/14 11:48:18 topia Exp $
# -----------------------------------------------------------------------------
# �����С����饯�饤����Ȥ˥�å�������ή���Ȥ������Υ��饹�ϥե��륿�Ȥ���
# �ͥåȥ��̾���ղä��ޤ���
# ���饤����Ȥ��饵���С���ή���Ȥ������Υ��饹�ϥͥåȥ��̾��ѡ�������
# ����٤��ƥ����С�������ޤ���
# �����뢫�������Х�nick���Ѵ��⤳���ǹԤ��ޤ���
# -----------------------------------------------------------------------------
package Multicast;
use strict;
use warnings;
use Configuration;
use Carp;
my $runloop = undef; # �ǥե���Ȥ�RunLoop�Υ���å��塣
my $default_network = ''; # �ǥե���ȤΥͥåȥ��̾�Υ���å��塣
my $separator = ''; # ���ѥ졼������Υ���å��塣������cast_message���ƤФ���٤˹�������롣

sub _ISON_from_client {
    # nick��ͥåȥ�����ʬ�ह�롣
    my ($message, $sender) = @_;
    my $networks = classify($message->params);

    while (my ($network_name,$params) = each %$networks) {
	my $network = $runloop->networks->{$network_name};
	@$params = map( local_to_global($_,$network) ,@$params);

	forward_to_server(new IRCMessage(
			      Command => $message->command,
			      Params => $params),
			  $network_name);
    }
}

sub _INVITE_from_server {
    my ($message,$sender) = @_;
    # nick�Ϥ��Τޤޡ������ͥ�ˤϥͥåȥ��̾���դ��롣
    $message->nick(global_to_local($message->nick,$sender));
    $message->params->[0] = global_to_local($message->params->[0],$sender);
    $message->params->[1] = attach($message->params->[1],$sender->network_name);
    return $message;
}
sub _INVITE_from_client {
    my ($message,$sender) = @_;
    # nick�ϥѡ�����������ǼΤƤ롣�����ͥ�Υѡ�����̤򸫤롣
    my $to = '';
    ($message->params->[0]) = detatch($message->params->[0]);
    ($message->params->[1],$to) = detatch($message->params->[1]);
    $message->params->[0] = local_to_global($message->params->[0],$to); # ��ʬ��INVITE������ʤ�̵���Τ�ɬ�פ�̵������
    forward_to_server($message,$to);
}

sub _JOIN_from_server {
    my ($message,$sender) = @_;
    # ����ޤǶ��ڤ��ʣ���Υ����ͥ뤬���ꤵ��Ƥ����Ȥ��Ƥ�
    # ���������Ƥ˥ͥåȥ��̾���ղä��롣(�ޤ���̵����������)
    $message->nick(global_to_local($message->nick,$sender));

    my @channels = split(/,/,$message->params->[0]);
    my $n_channels = @channels;
    for (my $i = 0; $i < $n_channels; $i++) {
	$channels[$i] = attach($channels[$i],$sender->network_name);
    }
    $message->params->[0] = join(',',@channels);
    return $message;
}
sub _JOIN_from_client {
    my ($message,$sender) = @_;
    # �ѥ���ɤ���ʬ��Ϯ�餺���ͥåȥ��̾��ѡ������Ƽ�������
    # �ƥ����ͥ��ͥåȥ�����ʬ�ह�롣
    if ($message->params->[0] eq '0') {
	# 0���ü졣
	# ���ƤΥ����С���JOIN 0�����롣
	distribute_to_servers(
	    new IRCMessage(
		Command => 'JOIN',
		Param => '0'));
    }
    else {
	my @targets = split(/,/,$message->params->[0]);
	my $networks = classify(\@targets);
	while (my ($network_name,$channels) = each %$networks) {
	    $message->params->[0] = join(',',@$channels);
	    forward_to_server($message,$network_name);
	}
    }
}

sub _KICK_from_server {
    my ($message,$sender) = @_;
    # �����ͥ�̾�ˤ������ͥåȥ��̾���ղä��롣
    $message->nick(global_to_local($message->nick,$sender));
    $message->params->[0] = attach($message->params->[0],$sender->network_name);
    $message->params->[1] = global_to_local($message->params->[1],$sender);
    return $message;
}
sub _KICK_from_client {
    my ($message,$sender) = @_;
    my @channels = split(/,/,$message->params->[0]);
    my @nicks = split(/,/,$message->params->[1]);
    if (scalar(@channels) == scalar(@nicks)) {
	# �����ͥ��nick�����а���б����롣
	# �����ͥ�Υͥåȥ��̾����Ѥ���nick�Υͥåȥ��̾�ϼΤƤ롣
	for (my $i = 0; $i < @channels; $i++) {
	    my ($raw_channel,$to) = detatch($channels[$i]);
	    my ($raw_nick) = detatch($nicks[$i]);

	    $message->params->[0] = $raw_channel;
	    $message->params->[1] = local_to_global($raw_nick,$runloop->networks->{$to});
	    forward_to_server($message,$to);
	}
    }
    elsif (@channels == 1) {
	# ��ĤΥ����ͥ뤫��ʣ����nick�򽳤�Ф���
	# �����ͥ�Υͥåȥ��̾����Ѥ���nick�Υͥåȥ��̾�ϼΤƤ롣
	my ($raw_channel,$to) = detatch($channels[0]);
	my $network = $runloop->networks->{$to};
	$message->params->[0] = $raw_channel;

	foreach my $nick (@nicks) {
	    my ($raw_nick) = detatch($nick);
	    $message->params->[1] = local_to_global($raw_nick,$network);

	    forward_to_server($message,$to);
	}
    }
}

sub _LIST_from_client {
    my ($message,$sender) = @_;
    # �����ͥ�Υͥåȥ��̾��ʬ�ࡣ
    if (defined $message->params->[0]) {
	my @targets = split(/,/,$message->params->[0]);
	my $networks = classify(\@targets);

	while (my ($network_name,$channels) = each %$networks) {
	    $message->params->[0] = join(',',@$channels);
	    forward_to_server($message,$network_name);
	}
    }
    else {
	forward_to_server($message, $default_network);
    }
}

sub _MODE_from_server {
    my ($message,$sender) = @_;
    $message->nick(global_to_local($message->nick,$sender));
    @{$message->params} = map( global_to_local($_,$sender) ,@{$message->params});

    my $target = $message->params->[0];
    unless (nick_p($target)) {
	# nick(�Ĥޤ꼫ʬ)�ξ��Ϥ��Τޤޥ��饤����Ȥ����ۡ�
	# ���ξ��ϥ����ͥ�ʤΤǡ��ͥåȥ��̾���ղá�
	$message->params->[0] = attach($target,$sender->network_name);
    }
    return $message;
}
sub _MODE_from_client {
    my ($message,$sender) = @_;
    my $to;
    ($message->params->[0],$to) = detatch($message->params->[0]);

    my $network = $runloop->networks->{$to};
    @{$message->params} = map( local_to_global($_,$network) ,@{$message->params});

    forward_to_server($message,$to);
}

sub _NICK_from_client {
    # �ͥåȥ��̾�����ꤵ��Ƥ����顢���λ��ˤΤ�NICK��������
    # �����Ǥʤ�������Ƥλ������롣
    my ($message,$sender) = @_;
    my $to;
    my $specified;
    ($message->params->[0],$to,$specified) = detatch($message->params->[0]);

    if ($specified) {
	forward_to_server($message,$to);
    }
    else {
	distribute_to_servers($message);
    }
}

sub _NJOIN_from_server {
    my ($message,$sender) = @_;
    $message->param(0,attach($message->param(0),$sender->network_name));
    $message->param(1,
		    join(',',
			 map{ s/^([@+]*)(.+)$/$1.global_to_local($2,$sender)/e; $_; } split(/,/,$message->param(1))));
    $message;
}

sub _WHOIS_from_client {
    my ($message,$sender) = @_;
    my $local_nick = $runloop->current_nick;
    my $to;

    # ������nick��WHOIS�����顢���ͥåȥ����nick��ɽ������
    if (($message->command eq 'WHOIS' || $message->command eq 'WHO') &&
	$message->param(0) eq $local_nick) {
	my $prefix = Configuration->shared->general->sysmsg_prefix;
	$sender->send_message(
	    new IRCMessage(Prefix => $prefix,
			   Command => 'NOTICE',
			   Params => [$local_nick,
				      "*** Your local nick is currently '$local_nick'."]));
	map {
	    # ������nick�ȥ����Х�nick��������äƤ����餽�λݤ������롣
	    # ��³���Ƥ���ͥåȥ��̾������ɽ������
	    my $network_name = $_->network_name;
	    my $global_nick = $_->current_nick;
	    if ($global_nick ne $local_nick) {
		$sender->send_message(
		    new IRCMessage(Prefix => $prefix,
				   Command => 'NOTICE',
				   Params => [$local_nick,
					      "*** Your global nick in $network_name is currently '$global_nick'."]));
	    } else {
		$sender->send_message(
		    new IRCMessage(Prefix => $prefix,
				 Command => 'NOTICE',
				 Params => [$local_nick,
					   "*** Your global nick in $network_name is same as local nick."]));
	    }
	} $runloop->networks_list;
    }

    ($message->params->[0],$to) = detatch($message->params->[0]);

    my $network = $runloop->networks->{$to};
    $message->params->[0] = local_to_global($message->params->[0],$runloop->networks->{$to});

    # ������nick��������Υ����Х�nick���ۤʤäƤ����顢���λݤ򥯥饤����Ȥ���𤹤롣
    # ������WHOIS���оݤ���ʬ���ä����Τߡ�
    my $global_nick = $network->current_nick;
    if (($message->command eq 'WHOIS' || $message->command eq 'WHO') &&
	$message->param(0) eq $global_nick &&
	$local_nick ne $global_nick) {
	$sender->send_message(
	    new IRCMessage(Prefix => Configuration->shared->general->sysmsg_prefix,
			   Command => 'NOTICE',
			   Params => [$local_nick,
				      "*** Your global nick in $to is currently '$global_nick'."]));
    }

    forward_to_server($message,$to);
}

sub _RPL_USERHOST {
    my ($message,$sender) = @_;
    $message->params->[1] =~ s/^([^*=]+)(.+)$/global_to_local($1,$sender).$2/e;
    $message;
}

sub _RPL_ISON {
    my ($message,$sender) = @_;
    $message->params->[1] =
	join(' ',
	     map {
		 global_to_local($_,$sender);
	     } split / /,$message->params->[1]);
    $message;
}

sub _RPL_INVITING {
    my ($message,$sender) = @_;
    $message->param(1,attach($message->param(1),$sender->network_name));
    $message->param(2,global_to_local($message->param(2),$sender));
    $message;
}

sub _RPL_WHOREPLY {
    my ($message, $sender) = @_;
    $message->param(1,attach($message->param(1),$sender->network_name));
    $message->param(5,global_to_local($message->param(5),$sender));
    $message;
}

sub _RPL_NAMREPLY {
    my ($message,$sender) = @_;
    $message->param(2,attach($message->param(2),$sender->network_name));
    $message->params->[3] =
	join(' ',
	     map {
		 s/^([@+]*)(.+)$/$1.global_to_local($2,$sender)/e; $_;
	     } split / /,$message->params->[3]);
    $message;
}

my $g2l_cache = {};
sub _gen_g2l_translator {
    my $index = shift;

    unless (exists $g2l_cache->{$index}) {
	$g2l_cache->{$index} = sub {
	    my ($message,$sender) = @_;
	    $message->params->[$index] = global_to_local($message->params->[$index],$sender);
	    $message;
	};
    }
    $g2l_cache->{$index};
}

my $attach_cache = {};
sub _gen_attach_translator {
    my $index = shift;

    unless (exists $attach_cache->{$index}) {
	$attach_cache->{$index} = sub {
	    my ($message,$sender) = @_;
	    $message->param($index,attach($message->param($index),$sender->network_name));
	    $message;
	};
    }
    $attach_cache->{$index};
}

my $detach_cache = {};
sub _gen_detach_translator {
    my $index = shift;

    if (!exists $detach_cache->{$index}) {
	$detach_cache->{$index} = sub {
	    my ($message, $sender) = @_;
	    $message->param(
		$index,
		detach($message->param($index)));
	    forward_to_server($message, $sender);
	};
    }
    $detach_cache->{$index};
}

my $server_sent = {
    'INVITE' => \&_INVITE_from_server,
    'JOIN' => \&_JOIN_from_server,
    'KICK' => \&_KICK_from_server,
    'MODE' => \&_MODE_from_server,
    'NICK' => undef, # ���Τϻ������NICK��Ϯ��ʤ�������򸫤ƾ���򹹿�����Τ�IrcIO::Server�Ǥ��롣
    'NOTICE' => \&_MODE_from_server, # MODE��Ʊ���������ɤ���Prefix��Ϯ��Ȥ���С�����ϥ⥸�塼������ܡ�
    'PART' => \&_JOIN_from_server, # JOIN��Ʊ���������ɤ���
    'PING' => undef,
    'PRIVMSG' => \&_MODE_from_server, # NOTICE��Ʊ���������ɤ���
    'QUIT' => undef, # QUIT�����Τ���ʬ���ä���ΤƤ롢�Ȥ��ä�������IrcIO::Server���Ԥʤ���
    'SQUERY' => \&_MODE_from_server, # ¿ʬ����ϻ�����������������ɤ�ʬ����ʤ���
    'TOPIC' => \&_MODE_from_server,
    'NJOIN' => \&_NJOIN_from_server,
    '301' => _gen_g2l_translator(1), # AWAY
    '302' => \&_RPL_USERHOST,
    '303' => \&_RPL_ISON,
    '311' => _gen_g2l_translator(1), # WHOISUSER
    '312' => _gen_g2l_translator(1), # WHOISSERVER
    '313' => _gen_g2l_translator(1), # WHOISOPERATOR
    '317' => _gen_g2l_translator(1), # WHOISIDLE
    '318' => _gen_g2l_translator(1), # ENDOFWHOIS
    '319' => _gen_g2l_translator(1), # WHOISCHANNELS
    '314' => _gen_g2l_translator(1), # WHOWASUSER
    '369' => _gen_g2l_translator(1), # ENDOFWHOWAS
    '322' => _gen_attach_translator(1), # LIST
    '325' => \&_RPL_INVITING, # UNIQOPIS (INVITING��Ʊ������)
    '324' => _gen_attach_translator(1), # CHANNELMODEIS
    '331' => _gen_attach_translator(1), # NOTOPIC
    '332' => _gen_attach_translator(1), # TOPIC
    '333' => _gen_attach_translator(1), # TOPICWHOTIME
    '341' => \&_RPL_INVITING,
    '346' => _gen_attach_translator(1), # INVITELIST
    '347' => _gen_attach_translator(1), # ENDOFINVITELIST
    '348' => _gen_attach_translator(1), # EXCEPTLIST
    '349' => _gen_attach_translator(1), # ENDOFEXCEPTLIST
    '352' => \&_RPL_WHOREPLY,
    '315' => _gen_attach_translator(1), # ENDOFWHO
    '353' => \&_RPL_NAMREPLY,
    '366' => _gen_attach_translator(1), # ENDOFNAMES
    '367' => _gen_attach_translator(1), # BANLIST
    '368' => _gen_attach_translator(1), # ENDOFBANLIST
    # TRACE�ϤΥ�ץ饤��Tiarra�ϴ��Τ��ʤ������ʤ��Ȥ⺣�ΤȤ���ϡ�
};

my $client_sent = {
    'ISON' => \&_ISON_from_client,
    'INVITE' => \&_INVITE_from_client,
    'JOIN' => \&_JOIN_from_client,
    'KICK' => \&_KICK_from_client,
    'LIST' => \&_LIST_from_client,
    'MODE' => \&_MODE_from_client,
    'NAMES' => \&_LIST_from_client, # LIST��Ʊ���������ɤ���
    'NICK' => \&_NICK_from_client,
    'NOTICE' => \&_LIST_from_client, # LIST��Ʊ���������ɤ���
    #'MODE' => \&_MODE_from_client, # MODE��Ʊ���������ɤ���
    #���տ�������
    'PART' => \&_LIST_from_client, # LIST��Ʊ���������ɤ���
    'PASS' => \&_MODE_from_client, # ��������ܤ˽������ʤ���SERVICE����ʤ���MODE��Ʊ�����ɤ���
    'PONG' => undef,
    'PRIVMSG' => \&_LIST_from_client, # NOTICE��Ʊ���������ɤ���
    'QUIT' => undef, # QUIT��ȥ�åפ���Τ�IrcIO::Client���Ĥޤꤳ���ˤϷ褷��QUIT��ή�����ʤ���
    'SERVICE' => \&_MODE_from_client, # �ɤ�ʬ����ʤ������Ȥꤢ����MODE��Ʊ���ˤ��롣
    'SERVLIST' => \&_MODE_from_client, # ������ɤ�ʬ����ʤ���MODE��Ʊ���ˡ�
    'SERVSET' => \&_MODE_from_client, # ����⡣
    'SQUERY' => \&_MODE_from_client, # �����
    'STATS' => \&_MODE_from_client,
    'SUMMON' => \&_MODE_from_client,
    'TIME' => \&_MODE_from_client,
    'TOPIC' => \&_MODE_from_client,
    'TRACE' => \&_MODE_from_client,
    'UMODE' => \&_MODE_from_client,
    'USER' => undef,
    'USERHOST' => \&_ISON_from_client,
    'USERS' => \&_MODE_from_client,
    'VERSION' => \&_MODE_from_client,
    'WHO' => \&_WHOIS_from_client,
    'WHOIS' => \&_WHOIS_from_client,
    'WHOWAS' => \&_WHOIS_from_client,
    'CLOSE' => \&_MODE_from_client,
    'CONNECT' => \&_MODE_from_client, # ̵�������뤬��
    'DIE' => \&_MODE_from_client,
    'KILL' => \&_MODE_from_client,
    'REHASH' => \&_MODE_from_client,
    'RESTART' => \&_MODE_from_client,
    'SQUIT' => \&_MODE_from_client,
    'ERROR' => undef,
    'NJOIN' => undef, # ���饤����Ȥ���NJOIN��ȯ�Ԥ���Τ�����̵��̣��
    'RECONNECT' => undef,
    'SERVER' => undef,
    'WALLOPS' => \&_MODE_from_client, # ���饤����Ȥ���WALLOPS��ȯ�Խ����Τ��ɤ������Τ�ʤ�����
    # �ʲ���ץ饤�������detach_network_name�ΰ٤����ˤ��롣
    '322' => _gen_detach_translator(1), # LIST
    '325' => _gen_detach_translator(1), # UNIQOPIS (INVITING��Ʊ������)
    '324' => _gen_detach_translator(1), # CHANNELMODEIS
    '331' => _gen_detach_translator(1), # NOTOPIC
    '332' => _gen_detach_translator(1), # TOPIC
    '333' => _gen_detach_translator(1), # TOPICWHOTIME
    '341' => _gen_detach_translator(1), # INVITING
    '346' => _gen_detach_translator(1), # INVITELIST
    '347' => _gen_detach_translator(1), # ENDOFINVITELIST
    '348' => _gen_detach_translator(1), # EXCEPTLIST
    '349' => _gen_detach_translator(1), # ENDOFEXCEPTLIST
    '352' => _gen_detach_translator(1), # WHOREPLY
    '315' => _gen_detach_translator(1), # ENDOFWHO
    '353' => _gen_detach_translator(2), # NAMREPLY
    '366' => _gen_detach_translator(1), # ENDOFNAMES
    '367' => _gen_detach_translator(1), # BANLIST
    '368' => _gen_detach_translator(1), # ENDOFBANLIST
};


sub _update_cache {
    my $networks = Configuration->shared_conf->networks;

    if (RunLoop->shared->multi_server_mode_p) {
	$default_network = $networks->default;
    }
    else {
	if (scalar RunLoop->shared->networks_list) {
	    $default_network = (RunLoop->shared->networks_list)[0]->network_name;
	} else {
	    $default_network = $networks->default;
	}
    }

    $separator = $networks->channel_network_separator;
    $runloop = RunLoop->shared_loop;
}

sub from_server_to_client {
    no warnings;
    my ($message, $sender) = @_;
    &_update_cache;
    # server -> client��ή��Ǥϡ���ĤΥ�å�������ʣ����ʬ�䤵������̵����
    # ���δؿ��ϰ�Ĥ�IRCMessage���֤���

    if ($message->command =~ /^\d+$/) {
	# �˥塼���å���ץ饤��0���ܤΥѥ�᥿������nick��
	$message->params->[0] = global_to_local($message->params->[0],$sender);
    }

    eval {
	# �ե��륿��̵���ä��ꡢ�ե��륿�μ¹�����㳰�������ä��ꤷ�����Ϥ��Τޤ��֤���
	$message = $server_sent->{$message->command}->($message, $sender);
    }; if ($@) {
	$message->nick(global_to_local($message->nick,$sender));
    }
    return $message;
}

sub from_client_to_server {
    no warnings;
    my ($message, $sender) = @_;
    &_update_cache;
    # client -> server��ή��Ǥϡ���ĤΥ�å�������ʣ����ʬ�䤵���������롣
    # ���δؿ��ϥ�å������򻪤�ľ�����ꡢ����ͤ��֤��ʤ���
    eval {
	$client_sent->{$message->command}->($message, $sender);
    }; if ($@) {
	forward_to_server($message,$default_network);
    }
}

sub detach_network_name {
    no strict;
    no warnings;
    my ($message, $sender) = @_;
    &_update_cache;
    my $result;
    local $hijack_forward_to_server = sub {
	my ($msg, $network_name) = @_;
	$result = $msg;
    };
    local $hijack_local_to_global = 1;
    eval {
	$client_sent->{$message->command}->($message, $sender);
    }; if ( !defined $result ) {
	$hijack_forward_to_server->($message, $default_network);
    }
    $result;
}

*detatch = \&detach; # ���㤤���Ƥ�����detach����������
sub detach {
    # �����: (���ѥ졼������ʸ����,�ͥåȥ��̾,�ͥåȥ��̾���������줿���ɤ���)
    # �����������顼����ƥ����ȤǤϥ��ѥ졼������ʸ����Τߤ��֤���
    my $str = shift;

    if (!defined $str) {
	croak "Arg[0] was undef.\n";
    }
    elsif (ref($str) ne '') {
	croak "Arg[0] was ref.\n";
    }

    my ($pkg_caller) = caller;
    _update_cache() unless $pkg_caller->isa('Multicast');

    my @result;
    if ((my $sep_index = index($str,$separator)) != -1) {
	my $before_sep = substr($str,0,$sep_index);
	my $after_sep = substr($str,$sep_index+length($separator));
	if ((my $colon_pos = index($after_sep,':')) != -1) {
	    # #��������@taiyou:*.jp  ��  #��������:*.jp + taiyou
	    @result = ($before_sep.substr($after_sep,$colon_pos),
		       substr($after_sep,0,$colon_pos),
		       1);
	}
	else {
	    # #��������@taiyou  ��  #�������� + taiyou
	    @result = ($before_sep,$after_sep,1);
	}
    }
    else {
	@result = ($str,$default_network,undef);
    }
    return wantarray ? @result : $result[0];
}

sub attach {
    # $str��ChannelInfo�Υ��֥������ȤǤ��ɤ���
    # $network_name�Ͼ�ά��ǽ��IrcIO::Server�Υ��֥������ȤǤ��ɤ���
    my ($str,$network_name) = @_;
    if (ref($str) eq 'ChannelInfo') {
	$str = $str->name;
    }
    if (ref($network_name) eq 'IrcIO::Server') {
	$network_name = $network_name->network_name;
    }

    if (!defined $str) {
	croak "Arg[0] was undef.\n";
    }
    elsif (ref($str) ne '') {
	croak "Arg[0] was ref.\n";
    }

    my ($pkg_caller) = caller;
    _update_cache() unless $pkg_caller->isa('Multicast');

    $network_name = $default_network if $network_name eq '';
    if ((my $pos_colon = index($str,':')) != -1) {
	# #��������:*.jp  ��  #��������@taiyou:*.jp
	$str =~ s/:/$separator.$network_name.':'/e;
    }
    else {
	# #��������  ��  #��������@taiyou
	$str .= $separator.$network_name;
    }
    $str;
}

sub classify {
    # array: ����ؤλ���
    # �����: �ͥåȥ��̾���ѡ������ʸ������¤٤�����ؤλ���
    my $array = shift;
    my $networks = {};
    foreach my $target (@$array) {
	my ($str,$network_name) = detatch($target);
	if (defined $networks->{$network_name}) {
	    push @{$networks->{$network_name}},$str;
	}
	else {
	    # ���Ƹ���줿�ͥåȥ���Ǥ��롣
	    $networks->{$network_name} = [$str];
	}
    }
    return $networks;
}

sub forward_to_server {
    # ���δؿ��ϡ�ưŪ�������פ��֤��줿�ѿ�
    # $hijack_forward_to_server���������Ƥ����顢
    # �����ؿ���ե��ȸ������ƥ����С�����������˸Ƥ֡�
    no strict;
    my ($msg, $network_name) = @_;

    if (defined $hijack_forward_to_server) {
	#::printmsg("forward_to_server HIJACKED");
	$hijack_forward_to_server->($msg, $network_name);
    }
    else {
	my $io = $runloop->network($network_name);
	if (defined $io) {
	    $io->send_message($msg);
	}
    }
}

sub distribute_to_servers {
    no strict;
    my $msg = shift;
    foreach my $server (values %{$runloop->networks}) {
	if (defined $hijack_forward_to_server) {
	    #::printmsg("forward_to_server HIJACKED");
	    $hijack_forward_to_server->($msg, $server->network_name);
	}
	else {
	    $server->send_message($msg);
	}
    }
}

sub nick_p {
    # ʸ����nick�Ȥ��Ƶ����������Ǥ��뤫�ɤ����򿿵��ͤ��֤���
    my $str = detach(shift);
    return undef unless length($str);

    my $first_char = '[a-zA-Z_\[\]\\\`\^\{\}\|]';
    my $remaining_char = '[0-9a-zA-Z_\-\[\]\\\`\^\{\}\|]';
    return $str =~ /^${first_char}${remaining_char}*$/;
}

sub channel_p {
    # ʸ����channel�Ȥ��Ƶ����������Ǥ��뤫�ɤ����򿿵��ͤ��֤���
    my $str = detach(shift);
    return undef unless length($str);

    my $first_char = '[\#\&\+\!]';
    my $suffix_spec = '(?::[a-z*.]+)?';
    return $str =~ /^${first_char}.*${suffix_spec}$/
}

sub local_to_global {
    # ���δؿ��ϡ�ưŪ�������פ��֤��줿�ѿ�
    # $hijack_local_to_global���������Ƥ����顢
    # �����ѹ��������֤���
    no strict;
    my ($str, $server) = @_;
    if (defined $hijack_local_to_global) {
	$str;
    }
    else {
	if (defined($str) && $str eq $runloop->current_nick) {
	    $server->current_nick;
	}
	else {
	    $str;
	}
    }
}

sub global_to_local {
    my ($str,$server) = @_;
    if (defined($str) && $str eq $server->current_nick) {
	return $runloop->current_nick;
    }
    else {
	return $str;
    }
}

1;
