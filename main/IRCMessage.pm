# -----------------------------------------------------------------------------
# $Id$
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
use Tiarra::OptionalModules;
use Tiarra::Utils;
use Tiarra::DefineEnumMixin (qw(PREFIX COMMAND PARAMS),
			     qw(NICK NAME HOST),
			     qw(REMARKS TIME RAW_PARAMS));


# constants
use constant MAX_MIDDLES => 14;
use constant MAX_PARAMS => MAX_MIDDLES + 1;
# max params = (middles[14] + trailing[1]) = 15

utils->define_array_attr_accessor(0, qw(time));
utils->define_array_attr_translate_accessor(
    0, sub {
	my ($from, $to) = @_;
	"($to = $from) =~ tr/a-z/A-Z/";
    }, qw(command));
utils->define_array_attr_notify_accessor(
    0, '$this->_update_prefix', qw(nick name host));
utils->define_array_attr_notify_accessor(
    0, '$this->_parse_prefix', qw(prefix));

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

    $obj->[TIME] = Tiarra::OptionalModules->time_hires ?
	Time::HiRes::time() : CORE::time();

    $obj->[RAW_PARAMS] = undef;

    if (exists $args{'Line'}) {
	$args{'Line'} =~ s/\x0d\x0a$//s; # 行末のcrlfは消去。
	$obj->_parse($args{'Line'},$args{'Encoding'} || 'auto'); # Encodingが省略されたら自動判別
    }
    else {
	if (exists $args{'Prefix'}) {
	    $obj->prefix($args{'Prefix'}); # prefixが指定された
	}
	elsif (exists $args{'Server'}) {
	    $obj->prefix($args{'Server'}); # prefix決定
	}
	else {
	    foreach (qw(Nick User Host)) {
		if (exists $args{$_}) {
		    my $method = lc($_);
		    $obj->$method($args{$_});
		}
	    }
	}

	# Commandは絶対に無ければならない。
	if (exists $args{'Command'}) {
	    $obj->command($args{'Command'});
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
		$obj->[PARAMS] = [@$params]; # コピーを格納
	    }
	}
	elsif (exists $args{'Param'}) {
	    # Paramがあった。型はスカラーのみ
	    $obj->[PARAMS] = [$args{'Param'}];
	}
    }
    if (exists $args{'Remarks'}) {
	$obj->[REMARKS] = {%{$args{'Remarks'}}};
    }
    $obj;
}

sub clone {
    my ($this, %args) = @_;
    if ($args{deep}) {
	eval
	    Data::Dumper->new([$this])->Terse(1)->Deepcopy(1)->Purity(1)->Dump;
    } else {
	my @new = @$this;
	$new[PARAMS] = [@{$this->[PARAMS]}] if defined $this->[PARAMS];
	$new[REMARKS] = {%{$this->[REMARKS]}} if defined $this->[REMARKS];
	bless \@new => ref($this);
    }
}

sub _parse {
    my ($this,$line,$encoding) = @_;
    delete $this->[PREFIX];
    delete $this->[COMMAND];
    delete $this->[PARAMS];
    delete $this->[RAW_PARAMS];
    my $param_count_warned = 0;

    my $pos = 0;
    # prefix
    if (substr($line,0,1) eq ':') {
	# :で始まっていたら
	my $pos_space = index($line,' ');
	$this->prefix(substr($line,1,$pos_space - 1));
	$pos = $pos_space + 1; # スペースの次から解釈再開
    }
    # command & params
    my $add_command_or_param = sub {
	my $value_raw = shift;
	if ($this->command) {
	    # commandはもう設定済み。次はパラメータだ。
	    $this->_raw_push($value_raw);
	}
	else {
	    # まだコマンドが設定されていない。
	    $this->command($value_raw);
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
	    if ($this->n_params > MAX_PARAMS && !$param_count_warned) {
		$param_count_warned = 1;
		carp 'max param exceeded; please fix upstream server!';
	    }
	    if (substr($param,0,1) eq ':') {
		$param = substr($line, $pos); # これ以降は全て一つの引数。
		$param =~ s/^://; # :があった場合は外す。
		$add_command_or_param->($param);
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

    $this->encoding_params($encoding);

    # 解釈結果の正当性をチェック。
    # commandが無かったらdie。
    unless ($this->COMMAND) {
	croak "IRCMessage parsed invalid one, which doesn't have command.\n  $line\n";
    }
}

sub _parse_prefix {
    my $this = shift;
    delete $this->[NICK];
    delete $this->[NAME];
    delete $this->[HOST];
    if (defined $this->[PREFIX]) {
	if ($this->[PREFIX] !~ /@/) {
	    $this->[NICK] = $this->[PREFIX];
	} elsif ($this->[PREFIX] =~ m/^(.+?)!(.+?)@(.+)$/) {
	    $this->[NICK] = $1;
	    $this->[NAME] = $2;
	    $this->[HOST] = $3;
	} elsif ($this->[PREFIX] =~ m/^(.+?)@(.+)$/) {
	    $this->[NICK] = $1;
	    $this->[HOST] = $2;
	}
    } else {
	delete $this->[PREFIX];
    }
}

sub _update_prefix {
    my $this = shift;
    if (defined $this->[NICK]) {
	$this->[PREFIX] = $this->[NICK];
	if (defined $this->[HOST]) {
	    if (defined $this->[NAME]) {
		$this->[PREFIX] .= '!'.$this->[NAME];
		$this->[PREFIX] .= '@'.$this->[HOST];
	    } else {
		$this->[PREFIX] .= '@'.$this->[HOST];
		delete $this->[NAME];
	    }
	} else {
	    delete $this->[NAME];
	    delete $this->[HOST];
	}
    } else {
	delete $this->[NICK];
	delete $this->[NAME];
	delete $this->[HOST];
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

    $result .= $this->command.' ';

    if ($this->[PARAMS]) {
	my $unicode = new Unicode::Japanese;
	my $n_params = $this->n_params;
	if ($n_params > MAX_PARAMS) {
	    # 表現不能なので croak (危険なので carp で……)
	    carp 'this message exceeded maximum param numbers!';
	}
	for (my $i = 0;$i < $n_params;$i++) {
	    if ($i == $n_params - 1) {
		# 最後のパラメタなら頭にコロンを付けて後にはスペースを置かない。
		# 但し半角スペースが一つも無く、且つコロンで始まっていなければコロンを付けない。
		# パラメタが空文字列であった場合は例外としてコロンを付ける。
		# また、 remark/always-use-colon-on-last-param が付いていた場合も
		# コロンを付ける。
		my $arg = $unicode->set($this->[PARAMS]->[$i])->conv($encoding);
		if (length($arg) > 0 and
		      index($arg, ' ') == -1 and
			index($arg, ':') != 0 and
			    !$this->remark('always-use-colon-on-last-param')) {
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
    CORE::length($this->serialize(@_));
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

sub _raw_params {
    my $this = shift;
    $this->[RAW_PARAMS] = [] if !defined $this->[RAW_PARAMS];
    $this->[RAW_PARAMS];
}

sub _raw_push {
    my $this = shift;
    CORE::push(@{$this->_raw_params}, @_);
}

sub _raw_pop {
    CORE::pop(@{shift->_raw_params});
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

sub purge_raw_params {
    my $this = shift;
    $this->_raw_params(undef);
}

sub encoding_params {
    my ($this, $encoding) = @_;

    croak "raw_params already purged; can't re encoding"
	unless defined $this->_raw_params;

    my @encodings = split(/\s*,\s*/, $encoding);
    my $unicode = Unicode::Japanese->new;

    # clear
    @{$this->params} = ();

    foreach my $value_raw (@{$this->_raw_params}) {
	my $use_encoding = $encodings[0];
	if (scalar(@encodings) != 1) {
	  my $auto_charset = $unicode->getcode($value_raw);
	  # getcodeで検出された文字コードでencodingsに指定されているものがあれば採用。
	  # 無ければencodingsの一番最初を採用する。 (UTF-8をSJISと認識したりするため。)
	  $use_encoding = ((grep {$auto_charset eq $_} @encodings), @encodings)[0];
	}
	my $value = do {
	    if (CORE::length ($value_raw) == 0) {
		'';
	    }
	    else {
		$unicode->set($value_raw,$use_encoding)->utf8;
	    }
	};
	$this->push($value);
    }
}

1;
