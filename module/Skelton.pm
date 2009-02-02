# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# モジュールのスケルトン。
# -----------------------------------------------------------------------------
package Skelton;
use strict;
use warnings;
use base qw(Module);

sub new {
    my $class = shift;
    # モジュールが必要になった時に呼ばれる。
    # これはモジュールのコンストラクタである。
    # 引数は無し。
    my $this = $class->SUPER::new(@_);

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

sub config_reload {
    my ($this, $old_config) = @_;
    # モジュールの設定が変更された時に呼ばれる。
    # 新しい config は $this->config で取得できます。

    # 定義されていない場合は destruct と new をそれぞれ呼ぶ。
    eval {
	$this->destruct;
    }; if ($@) {
	$this->_runloop->notify_error(
	    "Couldn't destruct module on reload config of " . ref($this)
		. ".\n$@");
    }
    return ref($this)->new($this->_runloop);
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    # サーバーまたはクライアントからメッセージが来た時に呼ばれる。
    # 戻り値はTiarra::IRC::Messageまたはその配列またはundef。
    #
    # $msg :
    #    内容: Tiarra::IRC::Messageオブジェクト
    #    サーバーから、またはクライアントから送られてきたメッセージ。
    #    モジュールはこのオブジェクトをそのまま返しても良いし、
    #    改変して返しても良いし何も返さなくても良いし二つ以上返しても良い。
    # $sender :
    #    内容: IrcIOオブジェクト
    #    このメッセージを発したIrcIO。サーバーまたはクライアントである。
    #    メッセージがサーバーから来たのかクライアントから来たのかは
    #    $sender->isa('IrcIO::Server')などとすれば判定出来る。
    #
    # サーバー→クライアントの流れでも、Prefixを持たないメッセージを
    # 流しても構わない。逆に言えば、そのようなメッセージが来ても
    # 問題が起こらないようにモジュールを設計しなければならない。
    return $msg;
}
## Auto::Utils::generate_reply_closures を使う場合。
# sub message_arrived {
#     my ($this,$msg,$sender) = @_;
#     my @result = ($msg);
# 
#     if ($msg->command eq 'PRIVMSG') {
# 	my ($get_raw_ch_name, $reply, $reply_as_priv, $reply_anywhere, $get_full_ch_name)
# 	    = Auto::Utils::generate_reply_closures($msg,$sender,\@result);
# 
# 	$reply_anywhere->('Hello, #(name|default_name)',
# 			'default_name' => '(your name)');
# 	if ($get_raw_ch_name->() eq '#Tiarra_testing') {
# 	    # なんらかの処理
# 	}
# 	if ($get_full_ch_name->() eq '#Tiarra_testing@LocalServer') {
# 	    # なんらかの処理
# 	}
#     }
#     return @result;
# }
# 

sub client_attached {
    my ($this,$client) = @_;
    # クライアントが新規に接続した時に呼ばれる。
    # 戻り値は無し。
    #
    # $client :
    #    内容: IrcIO::Clientオブジェクト
    #    接続されたクライアント。
}

sub client_detached {
    my ($this,$client) = @_;
    # クライアントが切断した時に呼ばれる。
    # 戻り値は無し。
    #
    # $client :
    #    内容: IrcIO::Clientオブジェクト
    #    切断したクライアント。
}

sub connected_to_server {
    my ($this,$server,$new_connection) = @_;
    # サーバーに接続した時に呼ばれる。
    # 戻り値は無し。
    #
    # $server :
    #    内容: IrcIO::Serverオブジェクト
    #         接続したサーバー。
    # $new_connection :
    #    内容: 真偽値
    #         新規の接続なら1。切断後の自動接続ではundef。
}

sub disconnected_from_server {
    my ($this,$server) = @_;
    # サーバーから切断した(或いはされた)時に呼ばれる。
    # 戻り値は無し。
    #
    # $server :
    #    内容: IrcIO::Serverオブジェクト
    #         切断したサーバー。
}

sub message_io_hook {
    my ($this,$message,$io,$type) = @_;
    # サーバーから受け取ったメッセージ、サーバーに送るメッセージ、
    # クライアントから受け取ったメッセージ、クライアントに送るメッセージは
    # このメソッドで各モジュールに通知される。メッセージの変更も可能で、
    # 戻り値のルールはmessage_arrivedと同じ。
    #
    # 通常のモジュールはこのメソッドを実装する必要は無い。
    #
    # $message :
    #    内容: Tiarra::IRC::Messageオブジェクト
    #         送受信しているメッセージ
    # $io :
    #    内容: IrcIO::Server又はIrcIO::Clientオブジェクト
    #         送受信を行っているIrcIO
    # $type :
    #    内容: 文字列
    #         'in'なら受信、'out'なら送信
    return $message;
}

sub control_requested {
    my ($this,$request) = @_;
    # 外部コントロールプログラムからのメッセージが来た。
    # 戻り値はControlPort::Reply。
    #
    # $request:
    #    内容 : ControlPort::Request
    #          送られたリクエスト
    die "This module doesn't support controlling.\n";
}

1;

=begin tiarra-doc

info:    Skeleton for tiarra-module.
default: off
#section: important

# モジュールの説明をこのあたりに書く.
# 詳細はこのソースみれば分かると思われ.
# 書式は tiarra.conf にそのままコピーできる形式.

# もにゅもにゅ
mask: *!*@*
mask: ...

=end tiarra-doc

=cut
