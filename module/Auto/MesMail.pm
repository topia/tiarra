# -*- cperl -*-
# $Clovery: tiarra/module/Auto/MesMail.pm,v 1.7 2003/07/27 07:24:44 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Auto::MesMail;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Auto::AliasDB Tools::DateConvert Tools::MailSend);
use Auto::Utils;
use Auto::AliasDB;
use Tools::DateConvert;
use Tools::MailSend;
use Mask;

# �ǥե��������
my $DATE_FORMAT = '%H:%M';
my $FORMAT = '#(date) << #(from.name|from.nick|from.nick.now) >> #(message)';
my $SUBJECT = 'Message from IRC';

sub new {
  my ($class) = @_;
  my $this = $class->SUPER::new;

  $this->{from_addr} = sub {
    my ($user, $host) = split(/\@/, $_[0], 2);
    $user = (getpwuid($>))[0] || '' unless $user;
    if ($host) {
      substr($host, 0, 0) = '@';
    } else {
      $host = ''
    }
    return ($user . $host);
  }->($this->config->from);

  my ($use_pop3) = $this->config->use_pop3;
  $use_pop3 = 1 if ($use_pop3 =~ /yes/i) || ($use_pop3 !~ /0/);
  $this->{use_pop3} = $use_pop3;

  return $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # �����С�����Υ�å���������
  if ($sender->isa('IrcIO::Server')) {
    # PRIVMSG����
    if ($msg->command eq 'PRIVMSG') {
      my ($get_ch_name,undef,undef,$reply_anywhere)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

      my ($str, $who, $text) = split(/\s+/, $msg->param(1), 3);

      if (Mask::match_deep([$this->config->send('all')], $str)) {
	# ���פ��Ƥ�����
	if (Mask::match_deep_chan([$this->config->mask('all')], $msg->prefix(), $get_ch_name->())) {
	  $this->_send($msg, $sender, $who, $text, $get_ch_name, $reply_anywhere);
	} else {
	  foreach my $reply ($this->config->deny('all')) {
	    $reply_anywhere->($reply);
	  }
	}
      }
    }
  }

  return @result;
}

sub _send {
  my ($this, $msg, $sender, $who, $text, $get_ch_name, $reply_anywhere) = @_;
  my (@sended_addr, @sended_who);
  my ($max_send) = $this->config->max_send_addresses;

  foreach my $name (split(/\,/, $who)) {
    next if grep{$_ eq $name;} @sended_who;
    push(@sended_who, $name);
    my ($to) = Auto::AliasDB->shared->find_alias([$this->config->alias_key('all')], [$name]);
    my ($alias) = {};

    $alias->{'who'} = $name;
    if (!defined ($to)) {
      foreach my $reply ($this->config->unknown('all')) {
	$reply_anywhere->($reply, %$alias);
      }
    } elsif ($to->{'mail'}) {
      next if grep{$_ == $to->{'mail'};} @sended_addr;
      push(@sended_addr, $to->{'mail'});
      my ($time) = time();
      $alias->{'date'} = 
	Tools::DateConvert::replace(Auto::AliasDB::get_value($to, 'mail_date') || 
				    $this->config->date || $DATE_FORMAT, $time);
      $alias->{'message'} = $text;
      $this->_mail_send_reserve($msg, $sender, $alias, $to, $get_ch_name, $reply_anywhere, $time);
      if (defined($max_send)) {
	last if scalar(@sended_addr) >= $max_send;
      }
    } else {
      foreach my $reply ($this->config->none_address('all')) {
	$reply_anywhere->($reply, %$alias);
      }
    }
  }
}

sub _mail_send_reserve {
  my ($this, $msg, $sender, $alias, $to, $get_ch_name, $reply_anywhere, $time) = @_;

  my ($subject) = Auto::AliasDB::get_value($to, 'mail_subject');
  $subject = $this->config->subject || $SUBJECT unless $subject;

  return Tools::MailSend->shared->
    mail_send(
	      use_pop3 => $this->{use_pop3},
	      pop3_host => $this->config->pop3host,
	      pop3_port => $this->config->pop3port,
	      pop3_user => $this->config->pop3user,
	      pop3_pass => $this->config->pop3pass,
	      pop3_expire => $this->config->pop3_expire,
	      smtp_host => $this->config->smtphost,
	      smtp_port => $this->config->smtpport,
	      smtp_fqdn => $this->config->smtp_fqdn,
	      sender => 'Auto::MesMail::' . $msg->prefix(),
	      priority => 0,
	      env_from => $this->{from_addr},
	      env_to => [Tools::MailSend::parse_mailaddrs(@{Auto::AliasDB::get_array($to, 'mail')})],
	      from => $this->config->from_header || $this->config->from || $this->{from_addr},
	      to => Auto::AliasDB::get_value($to, 'mail'),
	      subject => $subject,
	      data_type => Tools::MailSend::DATA_TYPES->{inner_iter},
	      data => \&_data,
	      reply_ok => \&_reply_ok,
	      reply_error => \&_reply_error,
	      reply_fatal => \&_reply_fatal,
	      local => 
	      {
	       this => $this,
	       alias => $alias,
	       from => 
	       Auto::AliasDB::concat_string_to_key(
				      Auto::AliasDB->shared->
				        find_alias_with_stdreplace($msg->nick, 
								   $msg->name, 
								   $msg->host,
								   $msg->prefix,
								   1 # public
								  ), 'from.'),
	       to => 
	       Auto::AliasDB->shared->
	         remove_private(
				Auto::AliasDB::concat_string_to_key($to, 'to.'),
				'to.'),
	       reply_anywhere => $reply_anywhere,
	       time => $time,
	       replacer => sub {
		 my ($str, %extra_replaces) = @_;

		 Auto::AliasDB->shared->
		     stdreplace(
				$msg->prefix || $sender->fullname,
				$str,
				$msg,
				$sender,
				%extra_replaces,
				'channel' => $get_ch_name->());
	       },
	      },
	     );
}

sub _data {
  my ($struct, $socksend) = @_;

  my $this = $struct->{local}->{this};
  my $alias = $struct->{local}->{alias};
  my $from = $struct->{local}->{from};
  my $to = $struct->{local}->{to};
  my $replacer = $struct->{local}->{replacer};

  my @format = Auto::AliasDB::get_array($to, 'mail_format');
  @format = $this->config->format('all') unless @format;
  @format = $FORMAT unless @format;

  foreach my $send_line (@format) {
    $socksend->($replacer->($send_line, %$from, %$to, %$alias));
  }
}

sub _reply_error {
  my ($struct, $state, $line, $info) = @_;
  # ���ѼԤ�error���֤��᥽�åɡ�$info�ˤ��������Ԥ�mail address���ޤޤ��Ϥ�������
  # channel�˸����ä�mail address���󤹤뤳�Ȥˤʤ�Τǻ��Ѥ��ʤ����Ȥ򴫤�롣
  # �ʤ���from/to�ˤ�private���ꤵ�줿��Τϴޤޤ�ʤ���

  # state�ˤϼ��Ԥ����Ȥ��ξ��֤��Ϥ��졢'error-mail' �� 'fatalerror-connect' �Τ褦��
  # �����̾ܺ٥�å�������������뤳�Ȥ�����롣

  my $this = $struct->{local}->{this};
  my $alias = $struct->{local}->{alias};
  my $from = $struct->{local}->{from};
  my $to = $struct->{local}->{to};
  my $reply_anywhere = $struct->{local}->{reply_anywhere};

  my @replys = $this->config->get('error-' . lc($state), 'all');
  @replys = $this->config->error('all') unless @replys;
  foreach my $reply (@replys) {
    $reply_anywhere->($reply, %$from, %$to, %$alias,
		      state => $state,
		      line => $line,
		      info => $info
		     );
  }
}

sub _reply_fatal {
  my ($struct, $state, $line, $info) = @_;
  # ���ѼԤ�error���֤��᥽�åɡ�$info�ˤ��������Ԥ�mail address���ޤޤ��Ϥ�������
  # channel�˸����ä�mail address���󤹤뤳�Ȥˤʤ�Τǻ��Ѥ��ʤ����Ȥ򴫤�롣
  # �ʤ���from/to�ˤ�private���ꤵ�줿��Τϴޤޤ�ʤ���

  # state�ˤϼ��Ԥ����Ȥ��ξ��֤��Ϥ��졢'error-mail' �� 'fatalerror-connect' �Τ褦��
  # �����̾ܺ٥�å�������������뤳�Ȥ�����롣

  # fatal ��1�����ԤˤĤ�1�Ĥ����֤����(�Ϥ�)��

  my $this = $struct->{local}->{this};
  my $alias = $struct->{local}->{alias};
  my $from = $struct->{local}->{from};
  my $to = $struct->{local}->{to};
  my $reply_anywhere = $struct->{local}->{reply_anywhere};

  # user notfound
  my @replys = $this->config->get('fatalerror-' . lc($state), 'all');
  @replys = $this->config->fatalerror('all') unless @replys;
  foreach my $reply (@replys) {
    $reply_anywhere->($reply, %$from, %$to, %$alias,
		      state => $state,
		      line => $line,
		      info => $info
		     );
  }
}

sub _reply_ok {
  my ($struct) = @_;
  # ���ѼԤ�accept���֤��᥽�åɡ�
  # from/to�ˤ�private���ꤵ�줿��Τϴޤޤ�ʤ���

  my $this = $struct->{local}->{this};
  my $alias = $struct->{local}->{alias};
  my $from = $struct->{local}->{from};
  my $to = $struct->{local}->{to};
  my $reply_anywhere = $struct->{local}->{reply_anywhere};

  foreach my $reply ($this->config->accept('all')) {
    $reply_anywhere->($reply, %$from, %$alias, %$to);
  }
}

1;

=pod
info: ������᡼��Ȥ����������롣
default: off

# �᡼�륢�ɥ쥹�ϥ����ꥢ���� mail �򻲾Ȥ��ޤ���

# From���ɥ쥹��[default: OS�Υ桼��̾]
from: example1@example.jp

# �����ѤΥ������ [default: mesmail_send]
send: ®ã����

# ���Ѥ���Ĥ����&�����ͥ�Υޥ�����
# ���Tiarra�⡼�ɻ��� [default: �ʤ�]
mask: * +*!*@*
# [plum-mode] mask: +*!*@*

# mask�ǵ��ݤ��줿�Ȥ��Υ�å����� [default: �ʤ�]
deny: �����������ʤ���

# ���٤�����밸����� [default: ̵����]
max-send-address: 5

# �����õ�������ꥢ������ȥ� [default: �ʤ�]
alias-key: name
alias-key: nick

# ����οͤ�Ƚ�̽���ʤ��ä��Ȥ��Υ�å����� [default: �ʤ�]
unknown: #(who)����ȸ����Τ�ï�Ǥ���?

# �᡼������շ���
date: %H:%M:%S

# �����ꥢ���ϸ��դ��ä�����ɥ᡼�륢�ɥ쥹����Ͽ����Ƥ��ʤ��ä��Ȥ��Υ�å������� [default: �ʤ�]
-none-address: #(who)����ϥ��ɥ쥹����Ͽ���Ƥ��ޤ���

# SMTP�Υۥ��� [default: localhost]
-smtphost: localhost

# SMTP�Υݡ��� [default: smtp(25)]
-smtpport: 25

# SMTP�Ǽ��ۥ��Ȥ�FQDN [default: localhost]
-smtpfqdn: localhost

# ��������᡼��δ����̾(�����ꥢ�������Բ�) [default: Message from IRC]
-subject: Message from IRC

# ��������᡼�����ʸ [default: #(date) << #(from.name|from.nick|from.nick.now) >> #(message)]
-format: #(date)��#(from.name|from.nick|from.nick.now)���󤫤�#(message)�Ȥ��������Ǥ���

# ���������Ȥ��Υ�å������� [default: �ʤ�]
accept: #(who)�����#(message)���������Ƥ����ޤ�����

# ---- POP before SMTP �λ��� ----
# POP before SMTP��Ȥ��� [default: no]
-use-pop3: yes

# POP before SMTP�Υ����ॢ���Ȼ���(ʬ)��ʬ����ʤ����ϻ��ꤷ�ʤ����ɤ��� [default: 0]
-pop3-expire: 4

# POP�Υۥ��ȡ� [default: localhost]
-pop3host: localhost

# POP�Υݡ��ȡ� [default: pop(110)]
-pop3port: 110

# POP�Υ桼�� [default: OS�Υ桼��̾]
-pop3user: example1

# POP�Υѥ���� [default: ���ѥ����('')]
-pop3pass: test-password

# ---- ���顼��å����������� ----

# ���̥��顼��
# error-[state] �ȸ��������Ǿܺ٥��顼��å����������Ǥ��롣
# [state]�ϡ�
#    * mailfrom(�᡼��������Ԥ���ꤷ�褦�Ȥ��ƥ��顼)
#    * rcptto(�᡼������������ꤷ�褦�Ȥ��ƥ��顼)
#    * norcptto(�᡼��������褬����̵���ʤä�)
#    * data(�᡼�����Ȥ��������褦�Ȥ��ƥ��顼)
#    * finish(�᡼�����Ȥ����������饨�顼)
# �����롣�ä��ߤ����ʤ����error-[state]�ϻ��ꤷ�ʤ��Ƥ⹽��ʤ���
# ��å�������Ф������ʤ��ʤ���Ȥ�̵������ȥ����ꤹ����ɤ���
# error-[state]�����ꤵ��Ƥʤ���������� error ��Ȥ��� [default: ̤���]

-error-rcptto:
-error-norcptto: #(who)����ˤ�����ޤ���Ǥ����������Ǥ���᡼�륢�ɥ쥹������ޤ���
-error-data: �᡼�뤬�����Ǥ��ޤ���DATA���ޥ�ɤ˼��Ԥ��ޤ�����#(line;�����б���:%s|;)
-error: �᡼���������顼�Ǥ���#(line;�����б���:%s|;)#(state; on %s|;)

# ��̿Ū�ʥ��顼���᡼��˸��̤ʥ��顼�ǤϤʤ��Τ�������(��prefix)���1��å����������롣
# fatalerror-[state]
# [state]:
#    * first(��³���顼)
#    * helo(SMTP���å����򳫻Ͻ���ʤ�)
# �����롣�ä��ߤ����ʤ����fatalerror-[state]�ϻ��ꤷ�ʤ��Ƥ⹽��ʤ���
# ��å�������Ф������ʤ��ʤ���Ȥ�̵������ȥ����ꤹ����ɤ���
# fatalerror-[state]�����ꤵ��Ƥʤ���������� fatalerror ��Ȥ��� [default: ̤���]

-fatalerror-first: SMTP�����Ф���³�Ǥ��ޤ���
-fatalerror: SMTP���å�������̿Ū�ʥ��顼������ޤ�����#(line; �����б���:%s|;)#(state; on %s|;)
=cut
