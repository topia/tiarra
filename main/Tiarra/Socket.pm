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

sub _should_define {
    die 'method should define! ('.shift->name.')';
}

sub want_to_write { shift->_should_define }
sub write { shift->_should_define }
sub read { shift->_should_define }

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

sub _increment_caller {
    my ($class_or_this, $subject, $opts) = @_;

    $opts->{_caller} = ($opts->{_caller} || 0) + 1;
    $opts->{_subject} = utils->get_first_defined(
	$opts->{_subject},
	$subject);
    $opts;
}

1;
