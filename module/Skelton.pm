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

sub message_arrived {
    my ($this,$message,$sender) = @_;
    # サーバーまたはクライアントからメッセージが来た時に呼ばれる。
    # 戻り値はIRCMessageまたはその配列またはundef。
    #
    # $message :
    #    内容: IRCMessageオブジェクト
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
    return $message;
}
## Auto::Utils::generate_reply_closures を使う場合。
# sub message_arrived {
#     my ($this,$message,$sender) = @_;
#     my @result = ($msg);
# 
#     if ($msg->command eq 'PRIVMSG') {
# 	my ($reply,$reply_as_priv,$get_raw_ch_name,$reply_anywhere,$get_full_ch_name)
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
    # サーバーから受け取ったメッセージ、サーバーに送ったメッセージ、
    # クライアントから受け取ったメッセージ、クライアントに送ったメッセージは
    # このメソッドで各モジュールに通知される。メッセージの変更も可能で、
    # 戻り値のルールはmessage_arrivedと同じ。
    #
    # 通常のモジュールはこのメソッドを実装する必要は無い。
    #
    # $message :
    #    内容: IRCMessageオブジェクト
    #         送受信されたメッセージ
    # $io :
    #    内容: IrcIO::Server又はIrcIO::Clientオブジェクト
    #         送受信が行なわれたIrcIO
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
