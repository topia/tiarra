# -----------------------------------------------------------------------------
# $Id: Preprocessor.pm,v 1.8 2004/07/08 15:13:13 topia Exp $
# -----------------------------------------------------------------------------
# tiarraのconfファイルのプリプロセッサです。
# このクラスは次のような機能を持ちます。
#
# ・"%PRE{"と"}ERP%"に挟まれた部分をperlの文として評価し、結果をその場所に挿入する。
#
# ・@include ファイル名
#   このような行を、そのファイルの中身と置き換える。
#
# ・@define 文字列A 文字列B 
#   このような行の後からは、ファイル中の文字列Aを全て文字列Bに置き換える。
#   置換される場所はどこであっても構わない。例えば次のような定義は有効である。
#   @define DEBUG 1
#   @if 'DEBUG' == '1'
#     debug: a
#   @endif
#   例外は@undef文。この文に対しては置換が行なわれない。
#
# ・@undef 文字列A
#   @defineで定義した置換を、次の行からキャンセルする。
#
# ・@if 式
# ・@elsif
#   式をperlの文として評価し、結果が真なら@elsif、@else、@endifまでを有効な行とみなす。
#   if-elsif-else-endif構文は幾らでも入れ子にする事が出来る。
#
# ・@else
# ・@endif
#   説明は不要であろう。
#
# ・@ifdef 文字列
# ・@ifndef 文字列
#   その文字列が@defineされていたら、若しくはされていなかったら。
#
# ・@message 文字列
#   標準出力にその文字列を出す。但し文字コードの変換は一切行われないので
#   ASCII文字以外を出すのはやめた方が良い。
#
# -----------------------------------------------------------------------------
# 先に%PRE{ }ERP%が評価され、次に@文が評価される。
# %PRE{ }ERP%は複数の行に渡っても良い。
# -----------------------------------------------------------------------------
package Configuration::Preprocessor;
use strict;
use warnings;
use Carp;
use IO::File;
use UNIVERSAL;
our %initial_definition;

sub preprocess {
    # IO::Handleまたはファイル名を一つ取り、プリプロセスの結果を返す。
    my $handle = shift;

    Configuration::Preprocessor
	->new
	->execute($handle);
}

sub new {
    my ($class,$filename) = @_;
    my $this = {
	included => {}, # ファイルパス => 1 (多重includeのチェックに使われる。)
	consts => {%initial_definition}, # @defineされたマクロ名 => 中身
    };
    bless $this,$class;
}

sub included_files {
    my ($this) = shift;
    return keys(%{$this->{included}});
}

sub initial_define {
    my ($key, $value) = @_;
    $initial_definition{$key} = $value;
}

sub defined_p {
    my ($this, $key) = @_;
    defined $this->{consts}{$key};
}

sub execute {
    my ($this,$filename) = @_;

    my $result = eval {
	$this->_execute($filename);
    };
    if ($@) {
	my $fname = do {
	    if (ref($filename) && UNIVERSAL::isa($filename,'IO::Handle')) {
		"HANDLE(".$filename->fileno.")";
	    }
	    else {
		$filename;
	    }
	};
	die "Exception in preprocessing $fname:\n$@\n";
    }

    $result;
}

sub _execute {
    my ($this,$filepath) = @_;

    my $handle = do {
	if (!defined $filepath) {
	    croak "Configuration::Preprocessor->_execute, Arg[1] was undef.\n";
	}
	elsif (ref($filepath) && UNIVERSAL::isa($filepath,'IO::Handle')) {
	    # IO::Handleだった。
	    # 重複チェックは不可能。
	    $filepath;
	}
	else {
	    if (exists $this->{included}->{$filepath}) {
		die "$filepath has already loaded or included before.\n";
	    }
	    else {
		$this->{included}->{$filepath} = 1;
	    }
	    
	    my $fh = IO::File->new($filepath,'r');
	    if (!defined $fh) {
		die "Couldn't open $filepath to read.\n";
	    }
	    $fh;
	}
    };

    # ファイルを先頭から最後まで読む。
    my $body = '';
    foreach (<$handle>) {
	tr/\r\n//d;
	$body .= "$_\n";
    }
    undef $handle;

    # %PRE{ }ERP% 置換
    $body = $this->_eval_pre($body);

    # 一行ずつ読んで@指令を処理。
    $body = $this->_eval_at($body);

    $body;
}

sub _eval_pre {
    my ($this,$body) = @_;

    my $evaluate = sub {
	my $script = shift;
	no strict; no warnings;
	my $result = eval "package Configuration::Implanted; $script";
	use warnings; use strict;
	if ($@) {
	    my $short = substr $script,0,50;
	    $short =~ tr/\n//d;
	    $short =~ s/^\s*|\s*$//g;
	    die "Exception in evaluating %PRE{ }ERP% block\nlike '$short'\n$@\n";
	}
	defined $result ? $result : '';
    };
    $body =~ s/\%PRE{(.+?)}ERP\%/$evaluate->($1)/seg;
    $body;
}

sub _eval_at {
    my ($this,$body) = @_;

    my @ifstack = (); # 次にif,elsif,else,endifが来るまでの動作(真なら残し、偽なら消す)

    my $result = '';
    foreach my $line (split /\n/,$body) {
	# この行が@undef,@ifdef,@ifndef文でないなら、@defineされた全ての置換を実行。
	if ($line !~ m/^\s*\@\s*(?:undef|ifdef|ifndef)\s+/) {
	    while (my ($key,$value) = each %{$this->{consts}}) {
		$line =~ s/\Q$key\E/$value/g;
	    }
	}

	if (@ifstack > 0) {
	    # if文のブロック内である。
	    my $action = $ifstack[@ifstack - 1];
	    
	    if ($line =~ m/^\s*\@\s*(?:if|elsif|ifdef|ifndef|else|endif)/) {
		# 状態が変わる可能性がある。
		# とりあえず何もしない。
	    }
	    else {
		# 状態は変わらない。
		# 捨てる必要があるなら捨てて次へ。
		if (!$action) {
		    next;
		}
	    }
	}
	
	if ($line =~ m/^\s*\@/) {
	    # @で始まっている。
	    # とりあえず先頭の@を取って最初と最後の\sがあれば消す。
	    $line =~ s/^\s*\@\s*|\s*$//g;

	    # ifdefとifndefはif文に書換える
	    if ($line =~ m/^ifdef\s+(.+)$/) {
		$line = q{if $this->defined_p(q@}.$1.q{@)};
	    }
	    elsif ($line =~ m/^ifndef\s+(.+)$/) {
		$line = q{if !$this->defined_p(q@}.$1.q{@)};
	    }

	    if ($line =~ m/^include\s+(.+)$/) {
		$result .= $this->execute($1);
	    }
	    elsif ($line =~ m/^define\s+(.+?)(?:\s+(.+))?$/) {
		my $key = $1;
		my $value = (defined $2 ? $2 : '');
		
		if (defined $this->{consts}->{$key}) {
		    die "$key has already been \@defined before.\n";
		}
		$this->{consts}->{$key} = $value;
	    }
	    elsif ($line =~ m/^undef\s+(.+)$/) {
		if (!defined $this->{consts}->{$1}) {
		    die "$1 has not been \@defined.\n";
		}
		delete $this->{consts}->{$1};
	    }
	    elsif ($line =~ m/^message\s+(.+)$/) {
		print "$1\n";
	    }
	    elsif ($line =~ m/^if\s+(.+)$/) {
		if (@ifstack > 0 && !$ifstack[@ifstack - 2]) {
		    # 下のフレームが存在し、一つ下のフレームのアクションが'消す'なら、無条件に消す。
		    push @ifstack,0;
		}
		else {
		    # 評価結果が真なら、次にif,elsif,else,endifが出てくるまで残す。偽ならそれらが出るまで消す。
		    my $cond_evaluated = eval(defined $1 ? $1 : '');
		    if ($@) {
			die "Exception in evaluating: \@$line\n$@\n";
		    }
		    push @ifstack,$cond_evaluated;
		}
	    }
	    elsif ($line =~ m/^elsif\s+(.+)$/) {
		# elsifは新たにifフレームを追加する事はせず、現在のフレームに上書きする。
		#
		# 現在のフレームのアクションが'残す'だった場合...
		#   if,elsif,else,endifが出てくるまで無条件に消す。
		#
		# '消す'だった場合...
		#   真ならif,elsif,else,endifが出てくるまで残す。偽ならそれらが出るまで消す。
		#
		# 但し、現在のフレームがトップレベルでなかった場合で、
		# その下のレベルのアクションが'消す'だった場合は、無条件に消す。
		if (@ifstack > 1 && !$ifstack[@ifstack - 2]) {
		    pop @ifstack;
		    push @ifstack,0;
		}
		else {
		    if (@ifstack > 0) {
			if ($ifstack[@ifstack - 1]) {
			    pop @ifstack;
			    push @ifstack,0;
			}
			else {
			    my $cond_evaluated = eval(defined $1 ? $1 : '');
			    if ($@) {
				die "Exception in evaluating: \@$line\n$@\n";
			    }
			    pop @ifstack;
			    push @ifstack,$cond_evaluated;
			}
		    }
		    else {
			die "\@elsif without \@if block.\n";
		    }
		}
	    }
	    elsif ($line =~ m/^else$/) {
		# elseは新たにifフレームを追加することはせず、現在のフレームに上書きする。
		#
		# 現在のフレームのアクションが'残す'だった場合...
		#   if,elsif,else,endifが出てくるまで無条件に消す。
		#
		# '消す'だった場合...
		#   if,elsif,else,endifが出てくるまで無条件に残す。
		#
		# 但し、現在のフレームがトップレベルでなかった場合で、
		# その下のレベルのアクションが'消す'だった場合は、無条件に消す。
		if (@ifstack > 1 && !$ifstack[@ifstack - 2]) {
		    pop @ifstack;
		    push @ifstack,0;
		}
		else {
		    if (@ifstack > 0) {
			if ($ifstack[@ifstack - 1]) {
			    pop @ifstack;
			    push @ifstack,0;
			}
			else {
			    pop @ifstack;
			    push @ifstack,1;
			}
		    }
		    else {
			die "\@else without \@if block.\n";
		    }
		}
	    }
	    elsif ($line =~ m/^endif$/) {
		if (@ifstack > 0) {
		    # このifブロックを終了する。
		    pop @ifstack;
		}
		else {
		    die "\@endif without \@if block.\n";
		}
	    }
	    else {
		die "Invalid @ command: \@$line\n";
	    }
	}
	else {
	    $result .= "$line\n";
	}
    }

    # 最終的に@ifstackが空になっていないという事は、@ifブロックが終わっていないという事。
    if (@ifstack > 0) {
	die "There's \@if block which is not terminated.\n"
    }

    $result;
}

1;
