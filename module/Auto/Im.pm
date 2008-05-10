# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Im;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::AliasDB Tools::HTTPClient);
use Auto::AliasDB;
use Tools::HTTPClient; # >= r11345
use HTTP::Request::Common;

sub new {
  my ($class) = shift;
  my $this = $class->SUPER::new(@_);

  if ($this->config->secret) {
      # signature required
      require Digest::SHA;
  }

  my $regex = join '|', (
      (map { "(?:$_)" } $this->config->regex_keyword('all')),
      (map { "(?i:\Q$_\E)" } map { split /,/ } $this->config->keyword('all')),
     );
  eval {
      $this->{regex} = qr/$regex/;
  }; if ($@) {
      $this->_runloop->notify_error($@);
  }

  return $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # �����С�����Υ�å���������
  if ($sender->isa('IrcIO::Server')) {
      # PRIVMSG����
      if ($msg->command eq 'PRIVMSG') {
	  my $text = $msg->param(1);
	  my $full_ch_name = $msg->param(0);

	  if ($text =~ $this->{regex} && Mask::match_deep_chan(
	      [$this->config->mask('all')],$msg->prefix,$full_ch_name)) {

	      my $url = "http://im.kayac.com/api/post/" . $this->config->user;
	      my $text = Auto::AliasDB->stdreplace(
		  $msg->prefix,
		  $this->config->format || '[tiarra][#(channel):#(nick.now)] #(text)',
		  $msg, $sender,
		  channel => $full_ch_name,
		  text => $text,
		 );
	      my @data = (message => $text);
	      if ($this->config->secret) {
		  push(@data, sig => Digest::SHA->new(1)
			   ->add($text . $this->config->secret)->hexdigest);
	      } elsif ($this->config->password) {
		  push(@data, password => $this->config->password);
	      }
	      my $runloop = $this->_runloop;
	      Tools::HTTPClient->new(
		  Request => POST($url, \@data),
		 )->start(
		     Callback => sub {
			 my $stat = shift;
			 $runloop->notify_warn(__PACKAGE__." post failed: $stat")
			     unless ref($stat);
			 ## FIXME: check response (should check 'error')
		     },
		    );
	  }
      }
  }

  return @result;
}

1;

=pod
info: ̾�����ƤФ��ȡ�����ȯ����im.kayac.com����������
default: off

# ȿ������ͤΥޥ�������ꤷ�ޤ���
# ��ά�����������ȿ�����ޤ���
mask: * *!*@*

# ȿ�����륭����ɤ�����ɽ���ǻ��ꤷ�ޤ���
# ʣ�����ꤷ��������ʣ���Ի��ꤷ�Ƥ���������
-regex-keyword: (?i:fugahoge)

# ȿ�����륭����ɤ���ꤷ�ޤ���
# ʣ�����ꤷ��������,(�����)�Ƕ��ڤ뤫��ʣ���Ի��ꤷ�Ƥ���������
keyword: hoge

# im.kayac.com �������å������Υե����ޥåȤ���ꤷ�ޤ���
# �ǥե������: [tiarra][#(channel):#(nick.now)] #(text)
format: [tiarra][#(channel):#(nick.now)] #(text)

# im.kayac.com����Ͽ�����桼��̾�����Ϥ��ޤ���
# im.kayac.com�ˤĤ��Ƥ� http://im.kayac.com/#docs �򻲹ͤˤ��Ƥ���������
user: username

# im.kayac.com����̩��ǧ�ڤ����򤷤��������ꤷ�Ƥ���������
# ��ά�����ǧ�ڤʤ��ˤʤ�ޤ���
-secret: some secret

# im.kayac.com�ǥѥ����ǧ�ڤ����򤷤��������ꤷ�Ƥ���������
# ��ά�����ǧ�ڤʤ��ˤʤ�ޤ���
# secret ��ξ�����ꤷ������ secret ��ͥ�褵��Ƥ��ޤ���
-password: some password

=cut
