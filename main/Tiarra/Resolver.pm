# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Simple Resolver with multi-thread or blocking.
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Resolver::QueueData;
use strict;
use warnings;
use Tiarra::DefineEnumMixin (qw(ID TIMEOUT),
			     qw(QUERY_TYPE QUERY_DATA ANSWER_STATUS ANSWER_DATA));
use Tiarra::DefineEnumMixin (qw(ANSWER_OK ANSWER_NOT_FOUND ANSWER_TIMEOUT),
			     qw(ANSWER_NOT_SUPPORTED ANSWER_INTERNAL_ERROR));
use Tiarra::Utils;
Tiarra::Utils->define_array_attr_accessor(
    0, qw(id timeout query_type query_data answer_status answer_data));

# attributes:
#   timeout: not implemented yet
#   query_type: resolver dependant data
#   query_data: resolver dependant data
#   answer_status: status
#     * ANSWER_OK: resolved
#     * ANSWER_NOT_FOUND: not found
#     * ANSWER_TIMEOUT: timeout (not implemented yet)
#     * ANSWER_NOT_SUPPORTED: not supported type (data: message)
#     * ANSWER_INTERNAL_ERROR: internal error occurred (data: message)
#   answer_data: data

sub new {
    my $class = shift;

    # FIXME: check type/value!
    my $this = [@_];
    bless $this, $class;
    $this;
}

sub serialize {
    my $this = shift;

    my @array : shared = @$this;
    \@array;
}

sub parse {
    my $this = shift;

    ref($this)->new(@{+shift});
}

package Tiarra::Resolver;
use strict;
use warnings;
use Tiarra::OptionalModules;
use Tiarra::SharedMixin;
use Tiarra::WrapMainLoop;
use Tiarra::TerminateManager;
use Socket;
use Carp;
use Net::hostent;
use Tiarra::DefineEnumMixin qw(QUERY_HOST QUERY_ADDR QUERY_SADDR QUERY_NAMEINFO);
my $dataclass = 'Tiarra::Resolver::QueueData';
our $use_threads;
our $use_ipv6;
our $use_threads_state_checking;
BEGIN {
    $use_threads = !$^C && Tiarra::OptionalModules->threads;
    if ($use_threads) {
	require threads;
	require threads::shared;
	require Thread::Queue;
	## threads 1.33 or earlier, not support $thr->is_running()
	$use_threads_state_checking = threads->can('is_running');
    }

    $use_ipv6 = Tiarra::OptionalModules->ipv6;
    if ($use_ipv6) {
	eval 'use Socket6;';
    } else {
	# dummy
	*AI_NUMERICHOST = sub () { undef };
	*NI_NUMERICHOST = sub () { undef };
	*NI_NAMEREQD = sub () { undef };
    }
}

if ($use_threads) {
    # fast initialize(for minimal thread)
    __PACKAGE__->shared;
}

sub init {
    my $this = shift;

    if ($use_threads) {
	$this->{ask_queue} = Thread::Queue->new;
	$this->{reply_queue} = Thread::Queue->new;
	$this->_create_thread();
	$this->{main_timer} = Tiarra::WrapMainLoop->new(
	    type => 'timer',
	    interval => 1,
	    closure => sub {
		$this->mainloop;
	    });
	$this->{main_loop} = Tiarra::WrapMainLoop->new(
	    type => 'mainloop',
	    closure => sub {
		$this->mainloop;
	    });
	$this->{destructor} = Tiarra::TerminateManager::Hook->new(
	    sub {
		$this->destruct;
	    })->install;
    }
    $this->{id} = 0;
    $this->{closures} = {};
    $this;
}

sub _new {
    my $class = shift;

    my $this = {};
    bless $this, $class;
    $this->init;
}

sub _check_thread {
    my $this = shift;

    if (!$use_threads_state_checking ||
	    (defined $this->{thread} &&
		 $this->{thread}->is_running())) {
	return undef;
    }
    $this->_create_thread;
}

sub _create_thread {
    my $this = shift;

    $this->{thread} = threads->create("resolver_thread",
				      ref($this),
				      $this->{ask_queue},
				      $this->{reply_queue});
}

sub destruct {
    my $this = shift;
    my $before_fork = shift;

    if (!$before_fork && defined $this->{destructor}) {
	$this->{destructor}->uninstall;
	$this->{destructor} = undef;
    }
    $this->{ask_queue}->enqueue(undef);
    $this->{thread}->join;
    $this->mainloop;
}

sub resolve {
    my ($class_or_this, $type, $data, $closure, $my_use_threads) = @_;
    my $this = $class_or_this->_this;

    $my_use_threads = $use_threads unless defined $my_use_threads;
    croak 'data not defined; please specify this' unless defined $data;
    croak 'closure not defined; please specify this' unless defined $closure;
    my $entry = $dataclass->new;
    my $do = undef;
    if ($type eq 'addr') {
	# addr: forward lookup
	#   query data: hostname
	#   callback data: [addr1, addr2, ...]
	$entry->query_type(QUERY_ADDR);
	$entry->query_data($data);
	$do = 1;
    } elsif ($type eq 'host') {
	# host: reverse lookup
	#   query data: ip address
	#   callback data: hostname or [host1, host2, ...]
	$entry->query_type(QUERY_HOST);
	$entry->query_data($data);
	$do = 1;
    } elsif ($type eq 'saddr') {
	# saddr: get socket addr
	#   query data: [host, port]
	#   callback data: sockaddr struct
	$entry->query_type(QUERY_SADDR);
	$entry->query_data($data);
	$do = 1;
    } elsif ($type eq 'nameinfo') {
	# nameinfo: get address/port from socket addr
	#   query data: sockaddr struct
	#   callback data: [address, port]
	$entry->query_type(QUERY_NAMEINFO);
	$entry->query_data($data);
	$do = 1;
	$my_use_threads = 0; # thread is not required
    }
    local $use_threads = $my_use_threads;
    if ($do) {
	$entry->timeout(0);
	$entry->id($this->{id}++);
	$this->{closures}->{$entry->id} = $closure;
	if ($use_threads) {
	    $this->_check_thread();
	    $this->{ask_queue}->enqueue($entry->serialize);
	    $this->{main_timer}->lazy_install;
	    $this->{main_loop}->lazy_install;
	    undef;
	} else {
	    $this->_call($this->_resolve($entry));
	}
    } else {
	$entry->answer_status($entry->ANSWER_NOT_SUPPORTED);
	$entry->answer_data("typename '$type' not supported");
	$closure->($entry);
    }
}

sub paranoid_check {
    # ip -> host -> ip check
    # closure: sub {
    #              my ($status, $hostname, $final_result) = @_;
    #              if (!$status) { die "paranoid check failed!"; }
    #              warn "paranoid check successful with: $hostname";
    #              if (defined $final_result) { /* maybe unnecessary */ }
    #          }
    my ($class_or_this, $data, $closure, $my_use_threads) = @_;
    my $this = $class_or_this->_this;

    # stage 1
    $this->resolve(
	'host', $data, sub {
	    eval {
		$this->_paranoid_stage1($data, $closure, $my_use_threads, shift);
	    }; if ($@) {
		$closure->(0, undef);
	    }
	}, $my_use_threads);
}

sub _paranoid_stage1 {
    my ($this, $data, $closure, $my_use_threads, $entry) = @_;

    if ($entry->answer_status eq $entry->ANSWER_OK) {
	my $host = $entry->answer_data;
	if (ref($host) eq 'ARRAY') {
	    # FIXME: support multiple hostname resolved
	    $host = $host->[0];
	}
	$this->resolve(
	    'addr', $host, sub {
		eval {
		    $this->_paranoid_stage2($data, $closure, $my_use_threads, shift);
		}; if ($@) {
		    $closure->(0, undef, $entry);
		}
	    }, $my_use_threads);
    } else {
	$closure->(0, undef, $entry);
    }
}

sub _paranoid_stage2 {
    my ($this, $data, $closure, $my_use_threads, $entry) = @_;

    if ($entry->answer_status eq $entry->ANSWER_OK) {
	if (grep { $data eq $_ } @{$entry->answer_data}) {
	    $closure->(1, $entry->query_data, $entry);
	}
    } else {
	$closure->(0, undef, $entry);
    }
}

sub _call {
    my ($this, $entry) = @_;

    my $id = $entry->id;
    eval { $this->{closures}->{$id}->($entry); };
    if ($@) { ::printmsg($@); }
    delete $this->{closures}->{$id};
    if (!%{$this->{closures}} && $use_threads) {
	$this->{main_timer}->lazy_uninstall;
	$this->{main_loop}->lazy_uninstall;
    }
    $entry;
}

sub _resolve {
    my ($class_or_this, $entry) = @_;

    my $resolved = undef;
    my $ret = undef;

    if ($entry->query_type eq QUERY_ADDR) {
	my @addrs;
	threads::shared::share(@addrs) if $use_threads;

	if ( $^O =~ /^MSWin32/ && $entry->query_data eq 'localhost' ) {
	    # Win2kだとなぜか問い合わせに失敗するので固定応答.
	    @addrs = ('127.0.0.1');
	    if ($use_ipv6) {
		push(@addrs, '::1');
	    }
	    $resolved = 1;
	}
	if ($use_ipv6 && !$resolved) {
	    my @res = getaddrinfo($entry->query_data, 0, AF_UNSPEC, SOCK_STREAM);
	    my ($saddr, $addr, %addrs);
	    while (scalar(@res) >= 5) {
		# check proto,... etc
		(undef, undef, undef, $saddr, undef, @res) = @res;
		($addr, undef) = getnameinfo($saddr, NI_NUMERICHOST);
		if (defined $addr && !$addrs{$addr}) {
		    $addrs{$addr} = 1;
		    push(@addrs, $addr);
		}
	    }
	    if (@addrs) {
		$resolved = 1;
	    }
	}
	if (!$resolved) {
	    my $hostent = Net::hostent::gethost($entry->query_data);
	    if (defined $hostent) {
		#$entry->answer_data($hostent->addr_list);
		@addrs = map {
		    inet_ntoa($_);
		} @{$hostent->addr_list};
		$resolved = 1;
	    }
	}

	if ($resolved) {
	    $entry->answer_data(\@addrs);
	}
    } elsif ($entry->query_type eq QUERY_HOST) {
	my @hosts;
	threads::shared::share(@hosts) if $use_threads;

	if ( $^O =~ /^MSWin32/ && $entry->query_data eq '127.0.0.1' ) {
		# Win2kだとなぜか問い合わせに失敗するので固定応答.
		@hosts = ('localhost');
		$resolved = 1;
	}
	if ($use_ipv6 && !$resolved) {
	    my @res = getaddrinfo($entry->query_data, 0, AF_UNSPEC, SOCK_STREAM);
	    my ($saddr, $host, %hosts);
	    while (scalar(@res) >= 5) {
		# check proto,... etc
		(undef, undef, undef, $saddr, undef, @res) = @res;
		($host, undef) = getnameinfo($saddr, NI_NAMEREQD);
		if (defined $host && !$hosts{$host}) {
		    $hosts{$host} = 1;
		    push(@hosts, $host);
		}
	    }
	    if (@hosts) {
		$resolved = 1;
	    }
	}
	if (!$resolved) {
	    my $hostent = Net::hostent::gethost($entry->query_data);
	    if (defined $hostent) {
		@hosts = ($hostent->name);
		$resolved = 1;
	    }
	}

	if ($resolved) {
	    $entry->answer_data(@hosts == 1 ? $hosts[0] : \@hosts);
	}
    } elsif ($entry->query_type eq QUERY_SADDR) {
	if ($use_ipv6 && !$resolved) {
	    my @res = getaddrinfo($entry->query_data->[0],
				  $entry->query_data->[1],
				  AF_UNSPEC, SOCK_STREAM);
	    my ($saddr);
	    (undef, undef, undef, $saddr, undef, @res) = @res;
	    if (defined $saddr) {
		$entry->answer_data($saddr);
		$resolved = 1;
	    }
	}
	if (!$resolved) {
	    my $addr = inet_aton($entry->query_data->[0]);
	    if (defined $addr) {
		$entry->answer_data(pack_sockaddr_in($entry->query_data->[1],
						     $addr));
		$resolved = 1;
	    }
	}
    } elsif ($entry->query_type eq QUERY_NAMEINFO) {
	my ($addr, $port);
	if ($use_ipv6 && !$resolved) {
	    ($addr, $port) = getnameinfo($entry->query_data, NI_NUMERICHOST);
	    $resolved = 1;
	}
	if (!$resolved) {
	    ($port, $addr) = sockaddr_in($entry->query_data);
	    $resolved = 1;
	}
	if ($resolved) {
	    my @data;
	    threads::shared::share(@data) if $use_threads;
	    @data = ($addr, $port);
	    $entry->answer_data(\@data);
	}
    } else {
	carp 'unsupported query type('.$entry->query_type.')';
	$entry->answer_status($entry->ANSWER_NOT_SUPPORTED);
	$entry->answer_data('unsupported query type('.$entry->query_type.')');
    }

    if ($resolved) {
	$entry->answer_status($entry->ANSWER_OK);
    } else {
	$entry->answer_status($entry->ANSWER_NOT_FOUND);
    }
    return $entry;
}

sub resolver_thread {
    my ($class, $ask_queue, $reply_queue) = @_;

    my ($data, $entry);
    while (defined ($data = $ask_queue->dequeue)) {
	$entry = $dataclass->new->parse($data);
	eval {
	    $reply_queue->enqueue($class->_resolve($entry)->serialize);
	}; if ($@) {
	    my $err = $@;
	    $entry->answer_status($entry->ANSWER_INTERNAL_ERROR);
	    eval {
		require Data::Dumper;
		my $answer_data = $entry->answer_data;
		if (defined $answer_data) {
		    $err .= "(answer_data: " .
			Data::Dumper->new([$entry->answer_data])->Terse(1)->
				Purity(1)->Dump . ")\n";
		}
	    };
	    $entry->answer_data($err);
	    $reply_queue->enqueue($entry->serialize);
	}
    }
    return 0;
}

sub mainloop {
    my $this = shift;

    my $entry;
    while ($this->{reply_queue}->pending) {
	$entry = $this->{reply_queue}->dequeue;
	$this->_call($dataclass->new->parse($entry));
    }
}

1;
