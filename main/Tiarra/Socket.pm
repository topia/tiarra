# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Socket Wrapper
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket;
use strict;
use warnings;
use Carp;
use Tiarra::Utils;
use RunLoop;
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

sub _should_define {
    die 'method should define! ('.shift->name.')';
}

sub want_to_write { shift->_should_define }
sub write { shift->_should_define }
sub read { shift->_should_define }

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
		     utils->get_first_defined($data{host}),
		     ((defined $data{addr} && $data{host} ne $data{addr}) ?
			  "($data{addr})" : '')),
		utils->get_first_defined($data{port}));
    if (length $str) {
	$str .= " ($data{type})" if defined $data{type};
    } else {
	$str .= utils->to_str($data{type});
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

sub _increment_caller {
    my ($class_or_this, $subject, $opts) = @_;

    $opts->{_caller} = ($opts->{_caller} || 0) + 1;
    $opts->{_subject} = utils->get_first_defined(
	$opts->{_subject},
	$subject);
    $opts;
}

1;
