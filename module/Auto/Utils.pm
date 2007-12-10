# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Utils;
use strict;
use warnings;
use Module::Use qw(Auto::AliasDB);
use Auto::AliasDB;
use Multicast;
use RunLoop;
use base qw(Tiarra::IRC::NewMessageMixin);

# get_ch_name は get_raw_ch_name のエイリアス(過去互換のため)
*get_ch_name = \&get_raw_ch_name;
sub get_raw_ch_name {
    # ネットワーク名抜きの送信先(チャンネル/nick)名 or undef を得る
    my ($msg, $ch_place) = @_;

    if (defined($msg->param($ch_place)) && $msg->param($ch_place) ne '') {
	return(scalar(Multicast::detach($msg->param($ch_place))));
    } else {
	return undef;
    }
}

sub get_full_ch_name {
    # ネットワーク名付きの送信先(チャンネル/nick)名 or undef を得る
    my ($msg, $ch_place) = @_;

    if (defined($msg->param($ch_place)) && $msg->param($ch_place) ne '') {
	return($msg->param($ch_place));
    } else {
	return undef;
    }
}

sub sendto_channel_closure {
    # チャンネル等に PRIVMSG / NOTICE を送るクロージャを返します。

    # - 引数 -
    # $sendto	: チャンネル名 or ニック。ネットワーク名を付けて下さい。
    # $command	: 'PRIVMSG' or 'NOTICE'。その他のコマンドも制限はしませんが意味が無いでしょう。
    # $msg	: message_arrivedに渡ってきた$msg。エイリアス置換に使用されます。よって、
    #               後述する $use_alias が false なら指定する必要はありません。
    #               その場合は undef でも渡しておきましょう。
    # $sender	: message_arrivedに渡ってきた$sender。送信に使います。ない場合は
    #               $result とともに undef を指定してください。
    # $result	: message_arrivedの返り値にする配列の参照。詳細は例を見ましょう。
    # $use_alias	: エイリアス置き換えを行うかどうか。省略可で省略した場合は
    #                       行うが、 $msg, $sender のどちらかが undef ならエイリアス
    #                       置き換えを呼び出せないので行わない。
    # $extra_callbacks
    # 		: 追加のエイリアス置換コールバック。省略可。
    #
    # エイリアス置換・コールバックに関しては Auto::AliasDB を参照してください。
    #
    # - 返り値 -
    # 	$send_message
    # $send_message
    # 		: クロージャ。第一引数にメッセージ、第二引数以降に追加のエイリアス(省略可能)を指定して呼び出す。
    #               メッセージとしてundefが渡された場合は、何もせずに終了する。
    #
    # - 使用例 -
    #       sub message_arrived {
    #           my ($this,$msg,$sender) = @_;
    #           my @result = ($msg);
    #           my $send_message = 
    #               sendto_channel_closure('#test@ircnet', 'NOTICE', $msg, $sender, \@result);
    #           $send_message->('message', 'hoge' => 'moge');
    #           return @result;
    #       }
    #

    my ($sendto, $command, $msg, $sender, $result, $use_alias, $extra_callbacks) = @_;

    $use_alias = 1 if (!defined $use_alias && defined $msg && defined $sender);
    $extra_callbacks = [] unless defined $extra_callbacks;

    return sub {
	my ($line,%extra_replaces) = @_;
	return if !defined $line;
	foreach my $str ((ref($line) eq 'ARRAY') ? @$line : $line) {
	    my $msg_to_send = __PACKAGE__->construct_irc_message(
		Command => $command,
		Params => ['',	# 後で設定
			   ($use_alias ? Auto::AliasDB->shared->stdreplace_add(
			       $msg->prefix || $sender->fullname,
			       $str,
			       $extra_callbacks,
			       $msg,
			       $sender,
			       %extra_replaces)
				: $str)]);
	    my ($rawname, $network_name, $specified_network) =
		Multicast::detach($sendto);
	    my $get_network_name = sub {
		$specified_network ? $network_name :
		    Configuration->shared_conf->networks->default;
	    };
	    my $sendto_client = Multicast::attach_for_client($rawname, $network_name);
	    if (!defined $sender) {
		# 鯖にはチャンネル名にネットワーク名を付けない。
		my $for_server = $msg_to_send->clone;
		$sender = RunLoop->shared_loop->network($get_network_name->());
		if (defined $sender) {
		    $for_server->param(0, $rawname);
		    $sender->send_message($for_server);
		}

		# クライアントにはチャンネル名にネットワーク名を付ける。
	    # また、クライアントに送られる時にはPrefixがそのユーザーに設定されるよう註釈を付ける。
		my $for_client = $msg_to_send->clone;
		$for_client->param(0, $sendto_client);
		$for_client->remark('fill-prefix-when-sending-to-client',1);
		RunLoop->shared_loop->broadcast_to_clients($for_client);
	    } elsif ($sender->isa('IrcIO::Server')) {
		# 鯖にはチャンネル名にネットワーク名を付けない。
		my $for_server = $msg_to_send->clone;
		$for_server->param(0, $rawname);
		$sender->send_message($for_server);

		# クライアントにはチャンネル名にネットワーク名を付ける。
		# また、クライアントに送られる時にはPrefixがそのユーザーに設定されるよう註釈を付ける。
		my $for_client = $msg_to_send->clone;
		$for_client->param(0, $sendto_client);
		$for_client->remark('fill-prefix-when-sending-to-client',1);
		push @$result,$for_client;
	    } elsif ($sender->isa('IrcIO::Client')) {
		# チャンネル名にネットワーク名を付ける。
		my $for_server = $msg_to_send->clone;
		$for_server->param(0, $sendto);
		push @$result,$for_server;

		my $for_client = $msg_to_send->clone;
		$for_client->prefix($sender->fullname);
		$for_client->param(0, $sendto_client);
		$sender->send_message($for_client);
	    }
	}
    };
}

sub generate_reply_closures {
    # 送信者に NOTICE で返答するクロージャを返します。

    # - 引数 -
    # $msg	: message_arrivedに渡ってきた$msg。
    # $sender	: message_arrivedに渡ってきた$sender。
    # $result	: message_arrivedの返り値にする配列の参照。詳細は例を見ましょう。
    # $use_alias	: エイリアス置き換えを行うかどうか。省略可、省略した場合は行う。
    # $extra_callbacks
    #		: 追加のエイリアス置換コールバック。省略可。
    # $ch_place	: チャンネル名が存在する $msg->param 内部の位置を指定します。省略時は0(先頭)です。
    #
    # エイリアス置換・コールバックに関しては Auto::AliasDB を参照してください。
    #
    # - 返り値 -
    # 	($get_raw_ch_name, $reply, $reply_as_priv, $reply_anywhere, $get_full_ch_name)
    # $get_raw_ch_name	: クロージャ。ネットワーク名無しのチャンネル名 or undef を返します。
    # $reply		: クロージャ。チャンネルに返答します。
    # $reply_as_priv	: クロージャ。送信者に直接 priv で返答します。
    # $reply_anywhere	: クロージャ。チャンネルが有効であれば $reply が、そうでなければ $reply_as_priv です。
    # $get_full_ch_name	: クロージャ。ネットワーク名付きのチャンネル名 or undef を返します。
    #
    # $reply* は第一引数にメッセージ、第二引数以降に追加のエイリアス(省略可能)を指定して呼び出します。
    # 第一引数にundefが渡された場合は、何もせずに終了します。
    #
    # - 使用例 -
    #       sub message_arrived {
    #           my ($this,$msg,$sender) = @_;
    #           my @result = ($msg);
    #           my ($get_ch_name, $reply, $reply_as_priv, $reply_anywhere) = 
    #               generate_reply_closures($msg, $sender, \@result);
    #           $reply_anywhere->('message', 'hoge' => 'moge');
    #           return @result;
    #       }
    #
    # - 備考 -
    # $get_raw_ch_name がクロージャなのは過去との互換性のため、
    # $get_full_ch_name がクロージャーなのは共通性のためです。

    my ($msg, $sender, $result, $use_alias, $extra_callbacks, $ch_place) = @_;
    $use_alias = 1 unless defined $use_alias;
    $extra_callbacks = [] unless defined $extra_callbacks;
    $ch_place = 0 unless defined $ch_place;

    my $raw_ch_name = get_raw_ch_name($msg, $ch_place);
    my $get_raw_ch_name = sub () {
	$raw_ch_name;
    };
    my $full_ch_name = get_full_ch_name($msg, $ch_place);
    my $get_full_ch_name = sub () {
	$full_ch_name;
    };
    my $reply = sub {
	sendto_channel_closure($msg->param($ch_place), 'NOTICE', $msg, $sender, $result,
			       $use_alias, $extra_callbacks)->(@_, 'channel' => $raw_ch_name);
    };
    my $reply_as_priv = sub {
	my ($line,%extra_replaces) = @_;
	return if !defined $line;
	foreach my $str ((ref($line) eq 'ARRAY') ? @$line : $line) {
	    $sender->send_message(__PACKAGE__->construct_irc_message(
		Command => 'NOTICE',
		Params => [$msg->nick,
			   ($use_alias ? Auto::AliasDB->shared->stdreplace_add(
			       $msg->prefix,
			       $str,
			       $extra_callbacks,
			       $msg,
			       $sender,
			       %extra_replaces)
				: $str)]));
	}
    };
    my $reply_anywhere = sub {
	if (defined($raw_ch_name) && Multicast::nick_p($raw_ch_name)) {
	    return $reply_as_priv;
	} else {
	    return $reply;
	}
    };
    return ($get_raw_ch_name,$reply,$reply_as_priv,$reply_anywhere->(),$get_full_ch_name);
}

1;
