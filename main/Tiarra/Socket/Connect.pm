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
			    qw(retry_int));
utils->define_attr_enum_accessor('domain', 'eq',
				 qw(tcp unix));

# now supported tcp, unix

sub new {
    my ($class, %opts) = @_;

    $class->_increment_caller('socket-connector', \%opts);
    my $this = $class->SUPER::new(%opts);
    map {
	$this->$_($opts{$_});
    } qw(host addr port callback bind_addr timeout);
    $this->retry_int($opts{retry});
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
		$this->cleanup;
		$this->_connect_error('timeout');
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
	$this->_connect_error("couldn't resolve hostname");
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
	$this->_connect_error('all dead');
	if ($this->retry_int) {
	    $this->{timer} = Timer->new(
		After => $this->retry_int,
		Code => sub {
		    $this->cleanup;
		    $this->connect;
		});
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
	$this->_warn("Couldn't prepare socket");
	$this->_connect_try_next;
	return;
    }
    if (!defined $sock->blocking(0)) {
	# effect only on connecting; comment out
	#$this->_warn('cannot blocking') if ::debug_mode();
    }
    my $saddr = Tiarra::Resolver->resolve(
	'saddr', [$this->current_addr, $this->current_port],
	sub {}, 0);
    $this->{connecting}->{saddr} = $saddr->answer_data;
    if ($sock->connect($this->{connecting}->{saddr})) {
	my $error = $!;
	$this->attach($sock);
	$! = $error;
	if ($!{EINPROGRESS}) {
	    $this->install;
	} else {
	    $this->_call;
	}
    } else {
	$this->_connect_error_try_next($this->_errno_to_msg($!));
    }
}

sub _errno_to_msg {
    my ($this, $errno) = @_;

    $! = $errno;
    $errno = ($!+0);
    my $errstr = "$!";
    if ($! eq 'Unknown error') {
	# try probe (for my ActivePerl v5.8.4 build 810)
	if ($!{ETIMEDOUT}) {
	    $errstr = 'Connection timed out';
	} elsif ($!{ECONNREFUSED}) {
	    $errstr = 'Connection refused';
	}
    }
    return "$errno: $errstr";
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
	$this->_connect_error_try_next($this->_errno_to_msg($!));
    }
}

sub _connect_error_try_next {
    my ($this, $msg) = @_;

    $this->_connect_warn($msg);
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
    my ($this, $msg) = @_;

    $this->callback->('error', $this, $msg);
}

sub _warn {
    my ($this, $msg) = @_;

    $this->callback->('warn', $this, $msg);
}

sub _call {
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
    my $this = shift;

    $this->cleanup;
    if (defined $this->sock) {
	$this->close;
    }
    $this->callback->('interrupt', $this);
}

sub want_to_write {
    1;
}

sub write { shift->proc_sock }
sub read { shift->proc_sock }

sub proc_sock {
    my $this = shift;

    my $select = IO::Select->new($this->sock);
    if (!$select->can_write(0)) {
	my $error = $this->sock->sockopt(SO_ERROR);
	$this->cleanup;
	$this->close;
	$this->_connect_error_try_next($this->_errno_to_msg($error));
    } elsif ($this->sock->connect($this->{connecting}->{saddr}) || $!{EISCONN}) {
	$this->cleanup;
	$this->_call;
    } else {
	my $error = $this->sock->sockopt(SO_ERROR);
	$this->cleanup;
	$this->close;
	$this->_connect_error_try_next($this->_errno_to_msg($error));
    }
}

1;
