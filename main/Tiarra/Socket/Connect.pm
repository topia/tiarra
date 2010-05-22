# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Socket Connector
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Socket::Connect;
use strict;
use warnings;
use Carp;
use List::Util qw(shuffle);
use Tiarra::Socket;
use base qw(Tiarra::Socket);
use Timer;
use Tiarra::OptionalModules;
use Tiarra::Utils;
utils->define_attr_accessor(0, qw(domain host addr port callback),
			    qw(bind_addr prefer timeout),
			    qw(retry_int retry_count),
			    qw(hooks ssl));
utils->define_attr_enum_accessor('domain', 'eq',
				 qw(tcp unix));

# now supported tcp, unix

# tcp:
#   my $connector = connect->new(
#       host => [hostname],
#       port => [port] or [ports],
#       callback => sub {
#           my ($genre, $connector, $msg_or_sock, $errno) = @_;
#           if ($genre eq 'error') {
#               # error: 重大なエラーが見つかったか、全ての接続に失敗したとき。
#               #        これ以降は何もしないので、必要な場合は
#               #        新しいインスタンスを作成してください。
#               #   $msg_or_sock: なんらかのメッセージ。
#               #   $errno: 原因となる errno があるときはセットされています。
#               die $msg_or_sock;
#           } elsif ($genre eq 'sock') {
#               # sock: 接続に成功したのでソケットを返します。
#               #   $msg_or_sock: 対応する IO::Socket のインスタンス。
#               attach($connector->current_addr, $connector->current_port,
#                      $msg_or_sock);
#               # その後上手く行かなかったので再開したいとき
#               # まず、いらなくなったソケットをクローズ
#               $msg_or_sock->close;
#               # このサーバは失敗したものとして、次のサーバから再試行
#               $connector->resume;
#           # timeout を指定したときは実装するようにしてください。
#           } elsif ($genre eq 'timeout') {
#               # timeout: 引数で指定された timeout が経過して、接続が
#               #          中断された時に呼ばれます。
#               #   $msg_or_sock: undef
#               die 'timeout';
#           # これ以降は必ずしも実装しなくてもかまいません。
#           } elsif ($genre eq 'warn') {
#               # warnings: 個々のホストに対する接続エラーとか。
#               #   $msg_or_sock: なんらかのメッセージ。
#               #   $errno: 原因となる errno があるときはセットされています。
#               warn $msg_or_sock;
#           } elsif ($genre eq 'progress') {
#               # progress: 接続の進行状況を示します。
#               #           主に試行開始メッセージが飛んできます。
#               #   $msg_or_sock: なんらかのメッセージ。
#               warn $msg_or_sock;
#           } elsif ($genre eq 'skip') {
#               # skip: before_connect フックにより skip を指示されると
#               #       呼び出されます。
#               #   $msg_or_sock: skip された接続先を含むメッセージ
#               warn $msg_or_sock;
#           } elsif ($genre eq 'interrupt') {
#               # interrupt: ユーザーにより接続が中断された
#               #            (interrupt が呼び出された)時に呼び出されます。
#               #   $msg_or_sock: undef
#               die 'interrupted';
#           }
#       },
#       ## オプション系
#       # 既に正引きしたアドレスを持っている場合に指定します。
#       addr => [already resolved addr],
#       # bind addr を指定します。必ずアドレスを書くようにしてください。
#       bind_addr => [bind_addr (cannot specify host)],
#       # タイムアウトを秒単位で指定します。
#       #  十分にテストされているとは言い難いので、おかしな動作を見つけたら
#       #  レポートを送ってください。
#       timeout => [timeout],
#       # 接続に失敗したあと、時間をおいて再試行する回数を指定します。
#       # 再試行回数は $connector->try_count で取得できます。
#       retry_count => [retry count],
#       # リトライ時の待ち時間を秒単位で指定します。
#       retry_int => [retry interval],
#       # 希望するソケット種類を ['ipv4', 'ipv6'] という形式で指定します。
#       # デフォルトは ipv6 -> ipv4 の順です。
#       prefer => [prefer socket type(and order) (ipv4, ipv6) as string's
#                  array ref, default ipv6, ipv4],
#       # ソケットドメイン。既定値ですが、必要であれば tcp を指定してください。
#       domain => 'tcp', # default
#       # SSL オブション。 IO::Socket::SSL の SSL_ を除いた名前が指定できます。
#       # ssl->{version} がない場合は SSL へのアップグレードは行いません。
#       # error_trap は Tiarra::Socket::Connector によって上書きされます。
#       # verifycn_name は指定がなければ host が補完されます。
#       ssl => {version=>'tlsv1'}, # no default
#       # フック。
#       hooks => {
#           # 接続前フック。
#           before_connect => { # hook before connection attempt
#               my ($stage, $connecting) = @_;
#               #   $stage: 'before_connect' という文字列が渡ります。
#               #   $connecting:
#               #     接続オプション。このハッシュは書き換えることができます。
#               #     { # be able to modify this hash.
#               #         addr => $addr, port => $port,
#               #         type => 'ipv4' or 'ipv6',
#               #         # この接続にのみ適用する bind_addr があれば
#               #         # 指定してください。
#               #         (bind_addr => [connection local bind_addr]),
#               #         # この接続にのみ適用する ssl があれば指定してください。
#               #         (ssl => [connection local ssl]),
#               #     }
#               if ( /* not_want_to_connect */ ) {
#                   # die するとこの接続はスキップされます。
#                   die 'skip this connection';
#               }
#           }
#       }
#       );
#   $connector->interrupt;
# unix:
#   my $connector = connect->new(
#       addr => [path],
#       callback => sub {
#           # ... same as tcp domain's
#       },
#       # optional params
#       domain => 'unix', # please define this
#       );

sub new {
    my ($class, %opts) = @_;

    $class->_increment_caller('socket-connector', \%opts);
    my $this = $class->SUPER::new(%opts);
    map {
	$this->$_($opts{$_});
    } qw(host addr port callback bind_addr timeout retry_int retry_count hooks ssl);

    if (!defined $this->callback) {
	croak 'callback closure required';
    }

    $this->domain(utils->get_first_defined($opts{domain}, 'tcp'));
    $this->prefer($opts{prefer});

    if (!defined $this->prefer) {
	if ($this->domain_tcp) {
	    my @prefer;
	    @prefer = ('ipv4');
	    if (Tiarra::OptionalModules->ipv6) {
		unshift(@prefer, 'ipv6')
	    }
	    $this->prefer(\@prefer);
	} elsif ($this->domain_unix) {
	    $this->prefer(['unix']);
	} else {
	    croak 'Unsupported domain: '. $this->domain;
	}
    }

    $this->{queue} = [];
    $this->connect;
}

sub connect {
    my $this = shift;

    if (defined $this->timeout) {
	$this->{timer} = Timer->new(
	    After => $this->timeout,
	    Code => sub {
		$this->interrupt('timeout');
	    });
    }

    if (defined $this->addr || $this->domain_unix) {
	my $entry = Tiarra::Resolver::QueueData->new;
	$entry->answer_status($entry->ANSWER_OK);
	$entry->answer_data([$this->addr]);
	$this->_connect_after_resolve($entry);
    } else {
	Tiarra::Resolver->resolve(
	    'addr', $this->host, sub {
		eval {
		    $this->_connect_after_resolve(@_);
		}; if ($@) {
		    $this->_connect_error("internal error: $@");
		}
	    });
    }
    $this;
}

sub _connect_after_resolve {
    my ($this, $entry) = @_;

    my %addrs_by_types;

    if ($entry->answer_status ne $entry->ANSWER_OK) {
	$this->_connect_error("Couldn't resolve hostname: ".$this->host);
	return undef; # end
    }

    foreach my $addr (shuffle @{$entry->answer_data}) {
	push (@{$addrs_by_types{$this->probe_type_by_addr($addr)}},
	      $addr);
    }

    foreach my $sock_type (@{$this->prefer}) {
	my $struct;
	my @ports;
	if (ref($this->port) eq 'ARRAY') {
	    @ports = @{$this->port};
	} else {
	    @ports = $this->port;
	}
	foreach my $port (@ports) {
	    push (@{$this->{queue}},
		  map {
		      $struct = {
			  type => $sock_type,
			  addr => $_,
			  port => $port,
		      };
		  } @{$addrs_by_types{$sock_type}});
	}
    }
    $this->_connect_try_next;
}

sub _connect_try_next {
    my $this = shift;

    $this->{connecting} = shift @{$this->{queue}};
    if (defined $this->{connecting}) {
	$this->_notify_progress("Connecting to ".$this->destination);
	my $methodname = '_try_connect_' . $this->{connecting}->{type};
	$this->$methodname;
    } else {
	if ($this->retry_int && (++$this->{try_count} <= $this->retry_count)) {
	    $this->{timer} = Timer->new(
		After => $this->retry_int,
		Code => sub {
		    $this->cleanup;
		    $this->connect;
		});
	    $this->_connect_warn(
		'all connection attempt failed, ' .
		    utils->to_ordinal_number($this->try_count) . ' retry');
	} else {
	    $this->_connect_error('all connection attempt failed');
	}
    }
}

sub _try_connect_ipv4 {
    my $this = shift;

    $this->_try_connect_tcp('IO::Socket::INET');
}

sub _try_connect_ipv6 {
    my $this = shift;

    if (!Tiarra::OptionalModules->ipv6) {
	$this->_warn(
	    qq{Host $this->{host} seems to be an IPv6 address, }.
		qq{but IPv6 support is not enabled. }.
		    qq{Use IPv4 or install Socket6 or IO::Socket::INET6 if possible.\n});
	$this->_connect_try_next;
	return;
    }

    $this->_try_connect_tcp('IO::Socket::INET6');
}

sub _check_connect_dependency {
    my $this = shift;

    my $ssl = $this->current_ssl;
    if (defined $ssl && $ssl->{version}) {
	if (!Tiarra::OptionalModules->ssl) {
	    $this->_warn(
		qq{You wants to connect with SSL, }.
		    qq{but SSL support is not enabled. }.
			qq{Use non-SSL or install IO::Socket::SSL if possible.\n});
	    return 0;
	}
    }
    return 1;
}

sub _try_connect_tcp {
    my ($this, $package, $addr, %additional) = @_;

    eval {
	$this->_call_hooks('before_connect', $this->{connecting});
    }; if ($@) {
	$this->_notify_skip($@);
	$this->_connect_try_next;
	return;
    }
    if (!eval("require $package")) {
	$this->_connect_warn("Couldn\'t require socket package: $package");
	$this->_connect_try_next;
	return;
    }
    if (!$this->_check_connect_dependency) {
	$this->_connect_try_next;
	return;
    }
    my $bind_addr = $this->current_bind_addr;
    my $sock = $package->new(
	%additional,
	(defined $bind_addr ?
	     (LocalAddr => $bind_addr) : ()),
	Timeout => undef,
	Proto => 'tcp');
    if (!defined $sock) {
	$this->_connect_warn("Couldn't prepare socket: $@");
	$this->_connect_try_next;
	return;
    }
    if (!defined $sock->blocking(0)) {
	# effect only on connecting; comment out
	#$this->_warn('cannot non-blocking') if ::debug_mode();

	if ($this->_is_winsock) {
	    # winsock FIONBIO
	    my $FIONBIO = 0x8004667e; # from Winsock2.h
	    my $temp = chr(1);
	    my $retval = $sock->ioctl($FIONBIO, $temp);
	    if (!$retval) {
		$this->_warn($this->sock_errno_to_msg(
		    $!, 'Couldn\'t set non-blocking mode (winsock2)'), $!);
	    }
	} else {
	    $this->_warn($this->sock_errno_to_msg(
		$!, 'Couldn\'t set non-blocking mode (general)'), $!);
	}
    }
    my $saddr = Tiarra::Resolver->resolve(
	'saddr', [$this->current_addr, $this->current_port],
	sub {}, 0);
    $this->{connecting}->{saddr} = $saddr->answer_data;
    if ($sock->connect($this->{connecting}->{saddr}) ||
	    $!{EINPROGRESS} || $!{EWOULDBLOCK}) {
	my $error = $!;
	$this->attach($sock);
	$! = $error;
	if ($!{EINPROGRESS} || $!{EWOULDBLOCK}) {
	    $this->install;
	} else {
	    $this->_connected;
	}
    } else {
	$this->_connect_warn_try_next($!, 'connect error');
    }
}

sub _try_connect_unix {
    my $this = shift;

    if (!Tiarra::OptionalModules->unix_dom) {
	$this->_error(
	    qq{Address $this->{addr} seems to be an Unix Domain Socket address, }.
		qq{but Unix Domain Socket support is not enabled. }.
		    qq{Use other protocol if possible.\n});
	return;
    }

    eval {
	$this->_call_hooks('before_connect', $this->{connecting});
    }; if ($@) {
	$this->_notify_skip($@);
	$this->_connect_try_next;
	return;
    }
    require IO::Socket::UNIX;
    if (!$this->_check_connect_dependency) {
	$this->_connect_try_next;
	return;
    }
    my $sock = IO::Socket::UNIX->new(Peer => $this->{connecting}->{addr});
    if (defined $sock) {
	$this->attach($sock);
	$this->_connected;
    } else {
	$this->_connect_warn_try_next($!, 'Couldn\'t connect');
    }
}

sub _connect_warn_try_next {
    my ($this, $errno, $msg) = @_;

    $this->_connect_warn($this->sock_errno_to_msg($errno, $msg), $errno);
    $this->_connect_try_next;
}

sub _connect_error { shift->_connect_warn_or_error('error', @_); }
sub _connect_warn { shift->_connect_warn_or_error('warn', @_); }

sub _connect_warn_or_error {
    my $this = shift;
    my $method = '_'.shift;
    my $str = shift;
    my $errno = shift; # but optional
    if (defined $str) {
	$str = ': ' . $str;
    } else {
	$str = '';
    }

    $this->$method("Couldn't connect to ".$this->destination.$str, $errno, @_);
}

sub destination {
    my $this = shift;

    $this->repr_destination(
	host => $this->host,
	addr => $this->current_addr,
	port => $this->current_port,
	type => $this->current_type);
}

sub current_addr {
    my $this = shift;

    utils->get_first_defined(
	$this->{connecting}->{addr},
	$this->addr);
}

sub current_port {
    my $this = shift;

    utils->get_first_defined(
	$this->{connecting}->{port},
	ref($this->port) ? join(',', @{$this->port}) : $this->port);
}

sub current_bind_addr {
    my $this = shift;

    utils->get_first_defined(
	$this->{connecting}->{bind_addr},
	$this->bind_addr);
}

sub current_ssl {
    my $this = shift;

    utils->get_first_defined(
	$this->{connecting}->{ssl},
	$this->ssl);
}

sub current_type {
    my $this = shift;

    $this->{connecting}->{type};
}

sub try_count {
    shift->{try_count} + 1;
}

sub _error {
    # connection error; and finish ->connect chain
    my ($this, $msg, $errno) = @_;

    $this->callback->('error', $this, $msg, $errno);
}

sub _warn {
    # connection warning; but continue trying
    my ($this, $msg, $errno) = @_;

    $this->callback->('warn', $this, $msg, $errno);
}

sub _notify_progress {
    # connection progress message.
    my ($this, $msg) = @_;

    $this->callback->('progress', $this, $msg);
}

sub _notify_skip {
    # this address/port skipped; but continue trying
    my ($this, $str, $errno) = @_;

    $this->callback->('skip', $this,
		      "skip connection attempt to ".$this->destination.$str,
		      $errno);
}

sub _connected {
    # connection successful
    my $this = shift;

    my $ssl = $this->current_ssl;
    if (!defined $ssl || !$ssl->{version}) {
	$this->_call;
    } else {
	## ssl module check is done before start connection,
	## with _check_connect_dependency.
	require IO::Socket::SSL;
	my %ssloptions = (
	    SSL_startHandshake => 0,
	    map { ("SSL_$_", $ssl->{$_})} keys %$ssl);
	$ssloptions{SSL_verifycn_name} ||= $this->host;
	$ssloptions{SSL_error_trap} = sub {
	    my ($sock, $error) = @_;
	    ## IO::Socket::SSL downgrading socket on standard error trap.
	    ## This breaks unregister RunLoop sockets.
	    $this->{connecting}->{ssl_fatal_error} = $error;
	};
	my $sock = $this->sock;
	$this->detach;
	my $newsock = IO::Socket::SSL->start_SSL(
	    $sock, %ssloptions);
	if (defined $newsock) {
	    $this->attach($newsock);
	    $this->{connecting}->{ssl_upgrading} = 1;
	    $this->install;
	    $this->proc_sock('ssl');
	} else {
	    $this->_warn(
		qq{Couldn\'t set-up SSL: $IO::Socket::SSL::SSL_ERROR.\n});
	    $this->attach($sock);
	    $this->close;
	    $this->_connect_try_next;
	    return;
	}
    }
}

sub _call {
    # connection successful
    my $this = shift;

    $this->callback->('sock', $this, $this->sock);
}

sub _call_hooks {
    # method may died by callback.
    # please cover with eval, if you need.
    my $this = shift;
    my $genre = shift;

    if (defined $this->{hooks}->{$genre}) {
	$this->{hooks}->{$genre}->($genre, @_);
    }
}

sub cleanup {
    my $this = shift;

    if ($this->installed) {
	$this->uninstall;
    }
    if (defined $this->{timer}) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }
}

sub interrupt {
    my ($this, $genre) = @_;

    $this->cleanup;
    if (defined $this->sock) {
	$this->close;
    }
    $genre = 'interrupt' unless defined $genre;
    $this->callback->($genre, $this);
}

sub resume {
    my ($this) = @_;

    if (defined $this->sock) {
	$this->detach;
    }
    $this->_connect_try_next;
}

sub want_to_read {
    my $connecting = shift->{connecting};
    $connecting->{ssl_upgrading} ? $connecting->{ssl_want_read} : 0;
}

sub want_to_write {
    my $connecting = shift->{connecting};
    $connecting->{ssl_upgrading} ? $connecting->{ssl_want_write} : 1;
}

sub write { shift->proc_sock('write') }
sub read { shift->proc_sock('read') }
sub exception { shift->_handle_sock_error }

sub proc_sock {
    my $this = shift;
    my $state = shift;

    if ($this->{connecting}->{ssl_upgrading}) {
	my $ret = $this->sock->connect_SSL;
	if (!$ret) {
	    $this->{connecting}->{ssl_want_read} =
		$this->sock->errstr == IO::Socket::SSL::SSL_WANT_READ();
	    $this->{connecting}->{ssl_want_write} =
		$this->sock->errstr == IO::Socket::SSL::SSL_WANT_WRITE();
	    if (!$this->{connecting}->{ssl_want_read} &&
		    !$this->{connecting}->{ssl_want_write}) {
		$this->_handle_sock_error($!, 'upgrade to SSL error: ' . $this->sock->errstr);
		if ($this->{connecting}->{ssl_fatal_error}) {
		    my $sock = $this->sock;
		    $this->cleanup;
		    $this->shutdown(2);
		    $this->detach;
		    $sock->close(SSL_no_shutdown=>1, SSL_ctx_free=>1);
		    $this->_connect_try_next;
		}
	    }
	} else {
	    $this->cleanup;
	    $this->_call;
	}
	return
    }
    if ($state eq 'write') {
	my $error = $this->errno;
	$this->cleanup;
	if ($error) {
	    $this->close;
	    $this->_connect_warn_try_next($error);
	} else {
	    $this->_connected;
	}
    } elsif (!$this->sock->connect($this->{connecting}->{saddr})) {
	if ($!{EISCONN} ||
		($this->_is_winsock && (($! == 10022) || $!{EWOULDBLOCK} ||
					    $!{EALREADY}))) {
	    $this->cleanup;
	    $this->_connected;
	} else {
	    $this->_handle_sock_error($!, 'connection try error');
	}
    } elsif (!IO::Select->new($this->sock)->can_write(0)) {
	$this->_handle_sock_error(undef, "can't write on $state");
    } else {
	# ignore first ready-to-read
	if ($state ne 'read' || $this->{unexpected_want_to_read_count}++) {
	    $this->_warn("connect successful, why called this on $state?");
	}
    }
}

sub _handle_sock_error {
    my $this = shift;

    my $error = shift;
    my $msg = shift;
    $error = $this->errno unless defined $error;
    $this->cleanup;
    $this->close;
    $this->_connect_warn_try_next($error, $msg);
}

1;
