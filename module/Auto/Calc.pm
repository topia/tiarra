# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id: Calc.pm,v 1.2 2003/08/24 18:21:13 topia Exp $
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/Auto/Calc.pm,v 1.2 2003/08/24 18:21:13 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Auto::Calc::Share;
use strict;
use warnings;

sub pi () { 3.141592653589793238; }
sub pie () { pi(); }
sub e () { exp(1); }

package Auto::Calc;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::Utils);
use Auto::Utils;
use Mask;

use Safe;

sub new {
    my ($class) = @_;
    my $this = $class->SUPER::new;
    $this->{safe} = Safe->new();
    $this->{safe}->permit_only(qw(:base_core :base_math :base_orig),
			       qw(pack unpack),
			       qw(atan2 sin cos exp log sqrt));
    $this->{safe}->share_from(__PACKAGE__.'::Share', [qw(pi pie e)]);

    return $this;
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
	my $keyword;
	($keyword, $method) = split(/\s+/, $method, 2);

	# request
	if (Mask::match_deep([$this->config->request('all')], $keyword)) {
	    if (Mask::match_deep_chan([$this->config->mask('all')],
				      $msg->prefix, $get_full_ch_name->())) {
		my ($ret, $err);
		do {
		    # disable warning
		    local $SIG{__WARN__} = sub { };
		    # die handler
		    local $SIG{__DIE__} = sub { $err = $_[0]; };
		    # floating point exceptions
		    local $SIG{FPE} = sub { die 'SIGFPE called'; } if exists $SIG{FPE};
		    no strict;
		    $ret = $this->{safe}->reval($method);
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

		    map {
			$reply_anywhere->(
			    $_,
			    method => $method,
			    result => $ret,
			    error => $err,
			   );
		    } @$array;
		};

		if ($err) {
		    $err =~ s/ +at \(eval \d+\) line \d+//;
		    $err =~ s/, <DATA> line \d+//;
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
		    $error_name =~ tr/[A-Z]/[a-z]/;
		    ::debug_printmsg("error_name: $error_name");

		    $format = [$this->config->error_format('all')]
			unless defined $format;
		    $reply->($format);
		} else {
		    $reply->([$this->config->reply_format('all')]);
		}
	    }
	    return $return_value->();
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
reply-format: test

# エラーが起きたときのフォーマット
error-format: test

=cut
