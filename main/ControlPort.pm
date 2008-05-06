# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
=pod
    << NOTIFY Log::Channel TIARRACONTROL/1.0
    << Sender: LogManager
    << ID: synchronize

    >> TIARRACONTROL/1.0 204 No Content
    ----------------------------------------
    << GET :: TIARRACONTROL/1.0
    << Sender: Foo
    << ID: get-realname
    << Reference0: ircnet
    << Charset: UTF-8

    >> TIARRACONTROL/1.0 200 OK
    >> Value: (�ͥåȥ��ircnet�Ǥ���̾)
    >> Charset: UTF-8
=cut
# -----------------------------------------------------------------------------
package ControlPort;
use strict;
use warnings;
use Carp;
use IO::Dir;
use ExternalSocket;
use Tiarra::Encoding;
use RunLoop;
use Tiarra::TerminateManager;

# ʣ���Υѥå������򺮺ߤ����Ƥ��SelfLoader���Ȥ��ʤ��ġ�
#use SelfLoader;
#1;
#__DATA__

sub TIARRA_CONTROL_ROOT () { '/tmp/tiarra-control'; }

sub new {
    my ($class,$sockname) = @_;

    # IO::Socket::UNIX��use���롣���Ԥ�����die��
    eval q{
        use IO::Socket::UNIX;
    }; if ($@) {
	# �Ȥ��ʤ���
	die "Tiarra control socket is not available for this environment.\n";
    }

    my $this = {
	sockname => $sockname,
	filename => TIARRA_CONTROL_ROOT.'/'.$sockname,
	server_sock => undef, # ExternalSocket
	clients => [], # ControlPort::Session
	session_handle_hook => undef, # RunLoop::Hook
    };
    bless $this,$class;
    $this->open;

    $this;
}

sub open {
    my $this = shift;
    my $filename = $this->{filename};

    # �ǥ��쥯�ȥ�/tmp/tiarra-control��̵����к�롣
    if (!-d TIARRA_CONTROL_ROOT) {
	mkdir TIARRA_CONTROL_ROOT or die 'Couldn\'t make directory '.TIARRA_CONTROL_ROOT;
	# ¾�Υ桼���������褦�ˤ��롣
	# �ǽ�˺��������桼���������ե������ä����Ȥ�����뤬���н�ˡ�ʤ���
	chmod 01777, TIARRA_CONTROL_ROOT;
    }

    # �����åȤ�����¸�ߤ���������³���Ƥߤ롣
    if (-e $filename) {
	my $sock = IO::Socket::UNIX->new(
	    Peer => $filename,
	   );
	if (!defined $sock) {
	    # �⤦�Ȥ��Ƥ��ʤ�?
	    unlink $filename;
	    undef $sock;
	}
    }

    # �ꥹ�˥��ѥ����åȤ򳫤���
    my $sock = IO::Socket::UNIX->new(
	Type => &SOCK_STREAM,
	Local => $filename,
	Listen => 1);
    if (!defined $sock) {
	die "Couldn't make socket $filename: $!";
    }
    # �ѡ��ߥå�����700�ˡ�
    chmod 0700, $filename;
    $this->{server_sock} =
	ExternalSocket->new(
	    Socket => $sock,
	    Read => sub {
		my $server = shift->sock;
		my $client = $server->accept;
		if (defined $client) {
		    push @{$this->{clients}},ControlPort::Session->new($client);
		}
	    },
	    Write => sub{},
	    WantToWrite => sub{undef})->install;

    # ���å����ϥ�ɥ��ѤΥեå��򤫤��롣
    $this->{session_handle_hook} =
	RunLoop::Hook->new(
	    'ControlPort Session Handler',
	    sub {
		# ���å�������
		foreach my $client (@{$this->{clients}}) {
		    $client->main;
		}
		# ��λ�������å�������
		@{$this->{clients}} = grep {
		    $_->is_alive;
		} @{$this->{clients}};
	    })->install;

    $this->{destructor} = Tiarra::TerminateManager::Hook->new(
	sub {
	    $this->destruct;
	})->install;

    $this;
}

sub destruct {
    my $this = shift;

    # ����
    if (defined $this->{server_sock}) {
	eval {
	    $this->{server_sock}->disconnect;
	};
    }

    # ���Υ����åȥե��������
    unlink $this->{filename};

    # �ǥ��쥯�ȥ�˥����åȤ���Ĥ�̵���ʤä��顢���Υǥ��쥯�ȥ��ä��롣
    rmdir TIARRA_CONTROL_ROOT;

    $this;
}

package ControlPort::Session;
use strict;
use warnings;
use Tiarra::Socket::Lined;
use base qw(Tiarra::Socket::Lined);

sub new {
    # $sock: IO::Socket
    my ($class,$sock) = @_;
    my $this = $class->SUPER::new(name => 'ControlPort::Session');
    $this->{method} = undef; # GET�ޤ���NOTIFY
    $this->{module} = undef; # Log::Channel�ʤɡ�'::'�ϥᥤ��ץ�����ɽ����
    $this->{header} = undef; # {key => value}
    $this->{input_is_frost} = 0; # ����ʾ�����Ϥ�̵�뤹�뤫��
    bless $this,$class;
    $this->attach($sock);
    $this->install;
}

sub main {
    my $this = shift;

    while (defined($_ = $this->pop_queue)) {
	s/^\s*|\s*$//g;
	my $line = $_;

	if ($this->{input_is_frost}) {
	    last;
	}

	if (defined $this->{header}) {
	    # $this->{header}��¸�ߤ���Ȥ������Ȥϡ��ǽ�Υꥯ�����ȹԤϤ⤦������ä���
	    if ($line eq '') {
		# ���ιԤ����ꥯ�����Ƚ���ꡣ
		$this->respond;
	    }
	    else {
		if ($line =~ m/^(.+?)\s*:\s*(.+)$/) {
		    $this->{header}{$1} = $2;
		}
		else {
		    $this->reply(401,'Bad Request');
		}
	    }
	}
	else {
	    if ($line =~ m|^(.+?)\s+(.+?)\s+TIARRACONTROL/(\d+)\.(\d+)$|) {
		$this->{method} = $1;
		$this->{module} = $2;
		if (!{GET => 1,NOTIFY => 1}->{$this->{method}}) {
		    $this->reply(501,'Method Not Implemented');
		}
		my $version = "$3.$4";
		if ($version > 1.0) {
		    $this->reply(401,'Bad Request');
		}
		$this->{header} = {};
	    }
	    else {
		$this->reply(401,'Bad Request');
	    }
	}
    }
}

sub reply {
    # $code: 204�ʤ�
    # $str: No Content�ʤ�
    # $header: {key => value} ��ά�ġ�ʸ�������ɤ�UTF-8��Sender��Charset�����ס�
    my ($this,$code,$str,$header) = @_;

    $this->append_line("TIARRACONTROL/1.0 $code $str");
    $this->append_line('Sender: Tiarra #'.&::version);
    my $unijp = Tiarra::Encoding->new;
    if (defined $header) {
	while (my ($key,$value) = each %$header) {
	    $this->append_line($unijp->set("$key: $value")->conv($this->charset));
	}
    }
    $this->append_line('Charset: '.$this->long_charset);
    $this->append_line('');
    $this->disconnect_after_writing;
}

sub charset {
    # �ꥯ�����ȤǼ�����ä�Charset���顢Unicode::Japanese���󥳡��ǥ���̾���֤���
    my $this = shift;

    if (!defined $this->{header}) {
	return 'utf8';
    }

    my $charset = $this->{header}->{Charset};
    if (!defined $charset) {
	return 'utf8';
    }

    my $charset_table = {
	'Shift_JIS' => 'sjis',
	'EUC-JP' => 'euc',
	'ISO-2022-JP' => 'jis',
	'UTF-8' => 'utf8',
    };
    $charset_table->{$charset} || 'utf8';
}

sub long_charset {
    my $this = shift;

    my $table = {
	'sjis' => 'Shift_JIS',
	'euc' => 'EUC-JP',
	'jis' => 'ISO-2022-JP',
	'utf8' => 'UTF-8',
    };
    $table->{$this->charset} || 'UTF-8';
}

sub is_alive {
    shift->connected;
}

sub respond {
    my $this = shift;

    my $req = ControlPort::Request->new($this->{method},$this->{module});
    my $charset = $this->charset;
    my $unijp = Tiarra::Encoding->new;
    while (my ($key,$value) = each %{$this->{header}}) {
	next if $key eq 'Charset';
	$req->$key($unijp->set($value,$charset)->utf8);
    }

    my $rep = eval {
	if ($req->module eq '::') {
	    # �⥸�塼��"::"�ϥᥤ��ץ�����ɽ����
	    # ��ǡ�
	    die qq{Controlling '::' is not supported yet.\n};
	}
	else {
	    # ���Τ褦�ʥ⥸�塼���¸�ߤ��뤫��
	    my $mod = ModuleManager->shared->get($req->module);
	    if (defined $mod) {
		my $reply = $mod->control_requested($req);
		if (!defined $reply) {
		    die $this->{module}."->control_requested returned undef.\n";
		}
		elsif (!$reply->isa('ControlPort::Reply')) {
		    die $this->{module}."->control_requested returned bad ref: ".ref($reply)."\n";
		}
		else {
		    $reply;
		}
	    }
	    else {
		die qq{Module $this->{module} doesn't exist.\n};
	    }
	}
    };
    if ($@) {
	(my $detail = $@) =~ s/\n//g;
	$this->reply(500,'Internal Server Error',{Detail => $detail});
    }
    else {
	$this->reply($rep->code,$rep->status,$rep->table);
    }
}

package ControlPort::Packet;
use strict;
use warnings;
our $AUTOLOAD;
use Tiarra::Utils ();
Tiarra::Utils->define_attr_getter(0, qw(table));

sub new {
    my $class = shift;
    my $this = {
	table => {}, # {key => value}
    };
    bless $this,$class;
}

sub AUTOLOAD {
    my ($this,$value) = @_;
    if ($AUTOLOAD =~ /::DESTROY$/) {
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    if (defined $value) {
	$this->{table}{$key} = $value;
    }
    $this->{table}{$key};
}

package ControlPort::Request;
use strict;
use warnings;
use base qw(ControlPort::Packet);
use Tiarra::Utils ();
Tiarra::Utils->define_attr_getter(0, qw(method module));

sub new {
    my ($class,$method,$module) = @_;
    my $this = $class->SUPER::new;
    $this->{method} = $method;
    $this->{module} = $module;
    $this;
}

package ControlPort::Reply;
use strict;
use warnings;
use base qw(ControlPort::Packet);
use Tiarra::Utils ();
Tiarra::Utils->define_attr_getter(0, qw(code status));

sub new {
    # $code: 204�ʤ�
    # $status: No Content�ʤ�
    my ($class,$code,$status) = @_;
    my $this = $class->SUPER::new;
    $this->{code} = $code;
    $this->{status} = $status;
    $this;
}

1;
