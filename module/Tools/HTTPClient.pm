# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
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
use Tools::HTTPClient::SSL;
use Module::Use qw(Tools::HTTPClient::SSL);

# ������HTTP::Request��HTTP::Response��Ȥ���������

our $DEBUG = 0;

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
    $this->{progress_callback} = undef;
    $this->{socket} = undef;
    $this->{hook} = undef;
    $this->{timeout_timer} = undef;

    $this->{expire_time} = undef; # �����ॢ���Ȼ���

    $this->{status_fetched} = undef;
    $this->{header_fetched} = undef;

    $this->{reply} = {Header => {}, Content => '', StreamState => 'ready' };

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
    my %opts;
    if( @_>=3 )
    {
      ($this, %opts) = @_;
      $callback = $opts{Callback};
    }
    if ($this->{callback}) {
	croak "This client is already started";
    }
    $this->{callback} = $callback;
    $this->{progress_callback} = $opts{ProgressCallback};

    if (!$callback or ref($callback) ne 'CODE') {
	croak "Callback function is required";
    }

    # URL��ʬ�򤷡��ۥ���̾�ȥѥ������롣
    my ($host, $path);
    $this->{url} =~ s/#.+//;
    if ($this->{url} =~ m|^http(s?)://(.+)$|) {
	my $with_ssl = $1;
	my $hostpath = $2;
	if ($hostpath =~ m|^(.+?)(/.*)|) {
	    $host = $1;
	    $path = $2;
	}
	else {
	    $host = $1;
	    $path = '/';
	}
	$this->{with_ssl} = $with_ssl;
    }
    else {
	croak "Unsupported scheme: $this->{url}";
    }

    # �إå���Host���ޤޤ�Ƥ��ʤ�����ɲá�
    if (!$this->{header}{Host}) {
	$this->{header}{Host} = $host;
    }

    # �ۥ���̾�˥ݡ��Ȥ��ޤޤ�Ƥ�����ʬ��
    my $port = $this->{with_ssl} ? 443 : 80;
    if ($host =~ s/:(\d+)$//) {
	$port = $1;
    }

    # ��³
    $this->{reply}{StreamState} = 'connect';
    my $socket_class = $this->{with_ssl} ? 'Tools::HTTPClient::SSL' : 'LinedINETSocket';
    $this->{socket} = $socket_class->new->connect($host, $port);
    if (!defined $this->{socket}) {
	# ��³�Բ�ǽ
	croak "Failed to connect: $host:$port";
    }
    if (!defined $this->{socket}->sock) {
	# ��³�Բ�ǽ
	croak "Failed to connect: $host:$port, $@";
    }
    $this->{reply}{StreamState} = 'fetch_status';

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
	"$this->{method} $path HTTP/1.0",
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

    my $progress;
    while (defined(my $line = $this->{socket}->pop_queue)) {
	$DEBUG and print "< $line\n";
	$progress = 1;
	
	if (!$this->{status_fetched}) {
	    # ���ơ�������
	    $line =~ tr/\n\r//d;
	    if ($line =~ m|^(HTTP/.+?) (\d+?) (.+)$|) {
		$this->{reply}{Protocol} = $1;
		$this->{reply}{Code} = $2;
		$this->{reply}{Message} = $3;
		$this->{status_fetched} = 1;
		$this->{reply}{StreamState} = 'fetch_header';
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
		$this->{reply}{StreamState} = 'fetch_body';
	    }
	    else {
		if ($line =~ m|(.+?): ?(.+)$|) {
		    my ($key, $val) = ($1, $2);
		    $key =~ /^Content-Type\z/i and $key = 'Content-Type';
		    $this->{reply}{Header}{$key} = $val;
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

    if( $this->{header_fetched} && $this->{socket}->recvbuf )
    {
      #$DEBUG and print "<< (merge body)\n" . $this->{socket}->recvbuf."<< (end)\n";
      $progress = 1;
      $this->{reply}{Content} .= $this->{socket}->recvbuf;
      $this->{socket}->recvbuf = '';
    }

    # ���Ǥ���Ƥ����顢�����ǽ���ꡣ
    if (!$this->{socket}->connected) {
        $DEBUG and print "<< (disconnected)\n";
	if (!$this->{status_fetched} or
	      !$this->{header_fetched}) {
	    $this->_end("unexpected disconnect by server");
	}
	else {
	    $this->{reply}{StreamState} = 'finished';
	    $this->_end;
	}
    }else
    {
      if( $progress && $this->{progress_callback} )
      {
        $this->{progress_callback}->($this->{reply});
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

    $this->{socket}->disconnect if $this->{socket} && $this->{socket}->connected;
    $this->{hook}->uninstall if $this->{hook};
    $this->{timeout_timer}->uninstall if $this->{timeout_timer};

    $this->{socket} =
      $this->{hook} =
	$this->{timeout_timer} =
	  undef;
}

1;

=encoding euc-jp

=head1 NAME

Tools::HTTPClient - HTTP Client

=head1 SYNOPSIS

 use Tools::HTTPClient;

 my $http = Tools::HTTPClient->new(
   Url    => 'http://www.example.com',
   Method => 'GET',
 );
 $http->start(\&callback);

=head1 DESCRIPTION

HTTP Client for tiarra.

�֥�å����ʤ��褦�˽�������侩�ʤΤ�,
�֥�å����ʤ��褦��Ĵ������Ƥ��� HTTP 
���饤����ȥ⥸�塼��.

=head1 METHODS

=head2 new

 my $http = Tools::HTTPClient->new(
   Url    => 'http://www.example.com',
   Method => 'GET',
 );

���󥹥��󥹤�����.
C<Url> �ڤ� C<Method> ������ɬ��.

����¾�ξ�ά��ǽ�ʰ����Ȥ���,
C<Content> (POST����),
C<Header>  (HASH-ref),
C<Timeout> (��ñ��)
�����Ѳ�ǽ.

=head2 start

 $http->start(\&callback);
 $http->start(%opts);

 $opts{Callback}         = \&callback;
 $opts{ProgressCallback} = \&progress_callback;

C<\&callback> �Ͻ�����λ���˸ƤФ��ؿ�.
C<\&progress_callback> �Ͻ����ο�Ľ�����ä��Ȥ��˸ƤФ��ؿ�.

C<\&callback> ��, HTTP������˴�λ�����HASH-ref��,
�����ॢ���Ȥ䥨�顼���ˤϥ��顼���Ƥ�ޤ��ʸ�����
�����Ȥ��ƸƤӽФ����.

  sub my_callback {
    my $response = shift;
    if( !ref($response) )
    {
      # error.
      return;
    }
    # success.
    my $protocol    = $response->{Protocol};
    my $status_code = $response->{Code};
    my $status_msg  = $response->{Message};
    my $headers     = $response->{Header}; # hash-ref.
    my $content     = $response->{Content};
  }

C<\&progress_callback> ��Ʊ��, 
������������ϥ��顼�����ˤϸƤФ�ʤ�.

=head2 stop

 $http->stop();

�ꥯ�����Ȥν�λ.
���ΤȤ��� L</start> �ǻ��ꤷ�� C<\&callback> ����Ф�ʤ��Τ����.

=head1 AUTHOR

phonohawk <phonohawk@ps.sakura.ne.jp>

=head1 SEE ALSO

tiarra
http://coderepos.org/share/wiki/Tiarra
(Japanese)

=cut
