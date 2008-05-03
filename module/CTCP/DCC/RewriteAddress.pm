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
		my $closure = $this->rewrite_dcc(
		    $msg->clone, $type, $params, $sender);
		next unless defined $closure;
		Timer->new(
		    After => 0,
		    Code => $closure,
		   )->install;
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

our %checkers = (
    'server-socket' => {
	resolver => sub {
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;
	    my $sock = ($this->_runloop->networks_list)[0]->sock;
	    return undef unless defined $sock;
	    my $result = Tiarra::Resolver->shared->resolve(
		'nameinfo', $sock->sockname, sub {}, 0);
	    if ($result->answer_status eq $result->ANSWER_OK) {
		$actions->{send_dcc}->($result->answer_data->[0], $port);
		1;
	    } else {
		undef;
	    }
	},
    },
    'client-socket' => {
	resolver => sub {
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;
	    my $sock = $sender->sock;
	    return undef unless defined $sock;
	    my $result = Tiarra::Resolver->shared->resolve(
		'nameinfo', $sock->peername, sub {}, 0);
	    if ($result->answer_status eq $result->ANSWER_OK) {
		$actions->{send_dcc}->($result->answer_data->[0], $port);
		1;
	    } else {
		undef;
	    }
	},
    },
    'dns' => {
	resolver => sub {
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;

	    Tiarra::Resolver->resolve(
		addr => $conf->host, sub {
		    my $resolved = shift;
		    $actions->{step}->(
			sub {
			    if ($resolved->answer_status ne
				    $resolved->ANSWER_OK) {
				return undef; # next method
			    }
			    my $addr = $resolved->answer_data->[0];
			    $actions->{send_dcc}->($addr, $port);
			    1;
			})
		});
	    1;
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
			       $actions->{send_dcc}->($1, $port);
			       1;

			   });
		   });
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

sub rewrite_dcc {
    my ($this, $msg, $type, $param, $sender) = @_;
    if ($param =~ /^(\S*) (\S*) (\S*)(.*)$/) {
	my ($arg, $addr, $port, $trail) = ($1, $2, $3, $4);
	$addr = intaddr_to_octet($addr);
	my $send_dcc = sub {
	    $this->send_dcc($msg, $type, $arg, $trail, $sender, @_);
	    1;
	};
	my @resolvers = split /\s+/, $this->config->resolver;
	my $resolver;
	my $step;
	my $next;
	$step = sub {
	    my $ret = eval { shift->() };
	    if (!defined $ret) {
		if ($@) {
		    ::printmsg("$resolver: error occurred: $@");
		}
		::printmsg("$resolver: cannot resolved. try next method.");
		$next->();
	    } else {
		1;
	    }
	};
	my $actions = {
	    send_dcc => $send_dcc,
	    step => $step,
	};
	$next = sub {
	    if (!@resolvers) {
		## FIXME: cannot resolve
		::printmsg(__PACKAGE__."/rewrite_dcc: cannot resolve address at all");
		return undef;
	    }
	    $resolver = shift(@resolvers);
	    $step->(sub { $checkers{$resolver}->{resolver}->(
		$this, $actions, $sender,
		$this->config->get($resolver, 'block'), $msg, $addr, $port); });
	};
	return $next;
    }
}

sub send_dcc {
    my ($this, $msg, $type, $arg, $trail, $sender, $addr, $port) = @_;
    $addr = octet_to_intaddr($addr);
    $msg->param(1, CTCP->make_text("DCC $type $arg $addr $port$trail"));
    Multicast::from_client_to_server($msg,$sender);
    1;
}

1;

=pod
info: クライアントが送信した CTCP DCC のアドレスを変換する。
default: off
section: important

# CTCP DCC に指定されているアドレスを、 tiarra で取得したものに
# 書き換えます。

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
