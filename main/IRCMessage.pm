# -----------------------------------------------------------------------------
# $Id: IRCMessage.pm,v 1.18 2004/06/04 12:57:30 topia Exp $
# -----------------------------------------------------------------------------
# IRCMessageはIRCのメッセージを表わすクラスです。実際のメッセージはUTF-8で保持します。
# 生のメッセージのパース、シリアライズ、そしてメッセージの生成をサポートします。
# パースとシリアライズには文字コードを指定して下さい。コードを変換します。
# LineとEncoding以外の手段でインスタンスを生成する際は、
# パラメータとしてUTF-8の値を渡して下さい。
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
use strict;
use warnings;
use Carp;
use Unicode::Japanese;
use Data::Dumper;

# constants
use constant MAX_PARAMS => 14;

# variable indices
use constant PREFIX  => 0;
use constant COMMAND => 1;
use constant PARAMS  => 2;

use constant NICK    => 3;
use constant NAME    => 4;
use constant HOST    => 5;

use constant REMARKS => 6;

sub new {
    my ($class,%args) = @_;
    my $obj = bless [] => $class;
    $obj->[PREFIX] = undef;
    $obj->[COMMAND] = undef;
    $obj->[PARAMS] = undef;

    $obj->[NICK] = undef;
    $obj->[NAME] = undef;
    $obj->[HOST] = undef;

    $obj->[REMARKS] = undef;

    if (exists $args{'Line'}) {
	$args{'Line'} =~ s/\x0d\x0a$//s; # 行末のcrlfは消去。
	$obj->_parse($args{'Line'},$args{'Encoding'} || 'auto'); # Encodingが省略されたら自動判別
    }
    else {
	if (exists $args{'Prefix'}) {
	    $obj->[PREFIX] = $args{'Prefix'}; # prefixが指定された
	}
	elsif (exists $args{'Server'}) {
	    $obj->[PREFIX] = $args{'Server'}; # prefix決定
	}
	elsif (exists $args{'Nick'}) {
	    $obj->[PREFIX] = $args{'Nick'}; # まずはnickがあることが分かった
	    if (exists $args{'User'}) {
		$obj->[PREFIX] .= '!'.$args{'User'}; # userもあった。
	    }
	    if (exists $args{'Host'}) {
		$obj->[PREFIX] .= '@'.$args{'Host'}; # hostもあった。
	    }
	}

	# Commandは絶対に無ければならない。
	if (exists $args{'Command'}) {
	    ($obj->[COMMAND] = $args{'Command'}) =~ tr/a-z/A-Z/;
	}
	else {
	    die "You can't make IRCMessage without a COMMAND.\n";
	}

	if (exists $args{'Params'}) {
	    # Paramsがあった。型はスカラーもしくは配列リファ
	    my $params = $args{'Params'};
	    my $type = ref($params);
	    if ($type eq '') {
		$obj->[PARAMS] = [$params];
	    }
	    elsif ($type eq 'ARRAY') {
		my @copy_of_params = @{$params};
		$obj->[PARAMS] = \@copy_of_params; # コピーを格納
	    }
	}
	elsif (exists $args{'Param'}) {
	    # Paramがあった。型はスカラーのみ
	    $obj->[PARAMS] = [$args{'Param'}];
	}
    }
    if (exists $args{'Remarks'}) {
	my %copy_of_remarks = %{$args{'Remarks'}};
	$obj->[REMARKS] = \%copy_of_remarks;
    }
    $obj->_parse_prefix;
    $obj;
}

sub clone {
    my ($this, %args) = @_;
    if ($args{deep}) {
	eval
	    Data::Dumper->new([$this])->Terse(1)->Deepcopy(1)->Purity(1)->Dump;
    } else {
	my @new = @$this;
	bless \@new => ref($this);
    }
}

sub _parse {
    my ($this,$line,$encoding) = @_;
    delete $this->[PREFIX];
    delete $this->[COMMAND];
    delete $this->[PARAMS];

    my $pos = 0;
    # prefix
    if (substr($line,0,1) eq ':') {
	# :で始まっていたら
	my $pos_space = index($line,' ');
	$this->[PREFIX] = substr($line,1,$pos_space - 1);
	$pos = $pos_space + 1; # スペースの次から解釈再開
    }
    # command & params
    my @encodings = split(/\s*,\s*/, $encoding);
    my $unicode = new Unicode::Japanese;
    my $add_command_or_param = sub {
	my $value_raw = shift;
	my $use_encoding = $encodings[0];
	if (scalar(@encodings) != 1) {
	  my $auto_charset = $unicode->getcode($value_raw);
	  # getcodeで検出された文字コードでencodingsに指定されているものがあれば採用。
	  # 無ければencodingsの一番最初を採用する。 (UTF-8をSJISと認識したりするため。)
	  $use_encoding = ((map {$auto_charset eq $_ ? $_ : ()} @encodings), @encodings)[0];
	}
	my $value = do {
	    if (length ($value_raw) == 0) {
		'';
	    }
	    else {
		$unicode->set($value_raw,$use_encoding)->utf8;
	    }
	};

	if ($this->[COMMAND]) {
	    # commandはもう設定済み。次はパラメータだ。
	    $this->push($value);
	}
	else {
	    # まだコマンドが設定されていない。
	    ($this->[COMMAND] = $value) =~ tr/a-z/A-Z/;
	}
    };
    while (1) {
	my $param = '';

	my $pos_space = index($line,' ',$pos);
	if ($pos_space == -1) {
	    # 終了
	    $param = substr($line,$pos);
	}
	else {
	    $param = substr($line,$pos,$pos_space - $pos);
	}

	if ($param ne '') {
	    if (substr($param,0,1) eq ':') {
		# これ以降は全て一つの引数。
		$add_command_or_param->(substr($line,$pos+1)); # :は外す。
		last; # ここで終わり。
	    }
	    else {
		$add_command_or_param->($param);
	    }
	}

	if ($pos_space == -1) {
	    last;
	}
	else {
	    $pos = $pos_space + 1; # スペースの次から解釈再開
	}
    }

    # 解釈結果の正当性をチェック。
    # commandが無かったらdie。
    unless ($this->[COMMAND]) {
	die "IRCMessage parsed invalid one, which doesn't have command.\n  $line\n";
    }
}

sub _parse_prefix {
    my $this = shift;
    if (defined $this->[PREFIX]) {
	$this->[PREFIX] =~ m/^(.+?)!(.+?)@(.+)$/;
	if (!defined($1)) {
	    $this->[NICK] = $this->[PREFIX];
	}
	else {
	    $this->[NICK] = $1;
	    $this->[NAME] = $2;
	    $this->[HOST] = $3;
	}
    }
}

sub _update_prefix {
    my $this = shift;
    if (defined $this->[NICK]) {
	if (defined $this->[NAME]) {
	    $this->[PREFIX] =
		$this->[NICK].'!'.$this->[NAME].'@'.$this->[HOST];
	}
	else {
	    $this->[PREFIX] = $this->[NICK];
	}
    }
    else {
	delete $this->[NICK];
    }
}

sub serialize {
    # encodingを省略するとutf8になる。
    my ($this,$encoding) = @_;
    $encoding = 'utf8' unless defined $encoding;
    my $result = '';

    if ($this->[PREFIX]) {
	$result .= ':'.$this->[PREFIX].' ';
    }

    $result .= $this->[COMMAND].' ';

    if ($this->[PARAMS]) {
	my $unicode = new Unicode::Japanese;
	my $n_params = scalar @{$this->[PARAMS]||[]};
	for (my $i = 0;$i < $n_params;$i++) {
	    if ($i == $n_params - 1) {
		# 最後のパラメタなら頭にコロンを付けて後にはスペースを置かない。
		# 但し半角スペースが一つも無く、且つコロンで始まっていなければコロンを付けない。
		# パラメタが空文字列であった場合は例外としてコロンを付ける。
		my $arg = $unicode->set($this->[PARAMS]->[$i])->conv($encoding);
		if (length($arg) > 0 and
		      index($arg, ' ') == -1 and
			index($arg, ':') != 0) {
		    $result .= $arg;
		}
		else {
		    $result .= ":$arg";
		}
		# 本当はCTCPメッセージを外してエンコードすべきかも知れない。
	    }
	    else {
		# 最後のパラメタでなければ後にスペースを置く。
		$result .= $unicode->set($this->[PARAMS]->[$i])->conv($encoding).' ';
	    }
	}
    }

    return $result;
}

sub length {
    my ($this) = shift;
    length($this->serialize(@_));
}

sub prefix {
    my ($this,$new_val) = @_;
    $this->[PREFIX] = $new_val if defined($new_val);
    $this->[PREFIX];
}

sub nick {
    my ($this,$new_val) = @_;
    if (defined $new_val) {
	$this->[NICK] = $new_val;
	$this->_update_prefix;
    }
    $this->[NICK];
}

sub name {
    my ($this,$new_val) = @_;
    if (defined $new_val) {
	$this->[NAME] = $new_val;
	$this->_update_prefix;
    }
    $this->[NAME];
}

sub host {
    my ($this,$new_val) = @_;
    if (defined $new_val) {
	$this->[HOST] = $new_val;
	$this->_update_prefix;
    }
    $this->[HOST];
}

sub command {
    my ($this,$new_val) = @_;
    $this->[COMMAND] = $new_val if defined($new_val);
    $this->[COMMAND];
}

sub params {
    croak "Parameter specified to params(). You must mistaked with param().\n" if (@_ > 1);
    my $this = shift;
    $this->[PARAMS] = [] if !defined $this->[PARAMS];
    $this->[PARAMS];
}

sub n_params {
    scalar @{shift->params};
}

sub param {
    my ($this,$index,$new_value) = @_;
    croak "Parameter index wasn't specified to param(). You must be mistaken with params().\n" if (@_ <= 1);
    if (defined $new_value) {
	$this->[PARAMS]->[$index] = $new_value;
    }
    $this->[PARAMS]->[$index];
}

sub push {
    my $this = shift;
    CORE::push(@{$this->params}, @_);
}

sub pop {
    CORE::pop(@{shift->params});
}

sub remark {
    my ($this,$key,$value) = @_;
    # remark() -> HASH*
    # remark('key') -> SCALAR
    # remark('key','value') -> 'value'
    if (!defined($key)) {
	$this->[REMARKS] || {};
    }
    else {
	if (defined $value) {
	    if (defined $this->[REMARKS]) {
		$this->[REMARKS]->{$key} = $value;
	    }
	    else {
		$this->[REMARKS] = {$key => $value};
	    }
	}
	defined $this->[REMARKS] ?
	    $this->[REMARKS]->{$key} : undef;
    }
}

1;
