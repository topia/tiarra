# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# IRCMessageはIRCのメッセージを表わすクラスです。実際のメッセージはUTF-8で保持します。
# 生のメッセージのパース、シリアライズ、そしてメッセージの生成をサポートします。
# パースとシリアライズには文字コードを指定して下さい。コードを変換します。
# LineとEncoding以外の手段でインスタンスを生成する際は、
# パラメータとしてUTF-8の値を渡して下さい。
# インターフェースは同一です。
# -----------------------------------------------------------------------------
# 生成方法一覧
#
# $msg = new IRCMessage(Line => ':foo!~foo@hogehoge.net PRIVMSG #hoge :hoge',
#                       Encoding => 'jis');
# print $msg->command; # 'PRIVMSG'を表示
#
# $msg = new IRCMessage(Server => 'irc.hogehoge.net', # ServerはPrefixでも良い。
#                       Command => '366',
#                       Params => ['hoge','#hoge','End of /NAMES list.']);
# print $msg->serialize('jis'); # ":irc.hogehoge.net 366 hoge #hoge :End of /NAMES list."を表示
#
# $msg = new IRCMessage(Nick => 'foo',
#                       User => '~bar',
#                       Host => 'hogehoge.net', # 以上３つのパラメータの代わりにPrefix => 'foo!~bar@hogehoge.net'でも良い。
#                       Command => 'NICK',
#                       Params => 'huga', # Paramsは要素が一つだけならスカラー値でも良い。(この時、ParamsでなくParamでも良い。)
#                       Remarks => {'saitama' => 'SAITAMA'}, # 備考欄。シリアライズには影響しない。
# print $msg->serialize('jis'); # ":foo!~bar@hogehoge.net NICK :huga"を表示
#
# $msg = new IRCMessage(Command => 'NOTICE',
#                       Params => ['foo','hugahuga']);
# print $msg->serialize('jis'); # "NOTICE foo :hugahuga"を表示
#
package IRCMessage;
use base qw(Tiarra::IRC::Message);

1;
