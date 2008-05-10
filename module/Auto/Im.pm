package Auto::Im;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Tools::DateConvert);
use Auto::Utils;
use Tools::DateConvert;
use Mask;

use LWP::UserAgent;
use HTTP::Request::Common;

# �ǥե��������
my $DATE_FORMAT = '%H:%M';
my $FORMAT = '#(date) << #(from.name|from.nick|from.nick.now) >> #(message)';
my $SUBJECT = 'Message from IRC';

sub new {
  my ($class) = shift;
  my $this = $class->SUPER::new(@_);

  my ($user) = $this->config->user;
  $this->{user} = $user;

  return $this;
}

sub destruct {
    my $this = shift;
    # �⥸�塼�뤬���פˤʤä����˸ƤФ�롣
    # ����ϥ⥸�塼��Υǥ��ȥ饯���Ǥ��롣���Υ᥽�åɤ��ƤФ줿���DESTROY�������
    # �����ʤ�᥽�åɤ�ƤФ�����̵���������ޡ�����Ͽ�������ϡ����Υ᥽�åɤ�
    # ��Ǥ����äƤ���������ʤ���Фʤ�ʤ���
    # ������̵����
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # �����С�����Υ�å���������
  if ($sender->isa('IrcIO::Server')) {
      # PRIVMSG����
      if ($msg->command eq 'PRIVMSG') {
          my ($get_ch_name,$reply_in_ch,$reply_as_priv,$reply_anywhere, $get_full_ch_name)
          = Auto::Utils::generate_reply_closures($msg,$sender,\@result);
          
          my $full_ch_name = $get_full_ch_name->();

          my ($str, $who, $text) = split(/\s+/, $msg->param(1), 3);

          if (Mask::match_deep([$this->config->keyword('all')], $str)) {
              # ���פ��Ƥ�����
              LWP::UserAgent->new->request( POST "http://im.kayac.com/api/post/$this->{user}",
                  [ message => "[tiarra][$full_ch_name] $str $who $text" ]
              );
              #$this->_send($msg, $sender, $who, $text, $get_ch_name, $reply_anywhere);
          }
      }
  }

  return @result;
}

1;

=pod
info: ̾�����ƤФ��ȡ�����ȯ����im.kayac.com����������
default: off

# ȿ�����륭����ɤ���ꤷ�ޤ���,���ڤ��ʣ������Ǥ���褦�Ǥ�
keyword: hoge

# im.kayac.com����Ͽ�����桼��̾�����Ϥ��ޤ���
# im.kayac.com�ˤĤ��Ƥ� http://im.kayac.com/#docs �򻲹ͤˤ��Ƥ���������
user: username

=cut
