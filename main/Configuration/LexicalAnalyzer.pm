# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# confファイルの字句解析器。
# 文脈に応じてトークンを解析していく。
# -----------------------------------------------------------------------------
package Configuration::LexicalAnalyzer;
use strict;
use warnings;

sub new {
    # $body: 解析させる内容
    my ($class,$body) = @_;
    my $this = {
	body => $body, # トークンが解析される度に、解析されたトークンが消されていく。
	linecount => 0, # 現在どの行を解析しているか？この情報はエラー時にしか使われない。
	rollbackcount => 0, # 現在何行を読み過ぎているか？
    };
    bless $this;
}

sub linecount {
    shift->{linecount};
}

sub next {
    # 次のトークンを得る。もう残っていなければundefを返す。
    # $contenxt: 'outside' | 'block'
    #
    # outside: 今、ブロックの外側に居る事を示す。
    # block: 今、ブロック内に居る事を示す。
    #
    # 戻り値: (トークン,タイプ)
    # タイプとしては次のようなものがある。
    # 'label' => ブロックのラベル
    # 'blockstart' => ブロックの始まり
    # 'blockend' => ブロックの終わり
    # 'pair' => キーと値のペア
    my ($this,$context) = @_;

    my $method = "_context_$context";
    if ($this->can($method)) {
	my ($token,$type) = eval {
	    $this->$method;
	}; if ($@) {
	    die "Exception in analyzing token: line $this->{linecount}\n$@\n";
	}
	($token,$type);
    }
    else {
	die "Illegal context: $context\n";
    }
}

sub _context_outside {
    my $this = shift;

    my $labelchar = qr{[^\s{}]}; # ブロック名として許される文字
    my $label = qr{^(?:(?:\+|\-)\s+)?$labelchar+}; # ブロックのラベル

    my $blockstart = qr|^{|; # ブロックの開始

    my $line = $this->_nextline;
    if (defined $line) {
	my ($token,$type) = do {
	    if ($line =~ s/($label)//) {
		($1,'label');
	    }
	    elsif ($line =~ s/($blockstart)//) {
		($1,'blockstart');
	    }
	    else {
		# 不正なトークン。
		die "Syntax error: $line\n";
	    }
	};
	# 必要なら残りの部分をロールバック
	$this->rollback($line);
	($token,$type);
    }
    else {
	undef;
    }
}

sub _context_block {
    my $this = shift;

    my $keychar = qr{[^\s{}:]}; # キーとして許される文字
    my $pair = qr{^$keychar+\s*:.*$}; # キーと値のペア

    my $labelchar = qr{[^\s{}:]}; # ブロック内ブロックのラベルとして許される文字
    my $label = qr{^$labelchar+}; # ブロックのラベル

    my $blockstart = qr|^{|; # ブロックの開始
    my $blockend = qr|^}|; # ブロックの終了

    my $line = $this->_nextline;
    if (defined $line) {
	my ($token,$type) = do {
	    if ($line =~ s/($pair)//) {
		($1,'pair');
	    }
	    elsif ($line =~ s/($label)//) {
		($1,'label');
	    }
	    elsif ($line =~ s/($blockstart)//) {
		($1,'blockstart');
	    }
	    elsif ($line =~ s/($blockend)//) {
		($1,'blockend');
	    }
	    else {
		# 不正なトークン。
		die "Syntax error: $line\n";
	    }
	};
	# 必要なら残りの部分をロールバック
	$this->rollback($line);
	($token,$type);
    }
    else {
	undef;
    }
}

sub _nextline {
    my $this = shift;

    while (1) {
	if ($this->{body} eq '') {
	    # もう行が無い。
	    return undef;
	}

	# とりあえず先頭一行を取得。
	$this->{body} =~ s/^(.*?)(?:\n|$)//s;
	my $line = $1;

	if (defined $line) {
	    # まだ行が残ってる。
	    # 最初と最後の空白を除去。
	    if ($this->{rollbackcount} > 0) {
		# 読み過ぎているのでカウントしない。
		$this->{rollbackcount}--;
	    }
	    else {
		$this->{linecount}++;
	    }
	    $line =~ s/^\s*|\s*$//g;
	    
	    # 空の行やコメント行なら飛ばして次へ。
	    if ($line eq '' || $line =~ m/^#/) {
		next;
	    }
	    else {
		return $line;
	    }
	}
	else {
	    # もう行が無い。
	    return undef;
	}
    }
}

sub rollback {
    my ($this,$line) = @_;

    # 最初と最後の空白を除去。
    $line =~ s/^\s*|\s*$//g;

    # まだ中身が残っていればカウンタごと書き戻す。
    if ($line ne '') {
	$this->{body} = "$line\n$this->{body}";
	$this->{rollbackcount}++;
    }
}

1;
