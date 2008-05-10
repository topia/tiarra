# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Auto::Oper;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;
use Multicast;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this;
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my ($get_raw_ch_name,$reply,$reply_as_priv,$reply_anywhere,$get_full_ch_name)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

    my $op = sub {
	$sender->send_message($this->construct_irc_message(
				  Command => 'MODE',
				  Params => [$get_raw_ch_name->(),'+o',$msg->nick]));
    };

    # 鯖からクライアントへのPRIVMSGで、かつrequestにマッチしているか？
    if ($sender->isa('IrcIO::Server') &&
	$msg->command eq 'PRIVMSG' &&
	Mask::match_array([$this->config->request('all')],$msg->param(1), 1)) {
	# 指定されたチャンネルは既知か？言い換えれば、privではないか？
	my $ch_name = $msg->param(0);
	my ($ch_name_plain) = Multicast::detatch($ch_name);
	my $ch = $sender->channel($ch_name_plain);
	if (defined $ch) {
	    # 指定されたチャンネルに、要求者は入っているか？
	    if (defined $ch->names($msg->nick)) {
		# なるとを渡しても良いのなら渡す。
		if (Mask::match_deep_chan([$this->config->mask('all')],$msg->prefix,$get_full_ch_name->())) {
		    # 自分はなるとを持ってるか？
		    my $myself = $ch->names($sender->current_nick);
		    if ($myself->has_o) {
			# 相手はなるとを持っているか？
			my $target = $ch->names($msg->nick);
			if ($target->has_o) {
			    $reply->($this->config->oper('random'));
			} else {
			    $reply->($this->config->message('random'));
			    $op->();
			}
		    } else {
			$reply->($this->config->not_oper('random'));
		    }
		} else {
		    $reply->($this->config->deny('random'));
		}
	    } else {
		$reply_as_priv->($this->config->out('random'));
	    }
	} else {
	    $reply_as_priv->($this->config->private('random'));
	}
    }
    return @result;
}

1;

=pod
info: 特定の文字列を発言した人を+oする。
default: off
section: important

# Auto::Aliasを有効にしていれば、エイリアス置換を行ないます。

# +oを要求する文字列(マスク)を指定します。
request: なると寄越せ

# チャンネルオペレータ権限を要求した人と要求されたチャンネルが
# ここで指定したマスクに一致しなかった場合は
# denyで指定した文字列を発言し、+oをやめます。
# 省略された場合は誰にも+oしません。
# 書式は「チャンネル 発言者」です。
# マッチングのアルゴリズムは次の通りです。
# 1. チャンネル名にマッチするmask定義を全て集める
# 2. 集まった定義の発言者マスクを、定義された順にカンマで結合する
# 3. そのようにして生成されたマスクで発言者のマッチングを行ない、結果を+o可能性とする。
# 例1:
# mask: *@2ch* *!*@*
# mask: #*@ircnet* *!*@*.hoge.jp
# この例ではネットワーク 2ch の全てのチャンネルで誰にでも +o し、
# ネットワーク ircnet の # で始まる全てのチャンネルでホスト名 *.hoge.jp の人に+oします。
# #*@ircnetだと「#hoge@ircnet:*.jp」などにマッチしなくなります。
# 例2:
# mask: #hoge@ircnet -*!*@*,+*!*@*.hoge.jp
# mask: *            +*!*@*
# 基本的に全てのチャンネルで誰にでも +o するが、例外的に#hoge@ircnetでは
# ホスト名 *.hoge.jp の人にしか +o しない。
# この順序を上下逆にすると、全てのチャンネルで全ての人を +o する事になります。
# 何故なら最初の* +*!*@*が全ての人にマッチするからです。
mask: * *!*@*

# +oを要求した人を実際に+oする時、ここで指定した発言をしてから+oします。
# #(name|nick)のようなエイリアス置換を行います。
# エイリアス以外でも、#(nick.now)を相手のnickに、#(channel)を
# そのチャンネル名にそれぞれ置換します。
message: 了解

# +oを要求されたが+oすべき相手ではなかった場合の発言。
# 省略されたら何も喋りません。
deny: 断わる

# +oを要求されたが相手は既にチャンネルオペレータ権限を持っていた場合の発言。
# 省略されたらdenyに設定されたものを使います。
oper: 既に@を持っている

# +oを要求されたが自分はチャンネルオペレータ権限を持っていなかった場合の発言。
# 省略されたらdenyに設定されたものを使います。
not-oper: @が無い

# チャンネルに対してでなく自分に対して+oの要求を行なった場合の発言。
# 省略されたらdenyに設定されたものを使います。
private: チャンネルで要求せよ

# チャンネルの外から+oを要求された場合の発言。+nチャンネルでは起こりません。
# 省略されたらdenyに設定されたものを使います。
out: チャンネルに入っていない
=cut
