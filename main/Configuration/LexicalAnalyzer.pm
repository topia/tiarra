# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# conf�ե�����λ�����ϴ
# ʸ̮�˱����ƥȡ��������Ϥ��Ƥ�����
# -----------------------------------------------------------------------------
package Configuration::LexicalAnalyzer;
use strict;
use warnings;

sub new {
    # $body: ���Ϥ���������
    my ($class,$body) = @_;
    my $this = {
	body => $body, # �ȡ����󤬲��Ϥ�����٤ˡ����Ϥ��줿�ȡ����󤬾ä���Ƥ�����
	linecount => 0, # ���ߤɤιԤ���Ϥ��Ƥ��뤫�����ξ���ϥ��顼���ˤ����Ȥ��ʤ���
	rollbackcount => 0, # ���߲��Ԥ��ɤ߲᤮�Ƥ��뤫��
    };
    bless $this;
}

sub linecount {
    shift->{linecount};
}

sub next {
    # ���Υȡ���������롣�⤦�ĤäƤ��ʤ����undef���֤���
    # $contenxt: 'outside' | 'block'
    #
    # outside: �����֥�å��γ�¦�˵����򼨤���
    # block: �����֥�å���˵����򼨤���
    #
    # �����: (�ȡ�����,������)
    # �����פȤ��Ƥϼ��Τ褦�ʤ�Τ����롣
    # 'label' => �֥�å��Υ�٥�
    # 'blockstart' => �֥�å��λϤޤ�
    # 'blockend' => �֥�å��ν����
    # 'pair' => �������ͤΥڥ�
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

    my $labelchar = qr{[^\s{}]}; # �֥�å�̾�Ȥ��Ƶ������ʸ��
    my $label = qr{^(?:(?:\+|\-)\s+)?$labelchar+}; # �֥�å��Υ�٥�

    my $blockstart = qr|^{|; # �֥�å��γ���

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
		# �����ʥȡ�����
		die "Syntax error: $line\n";
	    }
	};
	# ɬ�פʤ�Ĥ����ʬ�����Хå�
	$this->rollback($line);
	($token,$type);
    }
    else {
	undef;
    }
}

sub _context_block {
    my $this = shift;

    my $keychar = qr{[^\s{}:]}; # �����Ȥ��Ƶ������ʸ��
    my $pair = qr{^$keychar+\s*:.*$}; # �������ͤΥڥ�

    my $labelchar = qr{[^\s{}:]}; # �֥�å���֥�å��Υ�٥�Ȥ��Ƶ������ʸ��
    my $label = qr{^$labelchar+}; # �֥�å��Υ�٥�

    my $blockstart = qr|^{|; # �֥�å��γ���
    my $blockend = qr|^}|; # �֥�å��ν�λ

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
		# �����ʥȡ�����
		die "Syntax error: $line\n";
	    }
	};
	# ɬ�פʤ�Ĥ����ʬ�����Хå�
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
	    # �⤦�Ԥ�̵����
	    return undef;
	}

	# �Ȥꤢ������Ƭ��Ԥ������
	$this->{body} =~ s/^(.*?)(?:\n|$)//s;
	my $line = $1;

	if (defined $line) {
	    # �ޤ��Ԥ��ĤäƤ롣
	    # �ǽ�ȺǸ�ζ������
	    if ($this->{rollbackcount} > 0) {
		# �ɤ߲᤮�Ƥ���Τǥ�����Ȥ��ʤ���
		$this->{rollbackcount}--;
	    }
	    else {
		$this->{linecount}++;
	    }
	    $line =~ s/^\s*|\s*$//g;
	    
	    # ���ιԤ䥳���ȹԤʤ����Ф��Ƽ��ء�
	    if ($line eq '' || $line =~ m/^#/) {
		next;
	    }
	    else {
		return $line;
	    }
	}
	else {
	    # �⤦�Ԥ�̵����
	    return undef;
	}
    }
}

sub rollback {
    my ($this,$line) = @_;

    # �ǽ�ȺǸ�ζ������
    $line =~ s/^\s*|\s*$//g;

    # �ޤ���Ȥ��ĤäƤ���Х����󥿤��Ƚ��᤹��
    if ($line ne '') {
	$this->{body} = "$line\n$this->{body}";
	$this->{rollbackcount}++;
    }
}

1;
