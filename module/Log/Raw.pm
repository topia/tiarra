# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Log::Raw;
use strict;
use warnings;
use IO::File;
use File::Spec;
use Tiarra::Encoding;
use base qw(Module);
use Module::Use qw(Tools::DateConvert Log::Writer);
use Tools::DateConvert;
use Log::Writer;
use ControlPort;
use Mask;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{matching_cache} = {}; # <servername,fname>
    $this->{writer_cache} = {}; # <server,Log::Writer>
    $this->{sync_command} = do {
	my $sync = $this->config->sync;
	if (defined $sync) {
	    uc $sync;
	}
	else {
	    undef;
	}
    };
    $this;
}

sub sync {
    my $this = shift;
    $this->flush_all_file_handles;
    RunLoop->shared->notify_msg("Raw logs synchronized.");
}

sub control_requested {
    my ($this,$request) = @_;
    if ($request->ID eq 'synchronize') {
	$this->sync;
	ControlPort::Reply->new(204,'No Content');
    }
    else {
	die ref($this)." received control request of unsupported ID ".$request->ID."\n";
    }
}

sub message_arrived {
    my ($this,$message,$sender) = @_;

    # sync��ͭ���ǡ����饤����Ȥ��������ä���å������Ǥ��ꡢ���ĺ���Υ��ޥ�ɤ�sync�˰��פ��Ƥ��뤫��
    if (defined $this->{sync_command} &&
	$sender->isa('IrcIO::Client') &&
	$message->command eq $this->{sync_command}) {
	# �����Ƥ���ե����������flush��
	# ¾�Υ⥸�塼���Ʊ�����ޥ�ɤ�sync���뤫���Τ�ʤ��Τǡ�
	# do-not-send-to-servers => 1�����ꤹ�뤬
	# ��å��������Τ��˴����Ƥ��ޤ�ʤ���
	$this->sync;
	$message->remark('do-not-send-to-servers',1);
	return $message;
    }
    $message;
}

sub message_io_hook {
    my ($this,$message,$io,$type) = @_;

    # break with last
    while (1) {
	last unless $io->server_p;
	last unless Mask::match_deep([Mask::array_or_all(
	    $this->config->command('all'))], $message->command);
	my $msg = $message->clone;
	if ($this->config->resolve_numeric && $message->command =~ /^\d{3}$/) {
	    $msg->command(
		(NumericReply::fetch_name($message->command)||'undef').
		    '('.$message->command.')');
	}
	my $server = $io->network_name;
	my $dirname = $this->_server_match($server);
	if (defined $dirname) {
	    my $prefix  = sprintf '(%s/%s) ', $server, do {
		if ($type eq 'in') {
		    'recv';
		} elsif ($type eq 'out') {
		    'send';
		} else {
		    '----';
		}
	    };

	    my $charset = do {
		if ($io->can('out_encoding')) {
		    $io->out_encoding;
		} else {
		    $this->config->charset;
		}
	    };
	    if ($msg->have_raw_params) {
		$msg->encoding_params('binary');
		$charset = 'binary';
	    }
	    $this->_write($server, $dirname, $msg->time, $prefix .
			      $msg->serialize($this->config->charset));
	}
	last;
    }

    return $message;
}

sub _server_match {
    my ($this,$server) = @_;

    my $cached = $this->{matching_cache}->{$server};
    if (defined $cached) {
	if ($cached eq '') {
	    # cache of not found
	    return undef;
	}
	else {
	    return $cached;
	}
    }

    foreach my $line ($this->config->server('all')) {
	my ($name, $mask) = split /\s+/, $line, 2;
	if (Mask::match($mask,$server)) {
	    # �ޥå�������
	    my $fname_format = $this->config->filename || '%Y.%m.%d.txt';
	    my $fpath_format = $name."/$fname_format";

	    $this->{matching_cache}->{$server} = $fpath_format;
	    return $fpath_format;
	}
    }
    $this->{matching_cache}->{$server} = '';
    undef;
}

sub _write {
    # ���ꤵ�줿���ե�����˥إå��դ����ɵ����롣
    # �ǥ��쥯�ȥ�̾�����դΥޥ�����ִ�����롣
    my ($this,$channel,$abstract_fpath,$time,$line) = @_;
    my $concrete_fpath = do {
	my $basedir = $this->config->directory;
	if (defined $basedir) {
	    Tools::DateConvert::replace("$basedir/$abstract_fpath", $time);
	}
	else {
	    Tools::DateConvert::replace($abstract_fpath, $time);
	}
    };
    my $header = Tools::DateConvert::replace(
	$this->config->header || '%H:%M',
	$time,
       );
    my $always_flush = do {
	if ($this->config->keep_file_open) {
	    if ($this->config->always_flush) {
		1;
	    } else {
		0;
	    }
	} else {
	    1;
	}
    };
    # �ե�������ɵ�
    my $make_writer = sub {
	Log::Writer->shared_writer->find_object(
	    $concrete_fpath,
	    always_flush => $always_flush,
	    file_mode_oct => $this->config->mode,
	    dir_mode_oct => $this->config->dir_mode,
	   );
    };
    my $writer = sub {
	# ����å����ͭ������
	if ($this->config->keep_file_open) {
	    # ���Υ����ͥ�ϥ���å��夵��Ƥ��뤫��
	    my $cached_elem = $this->{writer_cache}->{$channel};
	    if (defined $cached_elem) {
		# ����å��夵�줿�ե�����ѥ��Ϻ���Υե�����Ȱ��פ��뤫��
		if ($cached_elem->uri eq $concrete_fpath) {
		    # ���Υե�����ϥ�ɥ������Ѥ����ɤ���
		    #print "$concrete_fpath: RECYCLED\n";
		    return $cached_elem;
		}
		else {
		    # �ե�����̾���㤦�����դ��Ѥ�ä����ξ�硣
		    # �Ť��ե�����ϥ�ɥ���Ĥ��롣
		    #print "$concrete_fpath: recached\n";
		    eval {
			$cached_elem->flush;
			$cached_elem->unregister;
		    };
		    # �����ʥե�����ϥ�ɥ��������
		    $cached_elem = $make_writer->();
		    if (defined $cached_elem) {
			$cached_elem->register;
		    }
		    return $cached_elem;
		}
	    }
	    else {
		# ����å��夵��Ƥ��ʤ��Τǡ��ե�����ϥ�ɥ���äƥ���å��塣
		#print "$concrete_fpath: *cached*\n";
		my $cached_elem =
		    $this->{writer_cache}->{$channel} =
			$make_writer->();
		if (defined $cached_elem) {
		    $cached_elem->register;
		}
		return $cached_elem;
	    }
	}
	else {
	    # ����å���̵����
	    return $make_writer->();
	}
    }->();
    if (defined $writer) {
	$writer->reserve("$header $line\n");
    } else {
	# XXX: do warn with properly frequency
	#RunLoop->shared_loop->notify_warn("can't write to $concrete_fpath: ".
	#				      "$header $line");
    }
}

1;

=pod
info: �����ФȤ������̿�����¸����
default: off

# Log�ϤΥ⥸�塼��Ǥϡ��ʲ��Τ褦�����դ������ִ����Ԥʤ��롣
# %% : %
# %Y : ǯ(4��)
# %m : ��(2��)
# %d : ��(2��)
# %H : ����(2��)
# %M : ʬ(2��)
# %S : ��(2��)

# ������¸����ǥ��쥯�ȥꡣTiarra����ư�������֤�������Хѥ���~����ϻȤ��ʤ���
directory: rawlog

# �ƹԤΥإå��Υե����ޥåȡ���ά���줿��'%H:%M'��
header: %H:%M:%S

# �ե�����̾�Υե����ޥåȡ���ά���줿��'%Y.%m.%d.txt'
filename: %Y-%m-%d.txt

# ���ե�����Υ⡼��(8�ʿ�)����ά���줿��600
mode: 600

# ���ǥ��쥯�ȥ�Υ⡼��(8�ʿ�)����ά���줿��700
dir-mode: 700

# �ȤäƤ���ʸ�������ɤ��褯�狼��ʤ��ä��Ȥ���ʸ�������ɡ���ά���줿��utf8��
# ���֤󤳤λ��꤬�����뤳�ȤϤʤ��Ȼפ��ޤ����ġġ�
charset: jis

# NumericReply ��̾�����褷��ɽ������(�����Ȥ��� dump �Ǥ�̵���ʤ�ޤ�)
resolve-numeric: 1

# �����륳�ޥ�ɤ�ɽ���ޥ�������ά���줿�鵭Ͽ���������Υ��ޥ�ɤ�Ͽ���롣
command: *,-ping,-pong

# �ƥ��ե�����򳫤��äѤʤ��ˤ��뤫�ɤ�����
# ���Υ��ץ�����¿���ξ�硢�ǥ����������������ޤ��Ƹ�Ψ�ɤ�������¸���ޤ���
# ����Ͽ���٤����ƤΥե�����򳫤����ޤޤˤ���Τǡ�50��100�Υ����ͥ��
# �̡��Υե�����˥�����褦�ʾ��ˤϻȤ��٤��ǤϤ���ޤ���
# ���� fd �����դ줿��硢���饤����Ȥ���(�ޤ��ϥ����Ф�)��³�Ǥ��ʤ���
# �����ʥ⥸�塼�����ɤǤ��ʤ������������Ǥ��ʤ��ʤɤξɾ����������ǽ����
# ����ޤ���limit �ξܺ٤ˤĤ��Ƥ� OS ���Υɥ�����Ȥ򻲾Ȥ��Ƥ���������
-keep-file-open: 1

# keep-file-open ���˳ƹԤ��Ȥ� flush ���뤫�ɤ�����
# open/close ����٤ϵ��ˤʤ뤬�����ϼ��������ʤ��͸�����
# keep-file-open ��ͭ���Ǥʤ��ʤ�̵�뤵��(1�ˤʤ�)�ޤ���
-always-flush: 0

# keep-file-open��ͭ���ˤ�����硢ȯ�����٤˥��ե�������ɵ�����ΤǤϤʤ�
# �����ʬ�̤�ί�ޤäƤ���񤭹��ޤ�롣���Τ��ᡢ�ե�����򳫤��Ƥ�
# �Ƕ��ȯ���Ϥޤ��񤭹��ޤ�Ƥ��ʤ���ǽ�������롣
# sync�����ꤹ��ȡ�¨�¤˥���ǥ������˽񤭹��ि��Υ��ޥ�ɤ��ɲä���롣
# ��ά���줿���ϥ��ޥ�ɤ��ɲä��ʤ���
sync: sync

# �ƥ����Ф����ꡣ������̾����ʬ�ϥޥ����Ǥ��롣
# ���Ҥ��줿����Ǹ��������Τǡ����ƤΥ����Ф˥ޥå�����"*"�ʤɤϺǸ�˽񤫤ʤ���Фʤ�ʤ���
# ���ꤵ�줿�ǥ��쥯�ȥ꤬¸�ߤ��ʤ��ä��顢����˺���롣
# �ե����ޥåȤϼ����̤ꡣ
# channel: <�ǥ��쥯�ȥ�̾> <������̾�ޥ���>
# ��:
# filename: %Y-%m-%d.txt
# server: ircnet ircnet
# server: others *
# ������Ǥϡ�ircnet�Υ���ircnet/%Y.%m.%d.txt�ˡ�
# ����ʳ��Υ���others/%Y.%m.%d.txt����¸����롣
server: ircnet ircnet
server: others *
=cut
