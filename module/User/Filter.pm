# -----------------------------------------------------------------------------
# $Id: Filter.pm,v 1.1 2003/03/23 07:44:50 admin Exp $
# -----------------------------------------------------------------------------
package User::Filter;
use strict;
use warnings;
use base qw(Module);
use Mask;

sub message_arrived {
    my ($this,$msg,$sender) = @_;

    if ($sender->isa('IrcIO::Server') &&
	($msg->command eq 'PRIVMSG' || $msg->command eq 'NOTICE')) {
	# �ޥå�����ѥ������õ��
	foreach ($this->config->pattern('all')) {
	    my ($user,$replace) = m/^(.+?)\s+(.+)$/;
	    if (Mask::match($user,$msg->prefix)) {
		# ���פ�����
		$replace =~ s/#\(message\)/$msg->param(1)/eg;
		$msg->param(1,$replace);
		last;
	    }
	}
    }

    $msg;
}

1;

=pod
info: ���ꤵ�줿��ʪ�����PRIVMSG��NOTICE��񤭴����롣
default: off

# ��ʪ�Υޥ����ȡ��ִ��ѥ�����������
# �ִ��ѥ��������#(message)�ϡ�ȯ�����Ƥ��ִ�����ޤ���
# ��ʪ��ʣ���Υޥ����˰��פ�����ϡ��ǽ�˰��פ�����Τ��Ȥ��ޤ���
pattern: *!*@* #(message)
=cut
