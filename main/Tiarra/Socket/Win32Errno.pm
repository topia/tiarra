# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Win32 (Winsock2) Errno to message formatter
# why we cannot use 'local $@ = errno; "$@"' ?
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket::Win32Errno;
use strict;
use warnings;
use Tiarra::SharedMixin;
use Errno;
use Tiarra::Utils;
our %descriptions;

sub _new {
    return __PACKAGE__;
}


BEGIN {
    my @data = split /\n/, <<__YAML__;
--- !tiarra.org/misc^win32-errno-messages
EWOULDBLOCK: Resource temporarily unavailable.
EINPROGRESS: Operation now in progress
EALREADY: Operation already in progress
ENOTSOCK: Socket operation on nonsocket
EDESTADDRREQ: Destination address required
EMSGSIZE: Message too long
EPROTOTYPE: Protocol wrong type for socket
ENOPROTOOPT: Bad protocol option
EPROTONOSUPPORT: Protocol not supported
EOPNOTSUPP: Operation not supported
EPFNOSUPPORT: Protocol family not supported
EAFNOSUPPORT: Address family not supported by protocol family
EADDRINUSE: Address already in use
EADDRNOTAVAIL: Cannot assign requested address
ENETDOWN: Network is down
ENETUNREACH: Network is unreachable
ENETRESET: Network dropped connection on reset
ECONNABORTED: Software caused connection abort
ECONNRESET: Connection reset by peer
ENOBUFS: No buffer space available
EISCONN: Socket is already connected
ENOTCONN: Socket is not connected
ESHUTDOWN: Cannot send after socket shutdown
ETIMEDOUT: Connection timed out
ECONNREFUSED: Connection refused
EHOSTDOWN: Host is down
EHOSTUNREACH: No route to host
EPROCLIM: Too many processes
...
__YAML__
    # strip yaml header/footer
    shift @data;pop @data;
    %descriptions = ();
    my ($name, $description, $value);
    map {
	($name, $description) = split(/: /, $_, 2);
	if (defined $name && exists $!{$name}) {
	    $value = Errno->$name;
	    $descriptions{$value} = $description;
	}
	();
    } @data;
}

sub fetch_description {
    my ($class_or_this, $number) = @_;

    $descriptions{$number};
}

1;
