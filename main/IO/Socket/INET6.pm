# -----------------------------------------------------------------------------
# $Id: INET6.pm,v 1.1 2003/05/24 04:41:44 admin Exp $
# -----------------------------------------------------------------------------
# IO::Socket::INETをSocket6.pmに移植したものです。
# オリジナルはあくまでIO::Socket::INETです。
# -----------------------------------------------------------------------------
package IO::Socket::INET6;
use strict;
use base qw(IO::Socket);
use Socket;
use Socket6;
use Carp;
use Exporter;
use Errno;
our $VERSION = "0.0.1";

my $EINVAL = exists(&Errno::EINVAL) ? Errno::EINVAL() : 1;

IO::Socket::INET6->register_domain( AF_INET6 );

my %socket_type = ( tcp  => SOCK_STREAM,
		    udp  => SOCK_DGRAM,
		    icmp => SOCK_RAW
		  );

sub new {
    my $class = shift;
    unshift(@_, "PeerAddr") if @_ == 1;
    return $class->SUPER::new(@_);
}

sub _sock_info {
  my($addr,$port,$proto) = @_;
  my @proto = ();
  my @serv = ();

  # v4での192.168.0.1:8080のような指定は出来ない。
#  $port = $1
#	if(defined $addr && $addr =~ s,:([\w\(\)/]+)$,,);

  if(defined $proto) {
    if (@proto = ( $proto =~ m,\D,
		? getprotobyname($proto)
		: getprotobynumber($proto))
    ) {
      $proto = $proto[2] || undef;
    }
    else {
      $@ = "Bad protocol '$proto'";
      return;
    }
  }

  if(defined $port) {
    $port =~ s,\((\d+)\)$,,;

    my $defport = $1 || undef;
    my $pnum = ($port =~ m,^(\d+)$,)[0];

    if ($port =~ m,\D,) {
      unless (@serv = getservbyname($port, $proto[0] || "")) {
	$@ = "Bad service '$port'";
	return;
      }
    }

    $port = $pnum || $serv[2] || $defport || undef;

    $proto = (getprotobyname($serv[3]))[2] || undef
	if @serv && !$proto;
  }

 return ($addr || undef,
	 $port || undef,
	 $proto || undef
	);
}

sub _error {
    my $sock = shift;
    my $err = shift;
    {
      local($!);
      $@ = join("",ref($sock),": ",@_);
      close($sock)
	if(defined fileno($sock));
    }
    $! = $err;
    return undef;
}

sub _get_addr {
    my($sock,$addr_str, $multi) = @_;
    my @addr;
#    if ($multi && $addr_str !~ /^\d+(?:\.\d+){3}$/) {
	(undef, undef, undef, undef, @addr) = gethostbyname2($addr_str,AF_INET6);
#    } else {
#	my $h = inet_aton($addr_str);
#	push(@addr, $h) if defined $h;
#    }
    @addr;
}

sub configure {
    my($sock,$arg) = @_;
    my($lport,$rport,$laddr,$raddr,$proto,$type);


    $arg->{LocalAddr} = $arg->{LocalHost}
	if exists $arg->{LocalHost} && !exists $arg->{LocalAddr};

    ($laddr,$lport,$proto) = _sock_info($arg->{LocalAddr},
					$arg->{LocalPort},
					$arg->{Proto})
			or return _error($sock, $!, $@);

    $laddr = defined $laddr ? inet_pton(AF_INET6,$laddr)
			    : in6addr_any;

    return _error($sock, $EINVAL, "Bad hostname '",$arg->{LocalAddr},"'")
	unless(defined $laddr);

    $arg->{PeerAddr} = $arg->{PeerHost}
	if exists $arg->{PeerHost} && !exists $arg->{PeerAddr};

    unless(exists $arg->{Listen}) {
	($raddr,$rport,$proto) = _sock_info($arg->{PeerAddr},
					    $arg->{PeerPort},
					    $proto)
			or return _error($sock, $!, $@);
    }

    $proto ||= (getprotobyname('tcp'))[2];

    my $pname = (getprotobynumber($proto))[0];
    $type = $arg->{Type} || $socket_type{$pname};

    my @raddr = ();

    if(defined $raddr) {
	@raddr = $sock->_get_addr($raddr, $arg->{MultiHomed});
	return _error($sock, $EINVAL, "Bad hostname '",$arg->{PeerAddr},"'")
	    unless @raddr;
    }

    while(1) {

	$sock->socket(AF_INET6, $type, $proto) or
	    return _error($sock, $!, "$!");

	if ($arg->{Reuse}) {
	    $sock->sockopt(SO_REUSEADDR,1) or
		    return _error($sock, $!, "$!");
	}

	if($lport || ($laddr ne in6addr_any) || exists $arg->{Listen}) {
	    $sock->bind($lport || 0, $laddr) or
		    return _error($sock, $!, "$!");
	}

	if(exists $arg->{Listen}) {
	    $sock->listen($arg->{Listen} || 5) or
		return _error($sock, $!, "$!");
	    last;
	}

 	# don't try to connect unless we're given a PeerAddr
 	last unless exists($arg->{PeerAddr});
 
        $raddr = shift @raddr;

	return _error($sock, $EINVAL, 'Cannot determine remote port')
		unless($rport || $type == SOCK_DGRAM || $type == SOCK_RAW);

	last
	    unless($type == SOCK_STREAM || defined $raddr);

	return _error($sock, $EINVAL, "Bad hostname '",$arg->{PeerAddr},"'")
	    unless defined $raddr;

#        my $timeout = ${*$sock}{'io_socket_timeout'};
#        my $before = time() if $timeout;

        if ($sock->connect(pack_sockaddr_in6($rport, $raddr))) {
#            ${*$sock}{'io_socket_timeout'} = $timeout;
            return $sock;
        }

	return _error($sock, $!, "Timeout")
	    unless @raddr;

#	if ($timeout) {
#	    my $new_timeout = $timeout - (time() - $before);
#	    return _error($sock,
#                         (exists(&Errno::ETIMEDOUT) ? Errno::ETIMEDOUT() : $EINVAL),
#                         "Timeout") if $new_timeout <= 0;
#	    ${*$sock}{'io_socket_timeout'} = $new_timeout;
#        }

    }

    $sock;
}

sub connect {
    @_ == 2 || @_ == 3 or
       croak 'usage: $sock->connect(NAME) or $sock->connect(PORT, ADDR)';
    my $sock = shift;
    return $sock->SUPER::connect(@_ == 1 ? shift : pack_sockaddr_in6(@_));
}

sub bind {
    @_ == 2 || @_ == 3 or
       croak 'usage: $sock->bind(NAME) or $sock->bind(PORT, ADDR)';
    my $sock = shift;
    return $sock->SUPER::bind(@_ == 1 ? shift : pack_sockaddr_in6(@_))
}

sub sockaddr {
    @_ == 1 or croak 'usage: $sock->sockaddr()';
    my($sock) = @_;
    my $name = $sock->sockname;
    $name ? (sockaddr_in6($name))[1] : undef;
}

sub sockport {
    @_ == 1 or croak 'usage: $sock->sockport()';
    my($sock) = @_;
    my $name = $sock->sockname;
    $name ? (sockaddr_in6($name))[0] : undef;
}

sub sockhost {
    @_ == 1 or croak 'usage: $sock->sockhost()';
    my($sock) = @_;
    my $addr = $sock->sockaddr;
    $addr ? inet_ntop(AF_INET6,$addr) : undef;
}

sub peeraddr {
    @_ == 1 or croak 'usage: $sock->peeraddr()';
    my($sock) = @_;
    my $name = $sock->peername;
    $name ? (sockaddr_in6($name))[1] : undef;
}

sub peerport {
    @_ == 1 or croak 'usage: $sock->peerport()';
    my($sock) = @_;
    my $name = $sock->peername;
    $name ? (sockaddr_in6($name))[0] : undef;
}

sub peerhost {
    @_ == 1 or croak 'usage: $sock->peerhost()';
    my($sock) = @_;
    my $addr = $sock->peeraddr;
    $addr ? inet_ntop(AF_INET6,$addr) : undef;
}

1;
