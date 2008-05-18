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


sub new {
    my $this = shift->SUPER::new(@_);

    $this->{permit_types} = [map uc, split /\s+/,
			     ($this->config->type || 'CHAT SEND')];
    $this->{resolvers} = [map lc, split /\s+/, $this->config->resolver];

    return $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Client') &&
	$msg->command eq 'PRIVMSG' &&
	    !defined $msg->nick) {

	my $text = $msg->param(1);
	foreach my $ctcp (CTCP->extract_from_text("$text")) {
	    if ($ctcp =~ m|^DCC (\S*) (.*)$|) {
		my ($type, $params) = (uc($1), $2);
		next unless grep { $type eq $_ } @{$this->{permit_types}};
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
		    $actions->{callback}->(shift->answer_data->[0],
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
		    $actions->{callback}->(shift->answer_data->[0],
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
		    $actions->{callback}->(shift->answer_data->[0],
					  $port);
		});
	},
    },
    'http' => {
	resolver => sub{
	    my ($this, $actions, $sender, $conf, $msg, $addr, $port) = @_;

	    my $regex = "".$conf->regex; # regex to string
	    my $callback = sub {
		my $resp = shift;
		$actions->{step}->(
		    sub {
			return undef unless ref($resp);
			if ($resp->{Content} !~ /$regex/) {
			    $this->_runloop->notify_warn(
				__PACKAGE__." http: regex not match: $regex");
			    #::printmsg("http: content: $resp->{Content}");
			    return undef;
			}
			$actions->{callback}->($1, $port);
			1;
		    });
	    };
	    Tools::HTTPClient->new(
		Method => 'GET',
		Url => $conf->url,
		Debug => 1,
	       )->start($callback);
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

# $this->get_dcc_address_port($msg, $msg_sender, $dcc_addr, $dcc_port,
#                             $callback, @resolvers)
# callback:
#   sub {
#       my ($addr, $port) = @_;
#       $addr = default_addr unless defined $addr;
#       $port = default_port unless defined $port;
#       ...
#   }
sub get_dcc_address_port {
    my ($this, $msg, $sender, $addr, $port, $callback, @resolvers) = @_;
    my $resolver;
    my $step;
    my $next;

    # resolving step wrapper.
    # $actions->{step}->(sub { ... }, @args_to_closure)
    #   closure return undef (or on error): try next method.
    #   otherwise wrapper return with closure return value.
    $step = sub {
	my $ret = eval { shift->(@_) };
	if (!defined $ret) {
	    if ($@) {
		$this->_runloop->notify_warn(
		    __PACKAGE__." $resolver: error occurred: $@");
	    }
	    $this->_runloop->notify_warn(
		__PACKAGE__." $resolver: cannot resolved. try next method.");
	    $next->();
	} else {
	    $ret;
	}
    };

    # Tiarra::Resolver->resolve wrapper.
    # $actions->{resolve}->($type => $data, sub { ... }, @args_to_callback);
    #   1. resolve answer status is not OK, try next method.
    #   2. call callback with args: (@args_to_callback, $resolved).
    #   3. callback return undef, try next method.
    #   4. otherwise wrapper return with callback return value
    my $resolve = sub {
	my $type = shift;
	my $data = shift;
	my $callback = shift;
	my @args = @_;

	Tiarra::Resolver->resolve(
	    $type => $data,
	    sub {
		my $resolved = shift;
		my $ret = eval {
		    if ($resolved->answer_status ne $resolved->ANSWER_OK) {
			$this->_runloop->notify_warn(
			    __PACKAGE__." resolver: $type/$data: return not OK");
			undef; # next method
		    } else {
			$callback->(@args, $resolved, @_);
		    }
		};
		if (!defined $ret) {
		    if ($@) {
			$this->_runloop->notify_warn(
			    __PACKAGE__." $resolver: error occurred: $@");
		    }
		    $this->_runloop->notify_warn(
			__PACKAGE__." $resolver: cannot resolved. try next method.");
		    $next->();
		} else {
		    $ret;
		}
	    });
	1;
    };

    my $actions = {
	callback => $callback,
	step => $step,
	resolve => $resolve,
    };

    $next = sub {
	if (!@resolvers) {
	    ## FIXME: on cannot resolve
	    $this->_runloop->notify_warn(
		__PACKAGE__." cannot resolve address at all");
	    $callback->();
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
    if ($param !~ /^(\S+) ([\d.]+) (\S+)(.*)$/) {
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

    my $callback = sub {
	my ($newaddr, $newport) = @_;
	$addr = $newaddr if $newaddr;
	$port = $newport if $newport;

	$send_dcc->($addr, $port);
    };
    $this->get_dcc_address_port(
	$msg, $sender, $addr, $port, $callback, @{$this->{resolvers}});

}

1;

=pod
info: クライアントが送信した CTCP DCC のアドレスを変換する。
default: off
section: important

# CTCP DCC に指定されているアドレスを、 tiarra で取得したものに
# 書き換えます。(EXPERIMENTAL)
#
# IPv4 のみサポートしています。
#
# このモジュールは一旦 CTCP DCC メッセージを破棄するので、
# 別のクライアントには送信されません。

# 変換する DCC タイプ。 [デフォルト値: CHAT SEND]
type: CHAT SEND

# 変換用アドレスの取得方法を選択する。デフォルト値はありません。
# 以下の取得方法(server-socket client-socket dns http)から
# 必要なもの(複数可)を指定してください。
resolver: client-socket server-socket dns http


# 取得方法と設定
# なにも設定がないときはブロック自体を省略することもできます。

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
  # 現状では単純な GET しかサポートしていません。

  # アクセス先 URL
  url: http://checkip.dyndns.org/

  # IP アドレス取得用 regex
  regex: Current IP Address: (\d+\.\d+\.\d+\.\d+)
}

# リゾルバの選び方
#
#  * tiarra を動作させているサーバとインターネットの間にルータ等があり、
#    グローバルアドレスがない場合
#      *-socket は役に立ちません。 http を利用してください。
#      適当な DDNS を持っていればdns も良いでしょう。
#
#  * tiarra がレンタルサーバなどLAN上にないサーバで動作している場合
#      server-socket, http は役に立ちません。
#      client-socket がお勧めです。
#
#  * tiarra がLAN上にあり、グローバルアドレスのついているホストで
#    動作している場合
#      client-socket は役に立ちません。
#      server-socket がお勧めです。

=cut
