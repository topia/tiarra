# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# confファイルの構文解析を行なうクラス。
# このクラスはConfiguration::LexicalAnalyzerを用いて字句解析を行ないます。
#
# このクラスは文字コードを全く変換せずに結果を返します。
# また、ブロック名については完全に無頓着です。
# -----------------------------------------------------------------------------
package Configuration::Parser;
use strict;
use warnings;
use Carp;
use Unicode::Japanese;
use Configuration::LexicalAnalyzer;
use Configuration::Block;

sub new {
    # $body: 解析する内容
    my ($class,$body) = @_;
    my $this = {
	lex => Configuration::LexicalAnalyzer->new($body),
	
	parsed => [], # Configuration::Block (現れた順番に並ぶ。)
    };
    bless $this,$class;

    eval {
	$this->_parse;
    }; if ($@) {
	die "(line ".$this->{lex}->linecount.") $@\n";
    }
    $this;
}

sub parsed {
    shift->{parsed};
}

sub _parse {
    my $this = shift;

    # block := LABEL BLOCKSTART blockcontent BLOCKEND
    # blockcontent := pair | block

    while (1) {
	my $block = $this->_parse_block('outside');
	if (defined $block) {
	    push @{$this->{parsed}},$block;
	}
	else {
	    last;
	}
    }

    $this;
}

sub _parse_block {
    my ($this,$context) = @_;
    
    my ($token,$type);
    # block := LABEL BLOCKSTART blockcontent BLOCKEND

    ($token,$type) = $this->{lex}->next($context);
    if (!defined $token) {
	return undef; # もうブロックが無い。
    }
    elsif ($type ne 'label') {
	die "Semantics error: label of block is needed here.\n$token\n";
    }
    my $block = Configuration::Block->new($token);

    ($token,$type) = $this->{lex}->next($context);
    if (!defined $token || $type ne 'blockstart') {
	$token = '' if !defined $token;
	die "Semantics error: '{' is needed here.\n$token\n";
    }

    $this->_parse_blockcontent($block);

    ($token,$type) = $this->{lex}->next('block');
    if (!defined $token || $type ne 'blockend') {
	$token = '' if !defined $token;
	die "Semantics error: '}' is needed here.\n$token\n";
    }

    $block;
}

sub _parse_blockcontent {
    my ($this,$block) = @_;

    my ($token,$type);
    # blockcontent := (pair | block)*

    while (1) {
	($token,$type) = $this->{lex}->next('block');
	if (!defined $token) {
	    die "Semantics error: pair, label or blockend is needed here.\n";
	}
	elsif ($type eq 'pair') {
	    $token =~ m/^(.+?)\s*:\s*(.+)$/;
	    $block->add($1,$2);
	}
	elsif ($type eq 'label') {
	    # 読み過ぎたので戻す。
	    $this->{lex}->rollback($token);

	    # ブロックをパース。
	    my $newblock = $this->_parse_block('block');
	    $block->set($newblock->block_name,$newblock);
	}
	elsif ($type eq 'blockend') {
	    # 読み過ぎたので戻す。
	    $this->{lex}->rollback($token);

	    # ここで終わり。
	    last;
	}
	else {
	    die "Semantics error: pair, label or blockend is needed here.\n$token\n";
	}
    }
}

1;
