# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# SendMessage - ��å��������������������뤿��Υ⥸�塼�롣
# -----------------------------------------------------------------------------
# Copyright (C) 2004 Yoichi Imai <yoichi@silver-forest.com>
package System::SendMessage;
use strict;
use warnings;
use base qw(Module);
use Mask;
use Multicast;
use ControlPort;
use Auto::Utils;
use Tiarra::Utils;

sub control_requested {
    my ($this,$request) = @_;
    # ��������ȥ���ץ���फ��Υ�å��������褿��
    # ����ͤ�ControlPort::Reply��
    #
    # $request:
    #    ���� : ControlPort::Request
    #          ����줿�ꥯ������

    # << NOTIFY System::SendMessage TIARRACONTROL/1.0
    # << Channel: !????channel@network
    # << Charset: UTF-8
    # << Text: message

    # >> TIARRACONTROL/1.0 200 OK

    my $mask = $request->table->{Channel};
    my $text = $request->table->{Text};
    my $command = utils->cond_yesno($request->table->{Notice}, 1) ?
	'NOTICE' : 'PRIVMSG';
    unless ($mask) {
	return new ControlPort::Reply(403, "Channel is not set");
    }
    unless ($text) {
	return new ControlPort::Reply(403, "Doesn't have remark");
    }

    my ($channel_mask, $network_name) = Multicast::detach($mask);

    my $server = $this->_runloop->network($network_name);
    unless (defined $server) {
	return new ControlPort::Reply(404, "Server Not Found");
    }

    my $matched = 0;

    foreach my $chinfo ($server->channels_list) {
	if (Mask::match_array([$channel_mask], $chinfo->name)) {
	    $matched = 1;
	    Auto::Utils::sendto_channel_closure(
		$chinfo->fullname, $command, undef, undef, undef, 0
	       )->($text);
	}
    }
    if ($matched) {
	return new ControlPort::Reply(200, "OK");
    } else {
	return new ControlPort::Reply(404, "Channel Not Found");
    }
}

1;
