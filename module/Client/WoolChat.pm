# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Client::WoolChat;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;

sub message_io_hook {
    my ($this,$msg,$io,$type) = @_;

    if ($io->isa('IrcIO::Client') &&
	    $this->is_target($io)) {
	if ($type eq 'out' &&
		$msg->command eq 'NICK') {
	    $msg->remark('always-use-colon-on-last-param', 1);
	}
    }
    return $msg;
}

sub is_target {
    my ($this, $client) = @_;

    return 1 if defined $client->remark('client-version') &&
	$client->remark('client-version') =~ /^WoolChat/;
    return 1 if defined $client->option('client-type') &&
	$client->option('client-type') =~ /woolchat/;
    return 0;
}

1;
=pod
info: WoolChat �Τ�������ư��Τ����Ĥ�����������
default: off

# �������饤����ȤΥ��ץ���� client-type �� woolchat �Ȼ��ꤷ�Ƥ���������
# ��̾��� $client-type=woolchat$ �Ƚ񤱤� OK �Ǥ���

=cut
