# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Log::Channel;
use strict;
use warnings;
use IO::File;
use File::Spec;
use Unicode::Japanese;
use base qw(Module);
use Module::Use qw(Tools::DateConvert Log::Logger Log::Writer);
use Tools::DateConvert;
use Log::Logger;
use Log::Writer;
use ControlPort;
use Mask;
use Multicast;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new;
    $this->{channels} = []; # ���Ǥ�[�ǥ��쥯�ȥ�̾,�ޥ���]
    $this->{matching_cache} = {}; # <�����ͥ�̾,�ե�����̾>
    $this->{writer_cache} = {}; # <�����ͥ�̾,Log::Writer>
    $this->{sync_command} = do {
	my $sync = $this->config->sync;
	if (defined $sync) {
	    uc $sync;
	}
	else {
	    undef;
	}
    };
    $this->{distinguish_myself} = do {
	my $conf_val = $this->config->distinguish_myself;
	if (defined $conf_val) {
	    $conf_val;
	}
	else {
	    1;
	}
    };
    $this->{logger} =
	Log::Logger->new(
	    sub {
		$this->_search_and_write(@_);
	    },
	    $this,
	    'S_PRIVMSG','C_PRIVMSG','S_NOTICE','C_NOTICE');

    $this->_init;
}

sub _init {
    my $this = shift;
    foreach ($this->config->channel('all')) {
	my ($dirname,$mask) = split /\s+/;
	if (!defined($dirname) || $dirname eq '' ||
	    !defined($mask) || $mask eq '') {
	    die 'Illegal definition in '.__PACKAGE__."/channel : $_\n";
	}
	push @{$this->{channels}},[$dirname,$mask];
    }

    $this;
}

sub sync {
    my $this = shift;
    $this->flush_all_file_handles;
    RunLoop->shared->notify_msg("Channel logs synchronized.");
}

sub control_requested {
    my ($this,$request) = @_;
    if ($request->ID eq 'synchronize') {
	$this->sync;
	ControlPort::Reply->new(204,'No Content');
    }
    else {
	die "Log::Channel received control request of unsupported ID ".$request->ID."\n";
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

    # __PACKAGE__/command�˥ޥå����뤫��
    if (Mask::match(lc($this->config->command || '*'),lc($message->command))) {
	$this->{logger}->log($message,$sender);
    }

    $message;
}

*S_PRIVMSG = \&PRIVMSG_or_NOTICE;
*S_NOTICE = \&PRIVMSG_or_NOTICE;
*C_PRIVMSG = \&PRIVMSG_or_NOTICE;
*C_NOTICE = \&PRIVMSG_or_NOTICE;
sub PRIVMSG_or_NOTICE {
    my ($this,$msg,$sender) = @_;
    my $target = Multicast::detatch($msg->param(0));
    my $is_priv = Multicast::nick_p($target);
    my $cmd = $msg->command;

    my $line = do {
	if ($is_priv) {
	    # priv�λ��ϼ�ʬ������ɬ�����̤��롣
	    if ($sender->isa('IrcIO::Client')) {
		sprintf(
		    $cmd eq 'PRIVMSG' ? '>%s< %s' : ')%s( %s',
		    $msg->param(0),
		    $msg->param(1));
	    }
	    else {
		sprintf(
		    $cmd eq 'PRIVMSG' ? '-%s- %s' : '=%s= %s',
		    $msg->nick || $sender->current_nick,
		    $msg->param(1));
	    }
	}
	else {
	    my $format = do {
		if ($this->{distinguish_myself} && $sender->isa('IrcIO::Client')) {
		    $cmd eq 'PRIVMSG' ? '>%s:%s< %s' : ')%s:%s( %s';
		}
		else {
		    $cmd eq 'PRIVMSG' ? '<%s:%s> %s' : '(%s:%s) %s';
		}
	    };
	    my $nick = do {
		if ($sender->isa('IrcIO::Client')) {
		    RunLoop->shared_loop->network(
		      (Multicast::detatch($msg->param(0)))[1])
			->current_nick;
		}
		else {
		    $msg->nick || $sender->current_nick;
		}
	    };
	    sprintf $format,$msg->param(0),$nick,$msg->param(1);
	}
    };

    [$is_priv ? 'priv' : $msg->param(0),$line];
}

sub _channel_match {
    # ���ꤵ�줿�����ͥ�̾�˥ޥå��������¸�ե�����Υѥ�������������õ����
    # ��Ĥ�ޥå����ʤ����undef���֤���
    # ���Υ᥽�åɤϸ�����̤�$this->{matching_cache}����¸���ơ���˺����Ѥ��롣
    my ($this,$channel) = @_;

    my $cached = $this->{matching_cache}->{$channel};
    if (defined $cached) {
	if ($cached eq '') {
	    # �ޥå����륨��ȥ��¸�ߤ��ʤ����Ȥ�����̤�����å��夵��Ƥ��롣
	    return undef;
	}
	else {
	    return $cached;
	}
    }

    foreach my $ch (@{$this->{channels}}) {
	if (Mask::match($ch->[1],$channel)) {
	    # �ޥå�������
	    my $fname_format = $this->config->filename || '%Y.%m.%d.txt';
	    my $fpath_format = $ch->[0]."/$fname_format";

	    $this->{matching_cache}->{$channel} = $fpath_format;
	    return $fpath_format;
	}
    }
    $this->{matching_cache}->{$channel} = '';
    undef;
}

sub _search_and_write {
    my ($this,$channel,$line) = @_;
    my $dirname = $this->_channel_match($channel);
    if (defined $dirname) {
	$this->_write($channel,$dirname,$line);
    }
}

sub _write {
    # ���ꤵ�줿���ե�����˥إå��դ����ɵ����롣
    # �ǥ��쥯�ȥ�̾�����դΥޥ�����ִ�����롣
    my ($this,$channel,$abstract_fpath,$line) = @_;
    my $concrete_fpath = do {
	my $basedir = $this->config->directory;
	if (defined $basedir) {
	    Tools::DateConvert::replace("$basedir/$abstract_fpath");
	}
	else {
	    Tools::DateConvert::replace($abstract_fpath);
	}
    };
    my $header = Tools::DateConvert::replace(
	$this->config->header || '%H:%M'
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
		    $cached_elem->register;
		    return $cached_elem;
		}
	    }
	    else {
		# ����å��夵��Ƥ��ʤ��Τǡ��ե�����ϥ�ɥ���äƥ���å��塣
		#print "$concrete_fpath: *cached*\n";
		my $cached_elem =
		    $this->{writer_cache}->{$channel} =
			$make_writer->();
		$cached_elem->register;
		return $cached_elem;
	    }
	}
	else {
	    # ����å���̵����
	    return $make_writer->();
	}
    }->();
    if (defined $writer) {
	$writer->reserve(
	    Unicode::Japanese->new("$header $line\n",'utf8')->conv(
		$this->config->charset || 'jis'));
    }
}

sub flush_all_file_handles {
    my $this = shift;
    foreach my $cached_elem (values %{$this->{writer_cache}}) {
	eval {
	    $cached_elem->flush;
	};
    }
}

sub destruct {
    my $this = shift;
    # �����Ƥ������Ƥ�Log::Writer���Ĥ��ơ�����å������ˤ��롣
    foreach my $cached_elem (values %{$this->{writer_cache}}) {
	eval {
	    $cached_elem->flush;
	    $cached_elem->unregister;
	};
    }
    %{$this->{writer_cache}} = ();
}

1;

=pod
info: �����ͥ��priv�Υ�����⥸�塼�롣
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
directory: log

# ���ե������ʸ�������ɡ���ά���줿��jis��
charset: sjis

# �ƹԤΥإå��Υե����ޥåȡ���ά���줿��'%H:%M'��
header: %H:%M:%S

# �ե�����̾�Υե����ޥåȡ���ά���줿��'%Y.%m.%d.txt'
filename: %Y.%m.%d.txt

# ���ե�����Υ⡼��(8�ʿ�)����ά���줿��600
mode: 600

# ���ǥ��쥯�ȥ�Υ⡼��(8�ʿ�)����ά���줿��700
dir-mode: 700

# �����륳�ޥ�ɤ�ɽ���ޥ�������ά���줿�鵭Ͽ���������Υ��ޥ�ɤ�Ͽ���롣
command: privmsg,join,part,kick,invite,mode,nick,quit,kill,topic,notice

# PRIVMSG��NOTICE��Ͽ����ݤˡ���ʬ��ȯ����¾�ͤ�ȯ���ǥե����ޥåȤ��Ѥ��뤫�ɤ�����1/0���ǥե���Ȥ�1��
distinguish-myself: 1

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

# �ƥ����ͥ�����ꡣ�����ͥ�̾����ʬ�ϥޥ����Ǥ��롣
# �ĿͰ��Ƥ�����줿PRIVMSG��NOTICE�ϥ����ͥ�̾"priv"�Ȥ��Ƹ�������롣
# ���Ҥ��줿����Ǹ��������Τǡ����ƤΥ����ͥ�˥ޥå�����"*"�ʤɤϺǸ�˽񤫤ʤ���Фʤ�ʤ���
# ���ꤵ�줿�ǥ��쥯�ȥ꤬¸�ߤ��ʤ��ä��顢Log::Channel�Ϥ���򾡼�˺�롣
# �ե����ޥåȤϼ����̤ꡣ
# channel: <�ǥ��쥯�ȥ�̾> (<�����ͥ�̾> / 'priv')
# ��:
# filename: %Y.%m.%d.txt
# channel: IRCDanwasitu #IRC���ü�@ircnet
# channel: others *
# ������Ǥϡ�#IRC���ü�@ircnet�Υ���IRCDanwasitu/%Y.%m.%d.txt�ˡ�
# ����ʳ�(priv��ޤ�)�Υ���others/%Y.%m.%d.txt����¸����롣
channel: priv priv
channel: others *
=cut
