# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Socket Connector
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket::Connect;
use strict;
use warnings;
use Carp;
use Tiarra::Socket;
use base qw(Tiarra::Socket);
use Timer;
use Socket;
use Tiarra::OptionalModules;
use Tiarra::Utils;
utils->define_attr_accessor(0, qw(domain host addr port callback),
			    qw(bind_addr prefer timeout),
			    qw(retry_int retry_count try_count));
utils->define_attr_enum_accessor('domain', 'eq',
				 qw(tcp unix));

# now supported tcp, unix

# tcp:
#   my $connector = connect->new(
#       host => [hostname],
#       port => [port],
#       callback => sub {
#           my ($genre, $connector, $msg_or_sock) = @_;
#           if ($genre eq 'warn') {
#               # $msg_or_sock: msg
#               warn $msg_or_sock;
#           } elsif ($genre eq 'error') {
#               # $msg_or_sock: msg
#               die $msg_or_sock;
#           } elsif ($genre eq 'sock') {
#               # $msg_or_sock: sock
#               attach($connector->current_addr, $connector->current_port,
#                      $msg_or_sock);
#           # optional genre
#           } elsif ($genre eq 'interrupt') {
#               # $msg_or_sock: undef
#               die 'interrupted';
#           } elsif ($genre eq 'timeout') {
#               # $msg_or_sock: undef
#               die 'timeout';
#           }
#       },
#       # optional params
#       addr => [already resolved addr],
#       bind_addr => [bind_addr (cannot specify host)],
#       timeout => [timeout], # didn't test enough, please send report when bugs.
#       retry_int => [retry interval],
#       retry_count => [retry count],
#       prefer => [prefer socket type(and order) (ipv4, ipv6) as string's
#                  array ref, default ipv6, ipv4],
#       domain => 'tcp', # default
#       );
#   $connector->interrupt;

sub new {
    my ($class, %opts) = @_;

    $class->_increment_caller('socket-connector', \%opts);
    my $this = $class->SUPER::new(%opts);
    map {
	$this->$_($opts{$_});
    } qw(host addr port callback bind_addr timeout retry_int retry_count);
    $this->domain(utils->get_first_defined($opts{domain},
					   'tcp'));
    $this->prefer(utils->get_first_defined($opts{prefer},
					   [qw(ipv6 ipv4)]));
    $this->{queue} = [];
    $this->connect;
}

sub connect {
    my $this = shift;

    if (defined $this->timeout) {
	$this->{timer} = Timer->new(
	    After => $this->timeout,
	    Code => sub {
		$this->interrupt('timeout');
	    });
    }

    $this->prefer([qw('unix')]) if $this->domain_unix;
    if (defined $this->addr || $this->domain_unix) {
	my $entry = Tiarra::Resolver::QueueData->new;
	$entry->answer_status($entry->ANSWER_OK);
	$entry->answer_data([$this->addr]);
	$this->_connect_stage($entry);
    } else {
	Tiarra::Resolver->resolve(
	    'addr', $this->host, sub {
		eval {
		    $this->_connect_stage(@_);
		}; if ($@) {
		    $this->_connect_error("internal error: $@");
		}
	    });
    }
    $this;
}

sub _connect_stage {
    my ($this, $entry) = @_;

    my %addrs_by_types;

    if ($entry->answer_status ne $entry->ANSWER_OK) {
	$this->_connect_error("Couldn't resolve hostname");
	return undef; # end
    }

    foreach my $addr (@{$entry->answer_data}) {
	push (@{$addrs_by_types{$this->probe_type_by_addr($addr)}},
	      $addr);
    }

    foreach my $sock_type (@{$this->prefer}) {
	my $struct;
	push (@{$this->{queue}},
	      map {
		  $struct = {
		      type => $sock_type,
		      addr => $_,
		      port => $this->port,
		  };
	      } @{$addrs_by_types{$sock_type}});
    }
    $this->_connect_try_next;
}

sub _connect_try_next {
    my $this = shift;

    $this->{connecting} = shift @{$this->{queue}};
    if (defined $this->{connecting}) {
	my $methodname = '_try_connect_' . $this->{connecting}->{type};
	$this->$methodname;
    } else {
	if ($this->retry_int && (++$this->try_count <= $this->retry_count)) {
	    $this->{timer} = Timer->new(
		After => $this->retry_int,
		Code => sub {
		    $this->cleanup;
		    $this->connect;
		});
	    $this->_connect_warn(
		'all dead, ' .
		    utils->to_ordinal_number($this->try_count) . ' retry');
	} else {
	    $this->_connect_error('all dead');
	}
    }
}

sub _try_connect_ipv4 {
    my $this = shift;

    $this->_try_connect_tcp('IO::Socket::INET');
}

sub _try_connect_ipv6 {
    my $this = shift;

    if (!Tiarra::OptionalModules->ipv6) {
	$this->_error(
	    qq{Host $this->{host} seems to be an IPv6 address, }.
		qq{but IPv6 support is not enabled. }.
		    qq{Use IPv4 or install Socket6 or IO::Socket::INET6 if possible.\n});
    }

    $this->_try_connect_tcp('IO::Socket::INET6');
}

sub _try_connect_tcp {
    my ($this, $package, $addr, %additional) = @_;

    eval "require $package";
    my $sock = $package->new(
	%additional,
	(defined $this->{bind_addr} ?
	     (LocalAddr => $this->{bind_addr}) : ()),
	Timeout => undef,
	Proto => 'tcp');
    if (!defined $sock) {
	$this->_connect_error($this->sock_errno_to_msg($!, 'Couldn\'t prepare socket'));
	return;
    }
    if (!defined $sock->blocking(0)) {
	# effect only on connecting; comment out
	#$this->_warn('cannot non-blocking') if ::debug_mode();

	if ($this->_is_winsock) {
	    # winsock FIONBIO
	    my $FIONBIO = 0x8004667e; # from Winsock2.h
	    my $temp = chr(1);
	    my $retval = $sock->ioctl($FIONBIO, $temp);
	    if (!$retval) {
		$this->_warn($this->sock_errno_to_msg(
		    $!, 'Couldn\'t set non-blocking mode (winsock2)'));
	    }
	} else {
	    $this->_warn($this->sock_errno_to_msg(
		$!, 'Couldn\'t set non-blocking mode (general)'));
	}
    }
    my $saddr = Tiarra::Resolver->resolve(
	'saddr', [$this->current_addr, $this->current_port],
	sub {}, 0);
    $this->{connecting}->{saddr} = $saddr->answer_data;
    if ($sock->connect($this->{connecting}->{saddr}) ||
	    $!{EINPROGRESS} || $!{EWOULDBLOCK}) {
	my $error = $!;
	$this->attach($sock);
	$! = $error;
	if ($!{EINPROGRESS} || $!{EWOULDBLOCK}) {
	    $this->install;
	} else {
	    $this->_call;
	}
    } else {
	$this->_connect_warn_try_next($!, 'connect error');
    }
}

sub _try_connect_unix {
    my $this = shift;

    if (!Tiarra::OptionalModules->unix_dom) {
	$this->_error(
	    qq{Host $this->{host} seems to be an Unix Domain Socket address, }.
		qq{but Unix Domain Socket support is not enabled. }.
		    qq{Use other protocol if possible.\n});
    }

    require IO::Socket::UNIX;
    my $sock = IO::Socket::UNIX->new(Peer => $this->{connecting}->{addr});
    if (defined $sock) {
	$this->attach($sock);
	$this->_call;
    } else {
	$this->_connect_warn_try_next($!, 'Couldn\'t connect');
    }
}

sub _connect_warn_try_next {
    my ($this, $errno, $msg) = @_;

    $this->_connect_warn($this->sock_errno_to_msg($errno, $msg));
    $this->_connect_try_next;
}

sub _connect_error { shift->_connect_warn_or_error('error', @_); }
sub _connect_warn { shift->_connect_warn_or_error('warn', @_); }

sub _connect_warn_or_error {
    my $this = shift;
    my $method = '_'.shift;
    my $str = shift;
    if (defined $str) {
	$str = ': ' . $str;
    } else {
	$str = '';
    }

    $this->$method("Couldn't connect to ".$this->destination.$str);
}

sub destination {
    my $this = shift;

    $this->repr_destination(
	host => $this->host,
	addr => $this->current_addr,
	port => $this->current_port,
	type => $this->current_type);
}

sub current_addr {
    my $this = shift;

    utils->get_first_defined(
	$this->{connecting}->{addr},
	$this->addr);
}

sub current_port {
    my $this = shift;

    utils->get_first_defined(
	$this->{connecting}->{port},
	$this->port);
}

sub current_type {
    my $this = shift;

    $this->{connecting}->{type};
}

sub _error {
    # connection error; and finish ->connect chain
    my ($this, $msg) = @_;

    $this->callback->('error', $this, $msg);
}

sub _warn {
    # connection warning; but continue trying
    my ($this, $msg) = @_;

    $this->callback->('warn', $this, $msg);
}

sub _call {
    # connection successful
    my $this = shift;

    $this->callback->('sock', $this, $this->sock);
}

sub cleanup {
    my $this = shift;

    if ($this->installed) {
	$this->uninstall;
    }
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }
}

sub interrupt {
    my ($this, $genre) = @_;

    $this->cleanup;
    if (defined $this->sock) {
	$this->close;
    }
    $genre = 'interrupt' unless defined $genre;
    $this->callback->($genre, $this);
}

sub want_to_write {
    1;
}

sub write { shift->proc_sock }
sub read { shift->proc_sock }
sub exception { shift->_handle_sock_error }

sub proc_sock {
    my $this = shift;

    my $select = IO::Select->new($this->sock);
    if (!$select->can_write(0)) {
	my $error = $this->sock->sockopt(SO_ERROR);
	$this->cleanup;
	$this->close;
	$this->_connect_warn_try_next($error, 'cant write');
    } elsif (!$this->sock->connect($this->{connecting}->{saddr})) {
	if ($!{EISCONN} ||
		($this->_is_winsock && (($! == 10022) || $!{EWOULDBLOCK} ||
					    $!{EALREADY}))) {
	    $this->cleanup;
	    $this->_call;
	} else {
	    $this->_warn($this->sock_errno_to_msg($!, 'connection try error'));
	    $this->_handle_sock_error;
	}
    } else {
	$this->_warn('connect successful, why called this?');
    }
}

sub _handle_sock_error {
    my $this = shift;

    my $error = $this->sock->sockopt(SO_ERROR);
    $this->cleanup;
    $this->close;
    $this->_connect_warn_try_next($error);
}

1;
