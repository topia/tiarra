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
