# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id: HTTPClient.pm,v 1.1 2004/03/27 10:41:17 admin Exp $
# -----------------------------------------------------------------------------
# HTTP/1.1���б���
# -----------------------------------------------------------------------------
package Tools::HTTPClient;
use strict;
use warnings;
use LinedINETSocket;
use Carp;
use RunLoop;
use Timer;
# ������HTTP::Request��HTTP::Response��Ȥ���������

my $DEBUG = 0;

sub new {
    my ($class, %args) = @_;
    my $this = bless {} => $class;

    if (!$args{Method}) {
	croak "Argument `Method' is required";
    }
    if (!$args{Url}) {
	croak "Argument `Url' is required";
    }

    $this->{method} = $args{Method}; # GET | POST
    $this->{url} = $args{Url};
    $this->{content} = $args{Content}; # undef��
    $this->{header} = $args{Header} || {}; # {key => value} undef��
    $this->{timeout} = $args{Timeout}; # undef��

    $this->{callback} = undef;
    $this->{socket} = undef;
    $this->{hook} = undef;
    $this->{timeout_timer} = undef;

    $this->{expire_time} = undef; # �����ॢ���Ȼ���

    $this->{status_fetched} = undef;
    $this->{header_fetched} = undef;

    $this->{reply} = {Header => {}, Content => ''};
    
    $this;
}

sub start {
    # $callback: ���å����λ��˸ƤФ��ؿ�����ά�Բġ�
    # ���δؿ��ˤϼ��Τ褦�ʥϥå��夬�Ϥ���롣
    # {
    #     Protocol => 'HTTP/1.0',
    #     Code     => 200,
    #     Message  => 'OK',
    #     Header   => {
    #         'Content-Length' => 6,
    #     },
    #     Content => 'foobar',
    # }
    # ���顼��ȯ���������ϥ��顼��å�����(ʸ����)���Ϥ���롣
    my ($this, $callback) = @_;
    if ($this->{callback}) {
	croak "This client is already started";
    }
    $this->{callback} = $callback;

    if (!$callback or ref($callback) ne 'CODE') {
	croak "Callback function is required";
    }

    # URL��ʬ�򤷡��ۥ���̾�ȥѥ������롣
    my ($host, $path);
    $this->{url} =~ s/#.+//;
    if ($this->{url} =~ m|^http://(.+)$|) {
	if ($1 =~ m|^(.+?)(/.*)|) {
	    $host = $1;
	    $path = $2;
	}
	else {
	    $host = $1;
	    $path = '/';
	}
    }
    else {
	croak "Unsupported scheme: $this->{url}";
    }

    # �إå���Host���ޤޤ�Ƥ��ʤ�����ɲá�
    if (!$this->{Header}{Host}) {
	$this->{Header}{Host} = $host;
    }

    # �ۥ���̾�˥ݡ��Ȥ��ޤޤ�Ƥ�����ʬ��
    my $port = 80;
    if ($host =~ s/:(\d+)//) {
	$port = $1;
    }

    # ��³
    $this->{socket} = LinedINETSocket->new("\x0a")->connect($host, $port);
    if (!$this->{socket}) {
	# ��³�Բ�ǽ
	croak "Failed to connect: $host:$port";
    }

    # ɬ�פʤ饿���ॢ�����ѤΥ����ޡ��򥤥󥹥ȡ���
    if ($this->{timeout}) {
	$this->{expire_time} = time + $this->{timeout};
	$this->{timeout_timer} = Timer->new(
	    After => $this->{timeout},
	    Code => sub {
		$this->{timeout_timer} = undef;
		$this->_main;
	    })->install;
    }

    # �ꥯ�����Ȥ�ȯ�Ԥ����եå��򤫤��ƽ�λ��
    my @request = (
	"$this->{method} $this->{url} HTTP/1.0",
	do {
	    map {
		"$_: ".$this->{header}{$_}
	    } keys %{$this->{header}}
	},
	'',
	do {
	    $this->{content} ? $this->{content} : ();
	},
       );
    foreach (@request) {
	$DEBUG and print "> $_\n";
	$this->{socket}->send_reserve($_);
    }

    $this->{hook} = RunLoop::Hook->new(
	sub {
	    $this->_main;
	})->install('before-select');

    $this;
}

sub _main {
    my $this = shift;

    # �����ॢ����Ƚ��
    if ($this->{expire_time} and time >= $this->{expire_time}) {
	$this->_end("timeout");
	return;
    }

    while (defined(my $line = $this->{socket}->pop_queue)) {
	$DEBUG and print "< $line\n";
	
	if (!$this->{status_fetched}) {
	    # ���ơ�������
	    $line =~ tr/\n\r//d;
	    if ($line =~ m|^(HTTP/.+?) (\d+?) (.+)$|) {
		$this->{reply}{Protocol} = $1;
		$this->{reply}{Code} = $2;
		$this->{reply}{Message} = $3;
		$this->{status_fetched} = 1;
	    }
	    else {
		$this->_end("invalid status line: $line");
		return;
	    }
	}
	elsif (!$this->{header_fetched}) {
	    $line =~ tr/\n\r//d;
	    if (length $line == 0) {
		# �إå������
		$this->{header_fetched} = 1;
	    }
	    else {
		if ($line =~ m|(.+?): (.+)$|) {
		    $this->{reply}{Header}{$1} = $2;
		}
		else {
		    $this->_end("invalid header line: $line");
		    return;
		}
	    }
	}
	else {
	    # ���
	    $this->{reply}{Content} .= $line . "\x0d\x0a";
	}
    }

    # ���Ǥ���Ƥ����顢�����ǽ���ꡣ
    if (!$this->{socket}->connected) {
	if (!$this->{status_fetched} or
	      !$this->{header_fetched}) {
	    $this->_end("unexpected disconnect by server");
	}
	else {
	    $this->{reply}{Content} .= $this->{socket}->recvbuf;
	    $this->_end;
	}
    }
}

sub _end {
    my ($this, $err) = @_;

    $this->stop;
    
    if ($err) {
	$this->{callback}->($err);
    }
    else {
	$this->{callback}->($this->{reply});
    }
}

sub alive_p {
    my $this = shift;
    defined $this->{socket};
}

sub stop {
    my $this = shift;

    $this->{socket}->disconnect if $this->{socket};
    $this->{hook}->uninstall if $this->{hook};
    $this->{timeout_timer}->uninstall if $this->{timeout_timer};

    $this->{socket} =
      $this->{hook} =
	$this->{timeout_timer} =
	  undef;
}

1;
