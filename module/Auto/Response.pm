# -*- cperl -*-
# $Clovery: tiarra/module/Auto/Response.pm,v 1.7 2003/07/27 07:09:52 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Auto::Response;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Auto::AliasDB::CallbackUtils Tools::GroupDB);
use Auto::Utils;
use Auto::AliasDB::CallbackUtils;
use Tools::GroupDB;
use Mask;
use Multicast;

sub new {
  my ($class) = @_;
  my $this = $class->SUPER::new;
  $this->{database} = Tools::GroupDB->new($this->config->file, 'pattern', $this->config->charset, 1, 1);

  return $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  # �����С�����Υ�å���������
  if ($sender->isa('IrcIO::Server')) {
    # PRIVMSG����
    if ($msg->command eq 'PRIVMSG') {
      my @matches = $this->{database}->find_groups_with_primary($msg->param(1));
      if (@matches) {
	my ($callbacks) = [];
	Auto::AliasDB::CallbackUtils::register_extcallbacks($callbacks, $msg, $sender);
	my (undef,undef,undef,$reply_anywhere,$get_full_ch_name)
	  = Auto::Utils::generate_reply_closures($msg, $sender, \@result, undef, $callbacks);

	if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix, $get_full_ch_name->())) {
	  # ���פ��Ƥ�����
	  foreach my $match (@matches) {
	    # mask�����פ��ʤ���м¹Ԥ��ʤ������Ф���
	    my $mask = Tools::GroupDB::get_array($match, 'mask');
	    next if ($mask && !Mask::match_deep_chan($mask, $msg->prefix, $get_full_ch_name->()));
	    # rate�ʲ��ʤ�м¹Ԥ��ʤ������Ф���
	    my $rate = Tools::GroupDB::get_value($match, 'rate');
	    next unless !defined($rate) || (int(rand(100)) < $rate);
	    $reply_anywhere->(Tools::GroupDB::get_value_random($match, 'response'));
	  }
	}
      }
    }
  }

  return @result;
}

1;

=pod
info: �ǡ����ե�����λ���ˤ������ä�ȿ�����롣
default: off

# ���̤�ȿ���ǡ������������Τ˸����Ƥ��ޤ���

# �ǡ����ե�����Υե����ޥå�
# | pattern: re:^(����(��)?����)
# | rate: 90
# | mask: * *!*@*
# | #plum: mask: *!*@*
# | response: ����ˤ��ϡ�
# | response: ����ä��㤤�ޤ���
# |
# | pattern: ���䤹��
# | rate: 20
# | response: ���䤹�ߤʤ�����
# pattern�ϰ�Ԥ����񤱤ޤ���(��ȴ��
# mask��rate���ά�Ǥ��ޤ�����ά��������mask��������rate��100�Ȥʤ�ޤ���
# response��ʣ���񤤤Ƥ����Х���������򤵤�ޤ���

# �ǡ����ե�����
file: response.txt

# ʸ��������
charset: euc

# ���Ѥ���Ĥ����&�����ͥ�Υޥ�����
mask: * *!*@*
# plum: mask: +*!*@*
=cut
