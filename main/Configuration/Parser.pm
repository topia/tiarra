# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# conf�ե�����ι�ʸ���Ϥ�Ԥʤ����饹��
# ���Υ��饹��Configuration::LexicalAnalyzer���Ѥ��ƻ�����Ϥ�Ԥʤ��ޤ���
#
# ���Υ��饹��ʸ�������ɤ������Ѵ������˷�̤��֤��ޤ���
# �ޤ����֥�å�̾�ˤĤ��Ƥϴ�����̵����Ǥ���
# -----------------------------------------------------------------------------
package Configuration::Parser;
use strict;
use warnings;
use Carp;
use Unicode::Japanese;
use Configuration::LexicalAnalyzer;
use Configuration::Block;

sub new {
    # $body: ���Ϥ�������
    my ($class,$body) = @_;
    my $this = {
	lex => Configuration::LexicalAnalyzer->new($body),
	
	parsed => [], # Configuration::Block (���줿���֤��¤֡�)
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
	return undef; # �⤦�֥�å���̵����
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
	    # �ɤ߲᤮���Τ��᤹��
	    $this->{lex}->rollback($token);

	    # �֥�å���ѡ�����
	    my $newblock = $this->_parse_block('block');
	    $block->set($newblock->block_name,$newblock);
	}
	elsif ($type eq 'blockend') {
	    # �ɤ߲᤮���Τ��᤹��
	    $this->{lex}->rollback($token);

	    # �����ǽ���ꡣ
	    last;
	}
	else {
	    die "Semantics error: pair, label or blockend is needed here.\n$token\n";
	}
    }
}

1;
