# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Tools::MailSend::EachServer;
use strict;
use warnings;
use Module::Use qw(Tools::DateConvert);
use Tools::DateConvert;
use RunLoop;
use LinedINETSocket;
use Tiarra::Encoding;

my $E_MAIL_EOL = "\x0d\x0a";

# constant
my $STATE_NONE = 0;
my $STATE_POP3 = 1;
my $STATE_SMTP = 2;

my $DATA_TYPE_ARRAY = 0;
my $DATA_TYPE_INNER_ITER = 1;

sub new {
    my ($class, %data) = @_;

    return undef unless defined($data{'cleaner'});

    my $this = {
	use_pop3  => 0,
	pop3_host => 'localhost',
	pop3_port => getservbyname('pop3', 'tcp') || 110,
	pop3_user => (getpwuid($>))[0],
	pop3_pass => '',
	pop3_expire => 0,

	smtp_host => 'localhost',
	smtp_port => getservbyname('smtp', 'tcp') || 25,
	smtp_fqdn => 'localhost',

	# cleaner is destruction function.
	cleaner => undef,

	# parent local datas
	local => undef,

	expire_time => undef,
	state => undef,
	# undef: not found
	# other: $STATE_*

	local_state => undef,
	# undef: not found
	# other: unknown.

	queue => [],

	sock => undef,

	esmtp_capable => [],

	hook => undef,

	timer => undef,

    };

    # failsafe timer
    $this->{timer} = 
	Timer->new(
	    Interval => 5,
	    Repeat => 1,
	    Code => sub {
		my ($timer) = @_;
		$this->main_loop();
	    }
	   )->install;

    bless $this, $class;

    foreach my $key (keys %data) {
	$this->_set_data($key, $data{$key});
    }

    return $this;
}

#--- constant ---
sub DATA_TYPES {
    return {
	array => $DATA_TYPE_ARRAY,		# data に送信行の raw data を渡す。
	inner_iter => $DATA_TYPE_INNER_ITER,	# data にコールバック関数を渡す。
    };
}

#--- server info ---
sub get_data {
    my ($this, $name) = @_;

    return undef unless 
	grep {$name eq $_} 
	    (qw(local cleaner use_pop3), 
	     (map { 'pop3_' . $_ } qw(host port user pass expire)), 
	     (map { 'smtp_' . $_ } qw(host port fqdn)));
    return $this->{$name};
}

sub _set_data {
    my ($this, $name, $value) = @_;

    return undef unless 
	grep {$name eq $_} 
	    (qw(local cleaner use_pop3), 
	     (map { 'pop3_' . $_ } qw(host port user pass expire)), 
	     (map { 'smtp_' . $_ } qw(host port fqdn)));

    $this->{$name} = $value;
    return 1;
}

sub mail_send_reserve {
    my ($this, %arg) = @_;

    return 1 unless $arg{'env_from'};
    return 1 unless $arg{'env_to'};
    return 1 unless $arg{'data'};

    push(@{$this->{queue}}, {
	# local
	local       => $arg{'local'},

	# sender
	sender      => $arg{'sender'} || undef,

	# queue priority
	priority    => $arg{'priority'} || 0,

	# envelope from
	env_from    => $arg{'env_from'},

	# envelope to [array]
	env_to      => $arg{'env_to'},

	# header from
	from        => $arg{'from'},

	# header to
	to          => $arg{'to'} || undef,

	# header subject
	subject     => $arg{'subject'} || undef,

	# data type [0=array, 1=inner_iter]
	data_type   => $arg{'data_type'},

	# data <code_ref, array_ref, scalar>
	data        => $arg{'data'},

	# reply ok <code_ref, undef>
	reply_ok    => $arg{'reply_ok'} || \&_do_nothing,

	# reply error <code_ref, undef>
	reply_error => $arg{'reply_error'} || \&_do_nothing,

	# reply fatal <code_ref, undef>
	reply_fatal => $arg{'reply_fatal'} || \&_do_nothing,
    });
    # if state is undef (not processing), start.
    $this->{state} = $STATE_NONE unless defined($this->{state});
    # continue_loop
    $this->main_loop();

    return 0;
}

sub _do_nothing {
    # noop func
}

sub clean {
    my ($this) = @_;

    $this->{cleaner}->($this);
    undef $this->{cleaner};
    $this->{hook}->uninstall if defined($this->{hook});
    $this->{hook} = undef;
    $this->{timer}->uninstall if defined($this->{timer});
    $this->{timer} = undef;
}

sub main_loop {
    my ($this) = @_;
    my ($state) = $this->{state};

    if (!defined($state)) {
	# if undef, nothing to process
	if (!defined($this->{expire_time}) || $this->{expire_time} < time()) {
	    return $this->clean();
	}
	return;
    }
    # activate hook
    if (!defined($this->{hook})) {
	$this->{hook} = RunLoop::Hook->new(
	    sub {
		my ($hook) = @_;
		$this->main_loop();
	    })->install('before-select');
    }

    if ($state == $STATE_NONE) {
	$state = $STATE_SMTP; # fallback
	if ($this->{use_pop3} && !defined($this->{expire_time})) {
	    $state = $STATE_POP3;
	}
    }

    $this->{state} = $state;

    if ($state == $STATE_POP3) {
	$this->_state_pop3();
    } elsif ($state == $STATE_SMTP) {
	$this->_state_smtp();
    }
}


# --- pop3 ---
sub _state_pop3 {
    my ($this) = @_;

    if (!defined($this->{sock})) {
	$this->{sock} = $this->_open_pop3();
	if (!defined($this->{sock})) {
	    RunLoop->shared->notify_warn('mesmail: cannot connect pop3, but start smtp.');
	    $this->{state} = $STATE_SMTP;
	    return;
	} else {
	    $this->{local_state} = 'FIRST';
	}
    }
    while ($this->_do_pop3()) {
	# noop
    };
}


sub _open_pop3 {
    my ($this) = @_;
    my ($host, $port, $sock);

    $host = $this->{pop3_host};
    $port = $this->{pop3_port};

    $sock = LinedINETSocket->new($E_MAIL_EOL)->connect($host, $port);

    return undef unless (defined $sock);
    return $sock;
}

sub _do_pop3 {
    my ($this) = @_;
    my ($local_state) = $this->{local_state};
    my ($sock) = $this->{sock};

    # wait +OK
    my ($line) = $sock->pop_queue();
    return 0 unless defined($line); # none data received
    if (substr($line, 0, 3) ne '+OK') {
	# error
	RunLoop->shared->notify_warn('mesmail: pop3 send command "'.$local_state.'" reply is not OK...');
	RunLoop->shared->notify_warn('mesmail: message is ' . $line);
	RunLoop->shared->notify_warn('mesmail: but start smtp.');
	$this->_close_pop3();
	return undef;
    } else {
	if ($local_state eq 'FIRST') {
	    # send USER
	    $this->{local_state} = 'USER';
	    $sock->send_reserve('USER ' . $this->{pop3_user});
	} elsif ($local_state eq 'USER') {
	    # send PASS
	    $this->{local_state} = 'PASS';
	    $sock->send_reserve('PASS ' . $this->{pop3_pass});
	} elsif ($local_state eq 'PASS') {
	    # send STAT
	    $this->{local_state} = 'STAT';
	    $sock->send_reserve("STAT");
	} elsif ($local_state eq 'STAT') {
	    # close pop3
	    $this->{expire_time} = time() + ($this->{pop3_expire} * 60);
	    $this->_close_pop3();
	    return 0;
	}
	return 1;
    }
    return 0; # this return is not used
}

sub _close_pop3 {
    my ($this) = @_;
    my ($sock) = $this->{sock};

    $sock->send_reserve('QUIT');
    $sock->disconnect_after_writing();
    $sock->flush(); # flush
    $this->{sock} = undef;
    $this->{local_state} = undef;
    $this->{state} = $STATE_SMTP;

    $this->main_loop();

    return undef;
}


# --- smtp ---
sub _state_smtp {
    my ($this) = @_;

    if (!defined($this->{sock})) {
	$this->{sock} = $this->_open_smtp();
	if (!defined($this->{sock})) {
	    $this->_reply_smtp_error(undef, 'CONNECT'); # undef is all
	    $this->{state} = undef;
	    return;
	} else {
	    $this->{local_state} = 'FIRST';
	}
    }
    while ($this->_do_smtp()) {
	# noop
    }
}

sub _open_smtp {
    my ($this) = @_;
    my ($host, $port, $sock);

    $host = $this->{smtp_host};
    $port = $this->{smtp_port};

    $sock = LinedINETSocket->new($E_MAIL_EOL)->connect($host, $port);

    return undef unless (defined $sock);
    return $sock;
}

sub _do_smtp {
    my ($this, $input) = @_;
    my ($local_state) = $this->{local_state};
    my ($sock) = $this->{sock};
    my $line;

    if (defined($input)) {
	$line = $input;
    } else {
	$line = $sock->pop_queue();
    }
    return 1 unless defined($line); # queue is empty
    my ($reply) = substr($line, 0, 4);
    if ($local_state eq 'FIRST') {
	# first reply: server info.
	if ($reply eq '220 ') {
	    # message end
	    $this->{local_state} = 'EHLO';
	    $sock->send_reserve('EHLO ' . $this->{smtp_fqdn});
	} else {
	    # error
	    $this->_reply_smtp_error(undef, $local_state, $line); # all stack
	    $this->_close_smtp();
	    $this->clean();
	}
    } elsif ($local_state eq 'EHLO') {
	if ($reply eq '250-') {
	    push(@{$this->{esmtp_capable}}, substr($line, 5));
	} elsif ($reply eq '250 ') {
	    # end of esmtp capable
	    push(@{$this->{esmtp_capable}}, substr($line, 5));
	    # ここでHELOと処理を一本化するためにSTART_MAILとしてrecursive.
	    $this->{local_state} = 'START_MAIL';
	    return $this->_do_smtp('THROUGH');
	} else {
	    # error. use HELO instead of EHLO
	    $this->{local_state} = 'HELO';
	    $sock->send_reserve('HELO ' . $this->{smtp_fqdn});
	}
    } elsif ($local_state eq 'HELO') {
	if ($reply eq '250 ') {
	    # ここでEHLOと処理を一本化するためにSTART_MAILとしてrecursive.
	    $this->{local_state} = 'START_MAIL';
	    return $this->_do_smtp('THROUGH');
	} else {
	    # error
	    $this->_reply_smtp_error(undef, $local_state, $line); # all stack
	    $this->_close_smtp();
	    $this->clean();
	}
    } elsif ($local_state eq 'START_MAIL') {
	# initialize mail

	$this->{queue}->[0]->{rcpt_ok_addrs} = 0;
	$this->{queue}->[0]->{to_seps} = [@{$this->{queue}->[0]->{env_to}}]; # duplicate

	$this->{local_state} = 'MAILFROM';
	$sock->send_reserve('MAIL FROM:<' . $this->{queue}->[0]->{env_from} . '>');
    } elsif ($local_state eq 'MAILFROM') {
	if ($reply eq '250 ') {
	    # initialize rcpt
	    my ($newaddr) = shift(@{$this->{queue}->[0]->{to_seps}});
	    $this->{local_state} = 'RCPTTO';
	    $sock->send_reserve('RCPT TO:<' . $newaddr . '>');
	} else {
	    #error
	    $this->_reply_smtp_error(0, $local_state, $line);
	    return $this->_smtp_send_final(); # smtp mail send が終了したものとみなす。
	}
    } elsif ($local_state eq 'RCPTTO') {
	my ($newaddr);
	if ($reply eq '551 ') {
	    # more simple
	    $line =~ /\<([^\<\>]*)\>/;
	    $newaddr = $1;
	} elsif ($reply =~ /25[01] /) {
	    $this->{queue}->[0]->{rcpt_ok_addrs}++;
	    $newaddr = shift(@{$this->{queue}->[0]->{to_seps}});
	} else {
	    # error
	    $line =~ /\<([^\<\>]*)\>/; # use mail_address entry for error msg.
	    $this->_reply_smtp_error(0, $local_state, $line, $1);
	    # 無視して次へ。
	    $newaddr = shift(@{$this->{queue}->[0]->{to_seps}});
	}
	if (defined($newaddr)) {
	    $sock->send_reserve('RCPT TO:<' . $newaddr . '>');
	} else {
	    if ($this->{queue}->[0]->{rcpt_ok_addrs}) {
		# ok.
		$this->{local_state} = 'DATA';
		$sock->send_reserve('DATA');
	    } else {
		# no rcpt addrs.
		# error は既にメッセージを返している。
		$this->_reply_smtp_error(0, 'NORCPTTO');
		return $this->_smtp_send_final(); # smtp mail send が終了したものとみなす。
	    }
	}
    } elsif ($local_state eq 'DATA') {
	if ($reply eq '354 ') {
	    # go ahead
	    my ($struct) = $this->{queue}->[0];

	    $sock->send_reserve('To: ' .  $struct->{to});
	    foreach my $send_line 
		(&mime_unstructured_header_array(
		    "Subject: " . Tiarra::Encoding->new($struct->{subject})->euc)) {
		    $sock->send_reserve($send_line);
		}
	    $sock->send_reserve('MIME-Version: 1.0');
	    $sock->send_reserve('Content-Type: text/plain; charset=iso-2022-jp');
	    $sock->send_reserve('Content-Transfer-Encoding: 7bit');
	    $sock->send_reserve('Message-Id: ' . do {
		# message-id	:= '<' time(epoc) rand-value '.' pid '.' envelope-from '>'
		# time		:= epoc time (now)
		# rand-value	:= [0-9]{,6}
		# pid		:= [1-9][0-9]*
		# envelope-from	:= email-addr
		# example: Message-Id: <1046695839413024.2151.topia@clovery.jp>
		'<' . time().int(rand()*1000000).".$$.".$struct->{env_from}.'>';
	    });
	    $sock->send_reserve('Date: ' . do {
		# example: Tue, 04 Mar 2003 11:10:24 +0900
		Tools::DateConvert::replace('%a, %d %b %Y %H:%M:%S %z', time());
	    });
	    $sock->send_reserve('From: ' . $struct->{from}) if defined($struct->{from});
	    $sock->send_reserve('');

	    my ($socksend) = sub {
		foreach my $send_line (@_) {
		    $send_line =~ s/[\x0d\x0a]+//;
		    $send_line = '..=' if $send_line eq '.';
		    $sock->send_reserve(Tiarra::Encoding->new($send_line)->h2zKana->jis);
		}
		$sock->flush();
	    };

	    if ($struct->{data_type} == $DATA_TYPE_ARRAY) {
		$socksend->(@$struct->{data});
	    } elsif ($struct->{data_type} == $DATA_TYPE_INNER_ITER) {
		$struct->{data}->($struct, $socksend);
	    }

	    $sock->send_reserve('.');
	    $this->{local_state} = 'FINISH';
	} else {
	    $this->_reply_smtp_error(0, $local_state, $line);
	}
    } elsif ($local_state eq 'FINISH') {
	if ($reply eq '250 ') {
	    # finalize
	    $this->_reply_smtp_ok(0);
	    return $this->_smtp_send_final();
	} else {
	    # error
	    $this->_reply_smtp_error(0, $local_state, $line);
	    return $this->_smtp_send_final();
	}
    } else {
	die 'unknown LOCAL_STATE "' . $local_state . '".';
    }

    return 1;
}

sub _smtp_send_final {
    my ($this) = @_;

    shift(@{$this->{queue}});
    if (@{$this->{queue}}) {
	# more queue.
	if (scalar(@{$this->{queue}}) != 1 && (grep {$_->{priority} != 0} @{$this->{queue}})) {
	    # have key having priority. and queue isn't single.
	    @{$this->{queue}} = sort { $a->{priority} <=> $b->{priority}} @{$this->{queue}};
	}
	# START_MAILにしてrecursive.
	$this->{local_state} = 'START_MAIL';
	return $this->_do_smtp('THROUGH');
    } else {
	# close smtp
	$this->_close_smtp();
	$this->{hook}->uninstall;
	$this->{hook} = undef;
    }
}

sub _close_smtp {
    my ($this) = @_;
    my ($sock) = $this->{sock};

    $sock->send_reserve('QUIT');
    $sock->disconnect_after_writing();
    $sock->flush(); # flush
    $this->{sock} = undef;
    $this->{local_state} = undef;
    $this->{state} = undef;
    $this->{esmtp_capable} = [];

    return undef;
}

sub _reply_smtp_error {
  my ($this, $session, $state, $line, $info) = @_;
  # 使用者にerrorを返すメソッド。$infoには送信失敗のmail addressが含まれるはずだが、
  # channelに向かってmail addressを広報することになるので使用しないことを勧める。
  # なお、from/toにはprivate指定されたものは含まれない。

  # stateには失敗したときの状態が渡され、'error-mail' や 'fatalerror-connect' のように
  # 状態別詳細メッセージを定義することが出来る。

  # fatalerror は1送信者につき1つだけ返される(はず)。

  if (defined($session)) {
    my $struct = $this->{queue}->[$session];
    $struct->{reply_error}->($struct, $state, $line, $info);
  } else {
    my (@sended_from);
    foreach my $struct (@{$this->{queue}}) {
      next if grep{$_ == $struct->{sender};} @sended_from;
      push(@sended_from, $struct->{sender});

      $struct->{reply_fatal}->($struct, $state, $line, $info);
    }
  }
}

sub _reply_smtp_ok {
  my ($this, $session) = @_;
  # 使用者にacceptを返すメソッド。
  # from/toにはprivate指定されたものは含まれない。

  my $struct = $this->{queue}->[$session];

  $struct->{reply_ok}->($struct);
}

sub mime_unstructured_header_array {
  return split(/\n/, mime_unstructured_header(@_));
}

# contrib
no strict; # i don't want fix these functions.

# $str を encoded-word に変換し $line に追加する

$ascii = '[\x00-\x7F]';
$twoBytes = '[\x8E\xA1-\xFE][\xA1-\xFE]';
$threeBytes = '\x8F[\xA1-\xFE][\xA1-\xFE]';

sub add_encoded_word {
  my($str, $line) = @_;
  my $result = '';

  while (length($str)) {
    my $target = $str;
    $str = '';
    if (length($line) + 22 +
	($target =~ /^(?:$twoBytes|$threeBytes)/o) * 8 > 76) {
      $line =~ s/[ \t\n\r]*$/\n/;
      $result .= $line;
      $line = ' ';
    }
    while (1) {
      my $encoded = '=?ISO-2022-JP?B?' .
	Tiarra::Encoding->new($target, 'euc')->h2zKana->conv('jis', 'base64') . '?=';
      if (length($encoded) + length($line) > 76) {
	$target =~ s/($threeBytes|$twoBytes|$ascii)$//o;
	$str = $1 . $str;
      } else {
	$line .= $encoded;
	last;
      }
    }
  }
  $result . $line;
}

# unstructured header $header を MIMEエンコードする
# add_encoded_word() については上のスクリプトを参照

sub mime_unstructured_header {
  my $oldheader = shift;
  my($header, @words, @wordstmp, $i) = ('');
  my $crlf = $oldheader =~ /\n$/;
  $oldheader =~ s/\s+$//;
  @wordstmp = split /\s+/, $oldheader;
  for ($i = 0; $i < $#wordstmp; $i++) {
    if ($wordstmp[$i] !~ /^[\x21-\x7E]+$/ and
	$wordstmp[$i + 1] !~ /^[\x21-\x7E]+$/) {
      $wordstmp[$i + 1] = "$wordstmp[$i] $wordstmp[$i + 1]";
    } else {
      push(@words, $wordstmp[$i]);
    }
  }
  push(@words, $wordstmp[-1]);
  foreach $word (@words) {
    if ($word =~ /^[\x21-\x7E]+$/) {
      $header =~ /(?:.*\n)*(.*)/;
      if (length($1) + length($word) > 76) {
	$header .= "\n $word";
      } else {
	$header .= $word;
      }
    } else {
      $header = add_encoded_word($word, $header);
    }
    $header =~ /(?:.*\n)*(.*)/;
    if (length($1) == 76) {
      $header .= "\n ";
    } else {
      $header .= ' ';
    }
  }
  $header =~ s/\n? $//mg;
  $crlf ? "$header\n" : $header;
}

1;
