# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003-2004 Topia <topia@clovery.jp>. all rights reserved.
package Auto::Calc::Share;
use strict;
our $__export = [qw(pi pie e frac)];
sub export () { $__export }

sub pi () { 3.141592653589793238 }
sub pie () { pi }
sub e () { exp(1) }
sub frac ($) { $_[0] - int($_[0]) }

package Auto::Calc;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils Auto::Calc::Share);
use Auto::Utils;
use Mask;

use Symbol ();
use Safe;

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{safe} = Safe->new(__PACKAGE__.'::Root');
    $this->{safe}->erase;
    $this->{safe}->permit_only(qw(:base_core :base_math :base_orig),
			       qw(pack unpack),
			       qw(atan2 sin cos exp log sqrt),
			      );
    if (!$this->config->permit_sub) {
	$this->{safe}->deny(qw(leavesub));
    }
    my $pkg = __PACKAGE__.'::Share';
    $this->{safe}->share_from($pkg, $pkg->export);

    return $this;
}

sub destruct {
    my ($this) = shift;

    Symbol::delete_package(__PACKAGE__.'::Root')
}

sub message_arrived {
    my ($this,$msg,$sender) = @_;
    my @result = ($msg);

    my $return_value = sub {
	return @result;
    };

    my (undef,undef,undef,$reply_anywhere,$get_full_ch_name)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result);

    if ($msg->command eq 'PRIVMSG') {
	my $method = $msg->param(1);
	$method =~ s/^\s*(.*)\s*$/$1/;

	# init
	if (Mask::match_deep([$this->config->init('all')], $method)) {
	    if (Mask::match_deep_chan([$this->config->init_mask('all')],
				      $msg->prefix, $get_full_ch_name->())) {
		$this->{safe}->reinit;
		$reply_anywhere->([$this->config->init_format('all')]);
		return $return_value->();
	    }
	}

	my $keyword;
	($keyword, $method) = split(/\s+/, $method, 2);

	# request
	if (Mask::match_deep([$this->config->request('all')], $keyword)) {
	    if (Mask::match_deep_chan([$this->config->mask('all')],
				      $msg->prefix, $get_full_ch_name->())) {
		my ($ret, $err, $signal);
		do {
		    # disable warning
		    local $SIG{__WARN__} = sub { };
		    #
		    my $signal_handler = sub {
			$signal = shift;
			die "$signal called";
		    };
		    # floating point exceptions
		    local $SIG{FPE} = sub { $signal_handler->('SIGFPE'); }
			if exists $SIG{FPE};
		    # alarm
		    local $SIG{ALRM} = sub { $signal_handler->('ALARM'); }
			if exists $SIG{ALRM};
		    my $timeout = $this->config->timeout;
		    $timeout = 1 unless defined $timeout;
		    # die handler
		    local $SIG{__DIE__} = sub {
			$err = shift;
			die '';
		    };

		    alarm $timeout if ($timeout);
		    no strict;
		    $ret = $this->{safe}->reval($method);
		    alarm 0 if ($timeout);
		};

		my $reply = sub {
		    my $array = shift;

		    map {
			if (defined($$_)) {
			    # 汚染の除去
			    $$_ =~ tr/\t\x0a\x0d/ /;
			    $$_ =~ tr/\x00-\x19//d;
			    $$_ =~ s/^\s+//;
			    $$_ =~ s/\s+$//;
			    $$_ =~ s/\s{2,}/ /;
			} else {
			    $$_ = $this->config->undef || 'undef';
			}
		    } (\$ret, \$err);

		    if ($err) {
			$err =~ s/ +at \(eval \d+\) line \d+//;
			$err =~ s/, <DATA> line \d+//;
		    }

		    map {
			$reply_anywhere->(
			    $_,
			    method => $method,
			    result => $ret,
			    error => $err,
			    signal => $signal,
			   );
		    } @$array;
		};

		my @format_names;
		if ($signal) {
		    push(@format_names, 'signal-'.lc($signal).'-format');
		    push(@format_names, 'signal-format');
		}
		if ($err) {
		    my $format = undef;
		    # format の個別化
		    my $error_name = $err;
		    if ($this->config->error_name_formatter) {

		    }
		    $error_name =~ s/'.+' (trapped by operation mask)/$1/;
		    $error_name =~ s/(Undefined subroutine) \&.+ (called)/$1 $2/;
		    $error_name =~ tr/ _/-/;
		    $error_name =~ tr/'`//d;
		    $error_name =~ s/\.$//;
		    $error_name =~ s/-+$//;
		    $error_name = lc($error_name);
		    #::debug_printmsg("error_name: $error_name");

		    push(@format_names, 'error-format');
		} else {
		    push(@format_names, 'reply-format');
		}
		foreach my $format_name (@format_names) {
		    my @formats = $this->config->get($format_name, 'all');
		    next if $#formats != 0;
		    $reply->(\@formats);
		    last;
		}
	    }
	}
    }

    return $return_value->();
}

1;
=pod
info: Perlの式を計算させるモジュール。
default: off

# 反応する発言を指定します。
request: 計算

# 使用を許可する人&チャンネルのマスク。
# 例はTiarraモード時。 [default: なし]
mask: * +*!*@*
# [plum-mode] mask: +*!*@*

# 結果が未定義だったときに置き換えられる文字列。省略されると undef 。
-undef: (未定義)

# 正常に計算できたときのフォーマット
# method: 計算式, result: 結果, error: エラー, signal: シグナル
reply-format: #(method): #(result)

# エラーが起きたときのフォーマット
# method: 計算式, result: 結果, error: エラー, signal: シグナル
error-format: #(method): エラーです。(#(error))

# シグナルが発生したときのフォーマット
-signal-format: #(method): シグナルです。(#(signal))

# signal-$SIGNALNAME-format 形式。
# $SIGNALNAME には現状 alarm/sigfpe があります。
# 該当がなければ signal-format にフォールバックします。

# いくつかの例を挙げます。
-signal-alarm-format: #(method): 時間切れです。
-signal-sigfpe-format: #(method): 浮動小数点計算例外です。

# タイムアウトする秒数を指定します。 alarm に渡されます。
# 再帰を止めるのに使えますが、どうもメモリリークしていそうな雰囲気です。
timeout: 1

# サブルーチン定義を許可するかどうかを指定する。
# 再帰定義が可能なので、許可する場合はこのモジュール専用の
# Tiarra を動かすことをお勧めします。
permit-sub: 0

# 初期化する発言を指定します。
# このモジュールでは現状変数や関数定義などを行えます。
# このコマンドが発行されるとそれらをクリアします。
init: 計算初期化

# 初期化を許可する人&チャンネルのマスク。
# 例はTiarraモード時。 [default: なし]
init-mask: * +*!*@*
# [plum-mode] mask: +*!*@*

# 再初期化したときの発言を指定します。
init-format: 初期化しました。

=cut
