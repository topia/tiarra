# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Rewrite ip address of CTCP DCC issued by client
# -----------------------------------------------------------------------------
package CTCP::DCC::RewriteAddress;
use strict;
use warnings;
use base qw(Module);
use Multicast;
use CTCP;
use Tiarra::Resolver;
use Module::Use qw(Tools::HTTPClient);
use Tools::HTTPClient;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Client') &&
	$msg->command eq 'PRIVMSG' &&
	    !defined $msg->nick) {

	my @permit_types = split /\s+/, (uc($this->config->type));
	my $text = $msg->param(1);
	foreach my $ctcp (CTCP->extract_from_text("$text")) {
	    if ($ctcp =~ m|^DCC (\S*) (.*)$|) {
		my ($type, $params) = (uc($1), $2);
		next unless !@permit_types or grep { $type eq $_ } @permit_types;
		my $result = $this->rewrite_dcc(
		    $msg->clone, $type, $params, $sender);
		next unless $result;
		my $encoded_ctcp = CTCP->make_text($ctcp);
		$text =~ s/\Q$encoded_ctcp\E//;
	    }
	}
	if ($text) {
	    $msg->param(1, $text);
	    return $msg;
	} else {
	    return undef;
	}
    }

    $msg;
}

our %resolvers = (
    'server-socket' => {
	resolver => sub {
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;
	    my $sock = ($this->_runloop->networks_list)[0]->sock;
	    return undef unless defined $sock;

	    $actions->{resolve}->(
		nameinfo => $sock->sockname,
		sub {
		    $actions->{closure}->(shift->answer_data->[0],
					  $port);
		});
	},
    },
    'client-socket' => {
	resolver => sub {
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;
	    my $sock = $sender->sock;
	    return undef unless defined $sock;

	    $actions->{resolve}->(
		nameinfo => $sock->peername,
		sub {
		    $actions->{closure}->(shift->answer_data->[0],
					  $port);
		});
	    1;
	},
    },
    'dns' => {
	resolver => sub {
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;

	    $actions->{resolve}->(
		addr => $conf->host,
		sub {
		    $actions->{closure}->(shift->answer_data->[0],
					  $port);
		});
	},
    },
    'http' => {
	resolver => sub{
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;

	    my $regex = "".$conf->regex;
	    Tools::HTTPClient->new(
		Method => 'GET',
		Url => $conf->url,
		Debug => 1,
	       )->start(
		   sub {
		       my $resp = shift;
		       $actions->{step}->(
			   sub {
			       return undef unless ref($resp);
			       if ($resp->{Content} !~ /$regex/) {
				   ::printmsg("http: regex: $regex");
				   ::printmsg("http: content: $resp->{Content}");
				   return undef;
			       }
			       $actions->{closure}->($1, $port);
			       1;
			   });
		   });
	    1;
	},
    },
   );

sub intaddr_to_octet {
    my $intaddr = shift;
    my $tail = $intaddr;
    my @ret;
    foreach (0..3) {
	unshift(@ret, $tail % 256);
	$tail /= 256;
    }
    join('.', @ret);
}

sub octet_to_intaddr {
    my $ret = 0;
    foreach (split /\./, shift) {
	$ret *= 256;
	$ret += $_;
    }
    $ret;
}

sub get_dcc_address_port {
    my ($this, $msg, $sender, $addr, $port, $closure, @resolvers) = @_;
    my $resolver;
    my $step;
    my $next;

    $step = sub {
	my $ret = eval { shift->(@_) };
	if (!defined $ret) {
	    if ($@) {
		::printmsg("$resolver: error occurred: $@");
	    }
	    ::printmsg("$resolver: cannot resolved. try next method.");
	    $next->();
	} else {
	    $ret;
	}
    };

    my $resolve = sub {
	my $type = shift;
	my $data = shift;
	my $closure = shift;
	my @args = @_;

	Tiarra::Resolver->resolve(
	    $type => $data,
	    sub {
		my $resolved = shift;
		my $ret = eval {
		    if ($resolved->answer_status ne $resolved->ANSWER_OK) {
			::printmsg("resolver: $type/$data: return not OK");
			::printmsg("resolver: ". $resolved->answer_data);
			return undef; # next method
		    }
		    $closure->(@args, $resolved, @_);
		};
		if (!defined $ret) {
		    if ($@) {
			::printmsg("$resolver: error occurred: $@");
		    }
		    ::printmsg("$resolver: cannot resolved. try next method.");
		    $next->();
		} else {
		    $ret;
		}
	    });
	1;
    };

    my $actions = {
	closure => $closure,
	step => $step,
	resolve => $resolve,
    };

    $next = sub {
	if (!@resolvers) {
	    ## FIXME: on cannot resolve
	    ::printmsg(__PACKAGE__."/rewrite_dcc: cannot resolve address at all");
	    $closure->();
	    return undef;
	}
	$resolver = shift(@resolvers);
	$step->(sub { $resolvers{$resolver}->{resolver}->(
	    $this, $actions, $sender,
	    $this->config->get($resolver, 'block'), $msg, $addr, $port); });
    };

    $next->();
}

sub rewrite_dcc {
    my ($this, $msg, $type, $param, $sender) = @_;
    if ($param !~ /^(\S*) (\S*) (\S*)(.*)$/) {
	return undef;
    }

    my ($arg, $addr, $port, $trail) = ($1, $2, $3, $4);
    $addr = intaddr_to_octet($addr);
    my $send_dcc = sub {
	my ($addr, $port) = @_;
	$addr = octet_to_intaddr($addr);
	$msg->param(1, CTCP->make_text("DCC $type $arg $addr $port$trail"));
	Multicast::from_client_to_server($msg, $sender);
	1;
    };
    my @resolvers = split /\s+/, $this->config->resolver;

    my $closure = sub {
	my ($newaddr, $newport) = @_;
	$addr = $newaddr if $newaddr;
	$port = $newport if $newport;

	$send_dcc->($addr, $port);
    };
    $this->get_dcc_address_port(
	$msg, $sender, $addr, $port, $closure, @resolvers);

}

1;

=pod
info: クライアントが送信した CTCP DCC のアドレスを変換する。
default: off
section: important

# CTCP DCC に指定されているアドレスを、 tiarra で取得したものに
# 書き換えます。(EXPERIMENTAL)

# このモジュールは一旦 CTCP DCC メッセージを破棄するので、
# 別のクライアントには送信されません。

# 変換する DCC タイプ。省略すると全てのDCCを処理する。
type: send chat

# 変換用アドレスの取得方法を選択する。デフォルト値はありません。
resolver: client-socket server-socket

server-socket {
  # サーバソケットのローカルアドレスを取ります。

  # client <-> tiarra[this address] <-> server
}

client-socket {
  # クライアントソケットのリモートアドレスを取ります。

  # client [this address]<-> tiarra <-> server
}

dns {
  # DNS を引いて決定します。IPアドレスの指定も可能です。
  host: example.com
}

http {
  url: http://checkip.dyndns.org/
  regex: Current IP Address: (\d+\.\d+\.\d+\.\d+)
}

=cut
