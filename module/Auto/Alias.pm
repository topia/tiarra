# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Alias;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::AliasDB Auto::Utils);
use Auto::AliasDB;
use Auto::Utils;
use Mask;

sub new {
  my $class = shift;
  my $this = $class->SUPER::new(@_);
  Auto::AliasDB::setfile($this->config->alias,
			 $this->config->alias_encoding);
  $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  if ($msg->command eq 'PRIVMSG') {

    if (Mask::match($this->config->confirm,$msg->param(1))) {
      # ���οͤΥ����ꥢ���������priv���֤���
      my (undef,undef,$reply_as_priv,undef,undef)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result, 0); # Alias conversion disable.

      my $alias = Auto::AliasDB->shared->find_alias_prefix($msg->prefix);
      if (defined $alias) {
	while (my ($key,$values) = each %$alias) {
	  map {
	    $reply_as_priv->("$key: $_");
	  } @$values;
	}
      }
    }
    else {
      my (undef,undef,undef,$reply_anywhere,undef)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result, 1);

      my $msg_from_modifier_p = sub {
	  !defined $msg->prefix ||
	      Mask::match_deep([Mask::array_or_all($this->config->modifier('all'))],
			       $msg->prefix);
      };

      my ($temp) = $msg->param(1);
      $temp =~ s/^\s*(.+)\s*$/$1/;
      my ($keyword,$key,$value)
	= split(/\s+/, $temp, 3);

      if(Mask::match($this->config->get('add'),$keyword)) {
	if ($msg_from_modifier_p->() && defined $key && defined $value) {
	  if (Auto::AliasDB->shared->add_value_with_prefix($msg->prefix, $key, $value)) {
	    if (defined $this->config->added_format && $this->config->added_format ne '') {
	      $reply_anywhere->($this->config->added_format, 'key' => $key, 'value' => $value);
	    }
	  }
	}
      }
      elsif (Mask::match($this->config->get('remove'),$keyword)) {
	if ($msg_from_modifier_p->() && defined $key) {
	  my $count = Auto::AliasDB->shared->del_value_with_prefix($msg->prefix, $key, $value);
	  if ($count) {
	    if (defined $this->config->removed_format && $this->config->removed_format ne '') {
	      $reply_anywhere->($this->config->removed_format, 'key' => $key, 'value' => $value, 'count' => $count);
	    }
	  }
	}
      }
    }
  }
  return @result;
}

1;

=pod
info: �桼�������ꥢ������δ�����Ԥʤ��ޤ���
default: off

# �����ꥢ���ϴ���Ū��name,user����ĤΥե�����ɤ������äƤ��ꡢ
# ���줾��桼����̾���桼�����ޥ�����ɽ���ޤ���

# �����ꥢ������ե�����Υѥ��ȡ����Υ��󥳡��ǥ��󥰡�
# ���Υե�����ϼ��Τ褦�ʥե����ޥåȤǤ��롣
# 1. ���줾��ιԤϡ�<����>: <��>�פη����Ǥ��롣
# 2. ���ιԤǡ��ƥ桼��������ڤ롣
# 3. <��>�ϥ���ޤǶ��ڤ���ʣ�����ͤȤ���롣
#
# �����ꥢ������ե��������:
#
# name: sample
# user: *!*sample@*.sample.net
#
# name: sample2,[sample2]
# user: *!sample2@*.sample.net,*!sample2@*.sample2.net
#
alias: alias.txt
alias-encoding: euc

# ����ȯ���򤷤��ͤΥ����ꥢ������Ͽ����Ƥ���С������priv�����롣
confirm: �����ꥢ����ǧ

# ��<add�ǻ��ꤷ���������> user *!*user@*.user.net�פΤ褦�ˤ��ƾ�����ɲá�
# ȯ���򤷤��ͤΥ����ꥢ����̤��Ͽ���ä����ϡ�user�Τ߼����դ��ƿ����ɲäȤ��롣
add: �����ꥢ���ɲ�

# ��<remove�ǻ��ꤷ���������> name �桼�����פΤ褦�ˤ��ƾ��������
# user�����ƺ�����줿�����ꥢ����¾�ξ���(name��)��ޤ�ƾ��Ǥ��롣
remove: �����ꥢ�����

# ��å��������ɲä��줿�Ȥ���ȿ������ꤷ�ޤ���
# ������ʥ�å�������ȯ������ݤΥե����ޥåȤ���ꤷ�ޤ���
# �����ꥢ���ִ���ͭ���Ǥ���#(nick.now)��#(channel)��
# ���줾������nick�������ͥ�̾���ִ�����ޤ���
# #(key)��#(value)�ϡ��ɲä��줿�������ͤ��ִ�����ޤ���
added-format: #(name|nick.now): �����ꥢ�� #(key) �� #(value) ���ɲä��ޤ�����

# ��å�������������줿�Ȥ���ȿ������ꤷ�ޤ���
# added-format�ǻ���Ǥ����Τ�Ʊ���Ǥ���
removed-format: #(name|nick.now): �����ꥢ�� #(key) ���� #(value) �������ޤ�����

# �����ꥢ�����ɲä�����������Ƥ���͡���ά���줿���ϡ�*!*@*�פȸ�������롣
modifier: *!*@*
=cut
