# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Socket Wrapper
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket;
use strict;
use warnings;
use Tiarra::Utils;
use base qw(Tiarra::Utils);

sub repr_destination {
    my ($class_or_this, %data) = @_;

    if (!defined $data{host} && defined $data{addr}) {
	$data{host} = $data{addr};
    }

    my $str = '';
    # $put(str,%host%$if($not($strcmp(%host%,%addr%)),'('%addr%')'))
    # $if($get(str),$puts(str_started,1))
    # $put(str,$if($or($get(str_started),%port%),/)%port)
    # $if($get(str),$puts(str_started,1))
    # $put(str,$if(%type%,
    # $if($get(str_started),' (')
    # %type%
    # $if($get(str_started),' (')))
    $str = join('/',
		join('',
		     $class_or_this->get_first_defined($data{host}),
		     ((defined $data{addr} && $data{host} ne $data{addr}) ?
			  "($data{addr})" : '')),
		$class_or_this->get_first_defined($data{port}));
    if (length $str) {
	$str .= " ($data{type})" if defined $data{type};
    } else {
	$str .= $class_or_this->to_str($data{type});
    }
    $str;
}

sub probe_type_by_class {
    my ($class_or_this, $obj) = @_;

    map {
	if (!wantarray) {
	    return $_->[1];
	} else {
	    $_->[1];
	}
    } grep {
	UNIVERSAL::isa($obj, $_->[0]);
    } map {
	substr($_->[0],0,0) = 'IO::Socket::';
	$_;
    } ([qw(UNIX Unix)], [qw(INET6 IPv6)], [qw(INET IPv4)]);
}

package Tiarra::Socket::Connect;
use strict;
use warnings;
use Carp;
use Tiarra::Resolver;
use Timer;
use base qw(Tiarra::Socket);
__PACKAGE__->define_attr_getter(0, qw(sock installed));
__PACKAGE__->define_attr_accessor(0, qw(host addr port callback),
				  qw(bind_addr prefer timeout),
				  qw(retry_int));

sub new {
    my ($class, %opts) = @_;

    my $this = {
	runloop => $opts{runloop},
	host => $opts{host},
	addr => $opts{addr},
	port => $opts{port},
	prefer => $class->get_first_defined($opts{prefer},
					    [qw(ipv6 ipv4)]),
	callback => $opts{callback},
	queue => [],
	bind_addr => $opts{bind_addr},
	installed => 0,
	timeout => $opts{timeout},
	retry_int => $opts{retry},
    };
    bless $this, $class;
    $this->connect;
}

sub runloop {
    my $this = shift;

    $this->get_first_defined($this->{runloop}, RunLoop->shared);
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
    Tiarra::Resolver->resolve('addr', $this->get_first_defined(
	$this->addr, $this->host), sub {
	    eval {
		$this->_connect_stage(@_);
	    }; if ($@) {
		$this->_connect_error("internal error: $@");
	    }
	});
    $this;
}

sub _connect_stage {
    my ($this, $entry) = @_;

    my %addrs_by_types;

    if ($entry->answer_status eq $entry->ANSWER_OK) {
	foreach my $addr (@{$entry->answer_data}) {
	    if ($addr =~ m/^(?:\d+\.){3}\d+$/) {
		push (@{$addrs_by_types{ipv4}}, $addr);
	    } elsif ($addr =~ m/^[0-9a-fA-F:]+$/) {
		push (@{$addrs_by_types{ipv6}}, $addr);
	    } else {
		die "unsupported addr type: $addr";
	    }
	}
    } else {
	$this->_connect_error("couldn't resolve hostname");
	return undef; # end
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

    my %additional = ();
    if (defined $this->{bind_addr}) {
	$additional{LocalAddr} = $this->{bind_addr};
    }
    $this->_try_connect_tcp('IO::Socket::INET', %additional);
}

sub _try_connect_ipv6 {
    my $this = shift;

    my %additional;
    if (defined $this->{bind_addr}) {
	$additional{LocalAddr} = $this->{bind_addr};
    }

    if (!::ipv6_enabled) {
	$this->_error(
	    die qq{Host $this->{host} seems to be an IPv6 address, }.
		qq{but IPv6 support is not enabled. }.
		    qq{Use IPv4 server or install Socket6.pm if possible.\n});
    }

    $this->_try_connect_tcp('IO::Socket::INET6', %additional);
}

sub _try_connect_tcp {
    my $this = shift;

    $this->_try_connect_io_socket(@_,
				  Proto => 'tcp');
}

sub _try_connect_io_socket {
    my ($this, $package, %additional) = @_;

    # ソケットを開く。開けなかったらdie。
    # 接続は次のようにして行なう。
    # 1. ホストがIPv4アドレスであれば、IPv4として接続を試みる。
    # 2. ホストがIPv6アドレスであれば、IPv6として接続を試みる。
    # 3. どちらの形式でもない(つまりホスト名)であれば、
    #    a. IPv6が利用可能ならIPv6での接続を試みた後、駄目ならIPv4にフォールバック
    #    b. IPv6が利用可能でなければ、最初からIPv4での接続を試みる。
    my @new_socket_args = (
	PeerAddr => $this->{connecting}->{addr},
	PeerPort => $this->{connecting}->{port},
	Timeout => undef,
	%additional,
    );

    my $sock = $package->new(@new_socket_args);
    my $error = $!;
    if (defined $sock) {
	$this->{sock} = $sock;
	$! = $error;
	if ($!{EINPROGRESS}) {
	    $this->_install;
	} else {
	    $this->_call;
	}
    } else {
	$this->_connect_error_try_next($error);
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
	addr => $this->get_first_defined(
	    $this->{connecting}->{addr},
	    $this->addr),
	port => $this->get_first_defined(
	    $this->{connecting}->{port},
	    $this->port),
	type => $this->type_name);
}

sub type_name {
    my $this = shift;
    my $type = $this->{connecting}->{type};
    if (!defined $type) {
	return undef;
	} elsif ($type =~ /^ipv(\d)+$/) {
	return "IPv$1";
    } else {
	return "unknown: $type";
    }
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
	$this->_uninstall;
    }
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }
}

sub interrupt {
    my $this = shift;

    $this->cleanup;
    if (defined $this->{sock}) {
	$this->{sock}->shutdown(2);
	$this->{sock} = undef;
    }
    $this->callback->('interrupt', $this);
}

sub _install {
    my $this = shift;

    if ($this->{installed}) {
	croak "already installed; module bug?";
    }

    $this->runloop->install_socket($this);
    $this->{installed} = 1;
    $this;
}

sub _uninstall {
    my $this = shift;

    if (!$this->{installed}) {
	croak "already uninstalled; module bug?";
    }

    $this->runloop->uninstall_socket($this);
    $this->{installed} = 0;
    $this;
}

sub want_to_write {
    1;
}

sub write {
    my $this = shift;
    $this->cleanup;
    $this->call;
}

sub read {
    my $this = shift;
    croak "->read should be stub method!";
}

1;
