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
use Tiarra::DefineEnumMixin qw(QUERY_HOST QUERY_ADDR);
my $dataclass = 'Tiarra::Resolver::QueueData';
our $use_threads;
our $use_ipv6;
BEGIN {
    $use_threads = Tiarra::OptionalModules->threads;
    if ($use_threads) {
	eval 'use Thread::Queue';
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

sub _new {
    my $class = shift;

    my $this = {};
    bless $this, $class;

    if ($use_threads) {
	$this->{ask_queue} = Thread::Queue->new;
	$this->{reply_queue} = Thread::Queue->new;
	$this->{thread} = threads->create("resolver_thread",
					  $class,
					  $this->{ask_queue},
					  $this->{reply_queue});
	$this->{mainloop} = Tiarra::WrapMainLoop->new(
	    type => 'timer',
	    interval => 2,
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

sub destruct {
    my $this = shift;

    $this->{ask_queue}->enqueue(undef);
    $this->{thread}->join;
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
	$entry->query_type(QUERY_ADDR);
	$entry->query_data($data);
	$do = 1;
    } elsif ($type eq 'host') {
	$entry->query_type(QUERY_HOST);
	$entry->query_data($data);
	$do = 1;
    }
    if ($do) {
	$entry->timeout(0);
	$entry->id($this->{id}++);
	$this->{closures}->{$entry->id} = $closure;
	if ($my_use_threads) {
	    $this->{ask_queue}->enqueue($entry->serialize);
	    $this->{mainloop}->lazy_install;
	} else {
	    $this->_call($this->_resolve($entry));
	}
    }
    undef;
}

sub paranoid_check {
    # ip -> host -> ip check
    my ($class_or_this, $data, $closure, $my_use_threads) = @_;
    my $this = $class_or_this->_this;

    # stage 1
    $this->resolve('host', $data, sub {
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
	$this->resolve('addr', $host, sub {
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
    $this->{closures}->{$id}->($entry);
    delete $this->{closures}->{$id};
    if (!%{$this->{closures}} && $use_threads) {
	$this->{mainloop}->lazy_uninstall;
    }
}

sub _resolve {
    my ($class_or_this, $entry) = @_;

    my $resolved = undef;
    my $ret = undef;

    if ($entry->query_type eq QUERY_ADDR) {
	if ($use_ipv6 && !$resolved) {
	    my @res = getaddrinfo($entry->query_data, AI_NUMERICHOST, AF_UNSPEC, SOCK_STREAM);
	    my ($saddr, $addr, @addrs, %addrs);
	    threads::shared::share(@addrs) if $use_threads;
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
		$entry->answer_data(\@addrs);
		$resolved = 1;
	    }
	}
	if (!$resolved) {
	    my $hostent = Net::hostent::gethost($entry->query_data);
	    if (defined $hostent) {
		#$entry->answer_data($hostent->addr_list);
		my @addrs;
		threads::shared::share(@addrs) if $use_threads;
		@addrs = map {
		    inet_ntoa($_);
		} @{$hostent->addr_list};
		$entry->answer_data(\@addrs);
		$resolved = 1;
	    }
	}
    } elsif ($entry->query_type eq QUERY_HOST) {
	if ($use_ipv6 && !$resolved) {
	    my @res = getaddrinfo($entry->query_data, AI_NUMERICHOST, AF_UNSPEC, SOCK_STREAM);
	    my ($saddr, $host, @hosts, %hosts);
	    threads::shared::share(@hosts) if $use_threads;
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
		if (@hosts == 1) {
		    $entry->answer_data($hosts[0]);
		} else {
		    $entry->answer_data(\@hosts);
		}
		$resolved = 1;
	    }
	}
	if (!$resolved) {
	    my $hostent = Net::hostent::gethost($entry->query_data);
	    if (defined $hostent) {
		$entry->answer_data($hostent->name);
		$resolved = 1;
	    }
	}
    } else {
	carp 'unsupported query type('.$entry->query_type.')';
	$entry->answer_status($entry->ANSWER_NOT_SUPPORTED);
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
	    $data->answer_status($entry->ANSWER_INTERNAL_ERROR);
	    $data->answer_data($@);
	    $reply_queue->enqueue($data->serialize);
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
