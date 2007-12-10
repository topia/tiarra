# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Socket Wrapper
# 注意: Win32 環境では Socket 以外のファイルハンドル等に select を使えません。
# (see perlport)
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket;
use strict;
use warnings;
use Carp;
use Tiarra::Utils;
use RunLoop;
use Socket;
our $is_winsock = $^O =~ /^MSWin32/;
utils->define_attr_getter(0, qw(sock installed));
utils->define_attr_accessor(0, qw(name),
			    map { ["_$_", $_] }
				qw(sock installed));

sub new {
    my ($class, %opts) = @_;

    my $this = {
	runloop => $opts{runloop},
	installed => 0,
	sock => undef,
	name => utils->get_first_defined(
	    $opts{name},
	    utils->simple_caller_formatter(
		utils->get_first_defined($opts{_subject}, 'socket').' registered',
		($opts{_caller} || 0))),
    };
    bless $this, $class;
}

sub runloop {
    my $this = shift;

    utils->get_first_defined($this->{runloop}, RunLoop->shared);
}

sub attach {
    my ($this, $sock) = @_;

    if ($this->installed) {
	croak "already installed; can't attach!";
    }

    return undef unless defined $sock;
    $sock->autoflush(1);
    $this->_sock($sock);
    $this;
}

sub detach {
    my $this = shift;

    if (!defined $this->sock) {
	croak "already detached; can't detach!";
    }
    if ($this->installed) {
	carp "installed; anyway detach...";
	$this->uninstall;
    }

    $this->_sock(undef);
    $this;
}

sub close {
    my $this = shift;

    if (!defined $this->sock) {
	croak "already detached; can't close!";
    }

    $this->shutdown(2);
    $this->detach;
}

sub shutdown {
    my ($this, $type) = @_;

    if (!defined $this->sock) {
	croak "already detached; can't shutdown!";
    }

    $this->sock->shutdown($type);
}

sub install {
    my $this = shift;

    if ($this->installed) {
	croak "already installed; module bug?";
    }

    $this->runloop->install_socket($this);
    $this->_installed(1);
    $this;
}

sub uninstall {
    my $this = shift;

    if (!$this->installed) {
	croak "already uninstalled; module bug?";
    }

    $this->runloop->uninstall_socket($this);
    $this->_installed(0);
    $this;
}

sub errno {
    my $this = shift;

    if (!defined $this->sock) {
	croak "already detached; can't fetch errno!";
    }

    my $errno = $this->sock->sockopt(SO_ERROR);
    if ($errno == 0 || $errno == -1) {
	$errno = undef;
    }
    return $errno;
}

sub errmsg {
    my $this = shift;
    my $errno = $this->errno;
    my $msg = undef;

    if (defined $errno) {
	$msg = $this->sock_errno_to_msg($errno, @_);
    }
    if (wantarray) {
	($msg, $errno);
    } else {
	$msg;
    }
}

sub _should_define {
    die 'method should define! ('.shift->name.')';
}

sub want_to_write { shift->_should_define }
sub write { shift->_should_define }
sub read { shift->_should_define }
sub exception { shift->_should_define }

# class method

sub repr_destination {
    my ($class_or_this, %data) = @_;

    if (!defined $data{host} && defined $data{addr}) {
	$data{host} = $data{addr};
	delete $data{addr};
    }
    if (defined $data{host} && defined $data{addr} &&
	    $data{host} eq $data{addr}) {
	delete $data{addr};
    }

    my $str = '';
    my $append_as_delimiter = sub {
	$str .= shift if length $str;
    };
    $str .= utils->to_str($data{host});
    $str .= "($data{addr})" if defined $data{addr};
    if (defined $data{port}) {
	$append_as_delimiter->('/');
	$str .= $data{port};
    }
    if (defined $data{type}) {
	$append_as_delimiter->(' (');
	$str .= $class_or_this->repr_type($data{type}) .
	    (length $str ? ')' : '');
    }
    $str;
}

sub repr_type {
    my ($class_or_this, $type) = @_;

    if ($type =~ /^ipv(\d+)$/i) {
	return "IPv$1";
    } elsif ($type =~ /^unix$/i) {
	return "Unix";
    } else {
	return "Unknown: $type";
    }
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
    } ([qw(INET ipv4)], [qw(INET6 ipv6)], [qw(UNIX unix)]);
}

sub probe_type_by_addr {
    my ($class_or_this, $addr) = @_;

    if ($addr =~ m/^(?:\d+\.){3}\d+$/) {
	return 'ipv4';
    } elsif ($addr =~ m/^[0-9a-fA-F:]+$/) {
	return 'ipv6';
    } else {
	# maybe
	return 'unix';
    }

}

sub sock_errno_to_msg {
    my ($this, $errno, $msg) = @_;

    local $! = $errno;
    $errno = ($!+0);
    my $errstr = "$!";
    if ($! eq 'Unknown error' && $this->_is_winsock) {
	# try probe (for my ActivePerl v5.8.4 build 810)
	require Tiarra::Socket::Win32Errno;
	my $new_errstr = Tiarra::Socket::Win32Errno->fetch_description($errno);
	if (defined $new_errstr) {
	    $errstr = $new_errstr;
	}
    }
    return ((defined $msg && length $msg) ? ($msg . ': ') : '' ) .
	"$errno: $errstr";
}

sub _is_winsock {
    return $is_winsock;
}

sub _increment_caller {
    my ($class_or_this, $subject, $opts) = @_;

    $opts->{_caller} = ($opts->{_caller} || 0) + 1;
    $opts->{_subject} = utils->get_first_defined(
	$opts->{_subject},
	$subject);
    $opts;
}

1;

=pod

=head1 NAME

Tiarra::Socket - Tiarra RunLoop based Socket Handler Base Class

=head1 SYNOPSIS

=over

=item use L<Tiarra::Socket>

 use Tiarra::Socket;
 $socket = Tiarra::Socket->new(name => 'sample socket');
 $socket->attach($sock);
 $socket->install;
 $socket->uninstall;
 $socket->shutdown(2);
 $socket->detach;
 $socket->close;
 $errno = $socket->errno;
 $msg = $socket->errmsg( [$additional_msg] );
 $type = Tiarra::Socket->probe_type_by_class($sock);
 $type = Tiarra::Socket->probe_type_by_addr($addr);
 Tiarra::Socket->repr_type( $type );
 Tiarra::Socket->repr_destination( [datas] );
 $is_winsock = Tiarra::Socket->_is_winsock;
 $msg = Tiarra::Socket->sock_errno_to_msg($errno[, $additional_msg]);

=item make subclass of L<Tiarra::Socket>

 package Tiarra::SomeSocket;
 use Tiarra::Socket;
 use base qw(Tiarra::Socket);

 sub new {
   my ($class, %opts) = @_;

   $class->_increment_caller('some-socket', \%opts);
   my $this = $class->SUPER::new(%opts);
   $this;
 }
 # some overrides and implements...

=back

=head1 DESCRIPTION

L<Tiarra::Socket> provides RunLoop based event driven Socket I/O interface.

=head1 CONSTRUCTOR

=over

=item C<< $socket = new( [OPTS] ) >>

opts is options hash.
parametors:

 runloop  Tiarra RunLoop
 name     Socket name for pretty-print

=back

=head1 METHODS

=over

=item C<< ->runloop >>

return default runloop or specified runloop

=item C<< ->attach >>

attach sock to socket

=item C<< ->detach >>

detach sock from socket

=item C<< ->close >>

shutdown and detach socket

=item C<< ->shutdown( HOW ) >>

call shutdown for this socket.

=item C<< ->install >>

install socket to runloop

=item C<< ->uninstall >>

uninstall socket from runloop

=item C<< ->sock >>

return sock attached to socket

=item C<< ->installed >>

return true if socket installed to runloop

=item C<< ->errno >>

return socket errno with sockopt(and clear status).
if errno not set, return undef.

=item C<< ->errmsg( [MESSAGE] ) >>

return socket error message with msg.
on array context, return $errno as 2nd item, also.

(implement likes
C<< $this->sock_errno_to_msg($this->errno, [MESSAGE] ) >>.)

=back

=head1 CLASS METHODS

=over

=item C<< ->repr_destination( [DATAS] ) >>

representation destination with DATAS hash.
currently supported hash key:

=over

=item host

hostname(maybe FQDN).

=item addr

Address(IPv[46] Address).

=item port

Port or UNIX Domain Socket path.

=item type

Socket type. try repr inside, you haven't necessary call C<< ->repr_type >>.

=back

=item C<< ->repr_type( TYPE ) >>

Simple Pretty-printing type. such as:

 ipv4 -> IPv4
 ipv6 -> IPv6
 unix -> Unix

=item C<< ->probe_type_by_class( CLASS_OR_OBJECT ) >>

Probe type by class or object.

=item C<< ->probe_type_by_addr( ADDRESS ) >>

Probe type by address.

=item C<< ->sock_errno_to_msg( ERRNO[, MESSAGE] ) >>

representation sock errno and message.

=back

=head1 METHODS OF PLEASE OVERRIDE BY SUBCLASS

=over

=item C<< ->want_to_write >>

return true(1) on want to write(write buffer has data)

=item C<< ->write >>

called when select notified this socket is writable.

=item C<< ->read >>

called when select notified this socket is readable.

=item C<< ->exception >>

called when select notified this socket has exception.

=back

=head1 SEE ALSO

L<Tiarra::Socket::Connect>: socket connector.

L<Tiarra::Socket::Buffered>, L<Tiarra::Socket::Lined>: reader/writer.

L<Tiarra::Socket::Win32Errno>: Win32 errno database.

=head1 COPYRIGHT AND DISCLAIMERS

Copyright (c) 2004 Topia. All rights reserved.

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=head1 AUTHOR

Topia, and originally developed by phonohawk.

=cut
