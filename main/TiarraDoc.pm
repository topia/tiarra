# ------------------------------------------------------------------------
# $Id: TiarraDoc.pm,v 1.1 2003/08/04 09:29:20 admin Exp $
# ------------------------------------------------------------------------
# tiarra-doc�Υѡ����ȥȥ�󥹥졼������
# ------------------------------------------------------------------------
use strict;
use warnings;
use Unicode::Japanese;
use IO::File;

package DocParser;
use Carp;

sub new {
    my ($class,$fpath) = @_;
    my $this = {
	fpath => $fpath,

	docs => undef, # {�ѥå�����̾ => DocPod}
    };
    bless $this,$class;
}

sub makeconf {
    # conf�Υ֥�å����������롣
    # �����: ([�֥�å�̾,info,�֥�å�(ʸ����)],...)
    # �����顼����ƥ����ȤǸƤ֤�croak��
    croak "You can't call DocParser->makeconf directly.";
}

sub makehtml {
    croak "You can't call DocParser->makehtml directly.";
}

sub getdoc {
    # �ѥå�����̾���ά����ȡ����Ǥ���ĤǤ���Ф�����֤���
    # ʣ�������croak���롣��Ĥ�̵�����undef���֤���
    my ($this,$pkg_name) = @_;

    if (!defined $this->{docs}) {
	$this->{docs} = {};
	my @dummy = $this->_parse_docpod;
    }

    if (defined $pkg_name) {
	$this->{docs}{$pkg_name};
    }
    else {
	my @keys = keys %{$this->{docs}};
	if (@keys == 0) {
	    undef;
	}
	elsif (@keys == 1) {
	    $this->{docs}{$keys[0]};
	}
	else {
	    croak "You can't ommit \$pkg_name if there's multiple poddocs.";
	}
    }
}

sub _parse_docpod {
    # tiarra�ɥ�����ȷ�����pod��õ���ƥإå���ѡ��������֤���
    # Ʊ��ѥå������˥ɥ�����Ȥ���İʾ夢�ä���die��
    # �����顼����ƥ����ȤǸƤФ줿��croak��
    # ����ͤη���: (DocPod,DocPod,...)
    croak "Don't call DocParser->_parse_docpod in scalar context." if !wantarray;
    my $this = shift;
    my @pods = $this->_parse_pod;
    my $header_re = qr/^\s*(.+?)\s*:\s*(.+)$/;

    my @result;
    my $new_doc = sub {
	my ($pkg_name,$header,$remaining) = @_;
	# ���ˤ��Υѥå������Υɥ�����Ȥ��Ѱդ���Ƥ��ʤ�����
	foreach (@result) {
	    if ($_->pkg_name eq $pkg_name) {
		die "$pkg_name has multiple documents.\n";
	    }
	}

	my $docpod = DocPod->new($pkg_name,$header,$remaining);
	push @result,$docpod;
	$this->{docs}{$pkg_name} = $docpod;
    };
    
    foreach my $pod (@pods) {
	my @lines = split /\x0a/,$pod->[1];
	if (@lines == 0) {
	    next; # ����ϥɥ�����ȤǤʤ���
	}
	elsif ($lines[0] =~ m/$header_re/) {
	    # �إå��ν����ޤǤ�ѡ������롣
	    my $header = {};
	    my $remaining_start = @lines;
	    foreach (my $i = 0; $i < @lines; $i++) {
		if ($lines[$i] =~ m/$header_re/) {
		    $header->{$1} = $2;
		}
		else {
		    # �����ǥإå�����ꡣ
		    $remaining_start = $i;
		    last;
		}
	    }

	    # ���ƤιԤˤĤ��ơ���Ƭ�������ζ����õ�롣
	    (my $remaining = join "\n",map {
		s/^\s*|\s*$//g;
		$_;
	    } @lines[$remaining_start .. (@lines-1)]) =~ s/^\s*|\s*$//g;
	    $new_doc->($pod->[0],$header,$remaining);
	}
    }

    @result;
}

sub _parse_pod {
    # =pod��=cut�˰Ϥޤ줿�ϰϤ��֤���
    # �����: ([�ѥå�����̾,pod�ϰ�],[�ѥå�����̾,pod�ϰ�],...)
    # �����顼����ƥ����ȤǸƤФ줿��croak��
    croak "Don't call DocParser->_parse_pod in scalar context." if !wantarray;
    my $this = shift;
    my @lines = split /\x0d?\x0a/,$this->_get_content;

    my @result;
    my $search_start_pos = 0;
    my $pkg_name;
    while (1) {
	# =pod��õ��
	my $found_pod_line;
	for (my $i = $search_start_pos; $i < @lines; $i++) {
	    if ($lines[$i] =~ m/^\s*=pod\s*$/) {
		$found_pod_line = $i;
		last;
	    }
	    elsif ($lines[$i] =~ m/\s*package\s+(.+?);/) {
		$pkg_name = $1;
	    }
	}

	if (defined $found_pod_line) {
	    # ���ä�������=cut��õ����
	    my $found_cut_line;
	    for (my $i = $found_pod_line+1; $i < @lines; $i++) {
		if ($lines[$i] =~ m/^\s*=cut\s*$/) {
		    $found_cut_line = $i;
		    last;
		}
	    }
	    if (defined $found_cut_line) {
		# ���ä��������ޤ�=pod & =cut��
		push @result,[
		    $pkg_name,
		    join("\n",@lines[$found_pod_line+1 .. $found_cut_line-1])
		];
		$search_start_pos = $found_cut_line+1;
	    }
	    else {
		# ̵�������顼��
		die "$this->{fpath} has unbalanced =pod and =cut\n";
	    }
	}
	else {
	    # ̵���������ǽ���ꡣ
	    last;
	}
    }

    @result;
}

sub _get_content {
    # �ե��������Ȥ�utf8���֤���
    my $this = shift;

    my $fh = IO::File->new($this->{fpath},'r');
    if (!defined $fh) {
	die "Couldn't open file $this->{fpath}.\n";
    }
    local $/ = undef;
    my $content = <$fh>;
    $fh->close;

    my $code = $this->_getcode($content);
    if ($code eq 'unknown') {
	die "Couldn't determine the charset of $this->{fpath}.\n";
    }

    Unicode::Japanese->new($content,$code)->utf8;
}

sub _getcode {
    # ʸ�������ɤ�Ƚ�̤��롣
    my ($this,$content) = @_;
    my $unijp = Unicode::Japanese->new;

    if ((my $code = $unijp->getcode($content)) ne 'unknown') {
	# Ƚ�̤Ǥ����顢������֤���
	$code;
    }
    else {
	# ���줾��ιԤˤĤ���getcode��¹Ԥ���¿������롣
	my $total_for_each = {};
	foreach (split /[\r\n]/,$content) {
	    if ((my $c = $unijp->getcode($_)) ne 'unknown') {
		$total_for_each->{$c} = ($total_for_each->{$c} || 0) + 1;
	    }
	}

	my @rank = sort {
	    $b <=> $a;
	} values %$total_for_each;
	if (@rank == 0) {
	    # ����unknown���ä�!
	    # ����̵���Τ�unknown���֤���
	    'unknown';
	}
	elsif (@rank == 1) {
	    # ���䤬��Ĥ�����������֤���
	    $rank[0];
	}
	else {
	    # ����Υȥåפ�ascii���ä��顢�����ܤΤ�Τ��֤���
	    # �����Ǥʤ���Хȥåפ��֤���
	    if ($rank[0] eq 'ascii') {
		$rank[1];
	    }
	    else {
		$rank[0];
	    }
	}
    }
}

package DocParser::Module;
use base qw/DocParser/;
use Carp;

sub new {
    my $class = shift;
    $class->SUPER::new(@_);
}

sub makeconf {
    my $this = shift;
    my $indent_level = shift || 2;
    croak "Don't call DocParser->makeconf in scalar context." if !wantarray;

    map {
	my $pod = $_;
	my $conf = eval {
	    $this->_makeconf($pod,$indent_level);
	}; if ($@) {
	    die $pod->pkg_name.": $@";
	}
	[$pod->pkg_name,$pod->header->{info},$conf];
    } $this->_parse_docpod;
}

sub _makeconf {
    my ($this,$pod,$indent_level) = @_;
    my $result = '';

    # default�إå��˱�����+��-�������ꤹ�롣
    # â��no-switch���������Ƥ��ƿ��Ǥ���С�����򤷤ʤ���
    if ($pod->header->{'no-switch'}) {
	$result .= $pod->pkg_name." {\n";
    }
    else {
	my $enabled = $pod->header->{default};
	if (defined $enabled) {
	    my $switch = {on => '+' , off => '-'}->{$enabled};
	    if (defined $switch) {
		$result .= $switch;
	    }
	    else {
		die "Its `default' header is invalid: $enabled\n";
	    }
	}
	else {
	    die "It doesn't have `default' header.\n";
	}
	$result .= ' '.$pod->pkg_name." {\n";
    }
    

    # info�إå������Ƥ���ϡ�̵����Х��顼��
    # ������info-is-omitted���������Ƥ��ƿ��Ǥ���н��Ϥ��ʤ���
    my $indent = ' ' x $indent_level;
    my $block_indent = '';
    my $info = $pod->header->{info};
    if (defined $info) {
	if (!$pod->header->{'info-is-omitted'}) {
	    $result .= "$indent# $info\n\n";
	}
    }
    else {
	die "It doesn't have `info' header.\n";
    }

    # �롼��:
    # '#'�ǻϤޤ�ԤϤ��Τޤ޽��ϡ�
    # ���Ԥ⤽�Τޤ޽��ϡ�
    # key:value�����ˤʤäƤ�����ʬ�⤽�Τޤ޽��Ϥ��뤬��
    # ����key��Ƭ��'-'���դ��Ƥ����顢����򥳥��ȥ����ȡ�
    my @lines = split /\n/,$pod->content;
    for (my $i = 0; $i < @lines; $i++) {
	my $line = $lines[$i];
	
	my $error = sub {
	    my $errstr = shift;
	    
	    # ����5�Ԥȶ��˥��顼�Ԥ򼨤���
	    my $region_lines = 5;
	    my $begin = $i - $region_lines;
	    if ($begin < 0) {
		$begin = 0;
	    }
	    my $end = $i + $region_lines;
	    if ($end >= @lines) {
		$end = @lines-1;
	    }
	    my $list = join '',map {
		if ($_ == $i) {
		    "=> |$lines[$_]\n";
		}
		else {
		    "   |$lines[$_]\n";
		}
	    } ($begin .. $end);

	    die "$errstr\n$list";
	};

	$result .= $indent . do {
	    if ($line eq '') {
		'';
	    }
	    elsif ($line =~ m/^\s*#/) {
		(my $stripped = $line) =~ s/^\s*//;
		"$block_indent$stripped";
	    }
	    elsif ($line =~ m/^(.+?)\s*:\s*(.+)$/) {
		my ($key,$value) = ($1,$2);
		if ($key =~ s/^-//) {
		    "$block_indent#$key: $value";
		}
		else {
		    "$block_indent$key: $value";
		}
	    }
	    elsif ($line =~ m/^(.+?)\s*{\s*$/) {
		$_ = "$block_indent$1 {";
		$block_indent .= ' ' x 2;
		$_;
	    }
	    elsif ($line =~ m/^}\s*$/) {
		substr($block_indent, 0, 2) = '';
		"$block_indent}";
	    }
	    else {
		$error->('illegal line');
	    }
	} . "\n";
    }

    $result . '}';
}

package DocPod;
our $AUTOLOAD;

sub new {
    my ($class,$pkg_name,$header,$content) = @_;
    my $this = {
	pkg_name => $pkg_name,
	header => $header,
	content => $content,
    };
    bless $this,$class;
}

sub AUTOLOAD {
    my ($this,$arg) = @_;
    (my $key = $AUTOLOAD) =~ s/.+?:://g;

    my $val = $this->{$key};
    if (defined $arg && ref($val) eq 'HASH') {
	$val->{$arg};
    }
    else {
	$val;
    }
}

1;
