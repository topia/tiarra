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

# デフォルト設定
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
    # モジュールが不要になった時に呼ばれる。
    # これはモジュールのデストラクタである。このメソッドが呼ばれた後はDESTROYを除いて
    # いかなるメソッドも呼ばれる事が無い。タイマーを登録した場合は、このメソッドが
    # 責任を持ってそれを解除しなければならない。
    # 引数は無し。
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # サーバーからのメッセージか？
  if ($sender->isa('IrcIO::Server')) {
      # PRIVMSGか？
      if ($msg->command eq 'PRIVMSG') {
          my ($get_ch_name,undef,undef,$reply_anywhere)
          = Auto::Utils::generate_reply_closures($msg,$sender,\@result);

          my ($str, $who, $text) = split(/\s+/, $msg->param(1), 3);

          if (Mask::match_deep([$this->config->keyword('all')], $str)) {
              # 一致していた。
              LWP::UserAgent->new->request( POST "http://im.kayac.com/api/post/$this->{user}",
                  [ message => "[tiarra] $str $who $text" ]
              );
              #$this->_send($msg, $sender, $who, $text, $get_ch_name, $reply_anywhere);
          }
      }
  }

  return @result;
}

1;

=pod
info: 名前が呼ばれると、その発言をim.kayac.comに送信する
=cut
