# -----------------------------------------------------------------------------
# $Id: Preprocessor.pm,v 1.8 2004/07/08 15:13:13 topia Exp $
# -----------------------------------------------------------------------------
# tiarra��conf�ե�����Υץ�ץ��å��Ǥ���
# ���Υ��饹�ϼ��Τ褦�ʵ�ǽ������ޤ���
#
# ��"%PRE{"��"}ERP%"�˶��ޤ줿��ʬ��perl��ʸ�Ȥ���ɾ��������̤򤽤ξ����������롣
#
# ��@include �ե�����̾
#   ���Τ褦�ʹԤ򡢤��Υե��������Ȥ��֤������롣
#
# ��@define ʸ����A ʸ����B 
#   ���Τ褦�ʹԤθ夫��ϡ��ե��������ʸ����A������ʸ����B���֤������롣
#   �ִ��������Ϥɤ��Ǥ��äƤ⹽��ʤ����㤨�м��Τ褦�������ͭ���Ǥ��롣
#   @define DEBUG 1
#   @if 'DEBUG' == '1'
#     debug: a
#   @endif
#   �㳰��@undefʸ������ʸ���Ф��Ƥ��ִ����Ԥʤ��ʤ���
#
# ��@undef ʸ����A
#   @define����������ִ��򡢼��ιԤ��饭��󥻥뤹�롣
#
# ��@if ��
# ��@elsif
#   ����perl��ʸ�Ȥ���ɾ��������̤����ʤ�@elsif��@else��@endif�ޤǤ�ͭ���ʹԤȤߤʤ���
#   if-elsif-else-endif��ʸ�ϴ���Ǥ�����Ҥˤ����������롣
#
# ��@else
# ��@endif
#   ���������פǤ�����
#
# ��@ifdef ʸ����
# ��@ifndef ʸ����
#   ����ʸ����@define����Ƥ����顢�㤷���Ϥ���Ƥ��ʤ��ä��顣
#
# ��@message ʸ����
#   ɸ����Ϥˤ���ʸ�����Ф���â��ʸ�������ɤ��Ѵ��ϰ��ڹԤ��ʤ��Τ�
#   ASCIIʸ���ʳ���Ф��ΤϤ�᤿�����ɤ���
#
# -----------------------------------------------------------------------------
# ���%PRE{ }ERP%��ɾ�����졢����@ʸ��ɾ������롣
# %PRE{ }ERP%��ʣ���ιԤ��ϤäƤ��ɤ���
# -----------------------------------------------------------------------------
package Configuration::Preprocessor;
use strict;
use warnings;
use Carp;
use IO::File;
use UNIVERSAL;
our %initial_definition;

sub preprocess {
    # IO::Handle�ޤ��ϥե�����̾���ļ�ꡢ�ץ�ץ����η�̤��֤���
    my $handle = shift;

    Configuration::Preprocessor
	->new
	->execute($handle);
}

sub new {
    my ($class,$filename) = @_;
    my $this = {
	included => {}, # �ե�����ѥ� => 1 (¿��include�Υ����å��˻Ȥ��롣)
	consts => {%initial_definition}, # @define���줿�ޥ���̾ => ���
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
	    # IO::Handle���ä���
	    # ��ʣ�����å����Բ�ǽ��
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

    # �ե��������Ƭ����Ǹ�ޤ��ɤࡣ
    my $body = '';
    foreach (<$handle>) {
	tr/\r\n//d;
	$body .= "$_\n";
    }
    undef $handle;

    # %PRE{ }ERP% �ִ�
    $body = $this->_eval_pre($body);

    # ��Ԥ����ɤ��@����������
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

    my @ifstack = (); # ����if,elsif,else,endif�����ޤǤ�ư��(���ʤ�Ĥ������ʤ�ä�)

    my $result = '';
    foreach my $line (split /\n/,$body) {
	# ���ιԤ�@undef,@ifdef,@ifndefʸ�Ǥʤ��ʤ顢@define���줿���Ƥ��ִ���¹ԡ�
	if ($line !~ m/^\s*\@\s*(?:undef|ifdef|ifndef)\s+/) {
	    while (my ($key,$value) = each %{$this->{consts}}) {
		$line =~ s/\Q$key\E/$value/g;
	    }
	}

	if (@ifstack > 0) {
	    # ifʸ�Υ֥�å���Ǥ��롣
	    my $action = $ifstack[@ifstack - 1];
	    
	    if ($line =~ m/^\s*\@\s*(?:if|elsif|ifdef|ifndef|else|endif)/) {
		# ���֤��Ѥ���ǽ�������롣
		# �Ȥꤢ�������⤷�ʤ���
	    }
	    else {
		# ���֤��Ѥ��ʤ���
		# �ΤƤ�ɬ�פ�����ʤ�ΤƤƼ��ء�
		if (!$action) {
		    next;
		}
	    }
	}
	
	if ($line =~ m/^\s*\@/) {
	    # @�ǻϤޤäƤ��롣
	    # �Ȥꤢ������Ƭ��@���äƺǽ�ȺǸ��\s������оä���
	    $line =~ s/^\s*\@\s*|\s*$//g;

	    # ifdef��ifndef��ifʸ�˽񴹤���
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
		    # ���Υե졼�ब¸�ߤ�����Ĳ��Υե졼��Υ��������'�ä�'�ʤ顢̵���˾ä���
		    push @ifstack,0;
		}
		else {
		    # ɾ����̤����ʤ顢����if,elsif,else,endif���ФƤ���ޤǻĤ������ʤ餽��餬�Ф�ޤǾä���
		    my $cond_evaluated = eval(defined $1 ? $1 : '');
		    if ($@) {
			die "Exception in evaluating: \@$line\n$@\n";
		    }
		    push @ifstack,$cond_evaluated;
		}
	    }
	    elsif ($line =~ m/^elsif\s+(.+)$/) {
		# elsif�Ͽ�����if�ե졼����ɲä�����Ϥ��������ߤΥե졼��˾�񤭤��롣
		#
		# ���ߤΥե졼��Υ��������'�Ĥ�'���ä����...
		#   if,elsif,else,endif���ФƤ���ޤ�̵���˾ä���
		#
		# '�ä�'���ä����...
		#   ���ʤ�if,elsif,else,endif���ФƤ���ޤǻĤ������ʤ餽��餬�Ф�ޤǾä���
		#
		# â�������ߤΥե졼�ब�ȥåץ�٥�Ǥʤ��ä����ǡ�
		# ���β��Υ�٥�Υ��������'�ä�'���ä����ϡ�̵���˾ä���
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
		# else�Ͽ�����if�ե졼����ɲä��뤳�ȤϤ��������ߤΥե졼��˾�񤭤��롣
		#
		# ���ߤΥե졼��Υ��������'�Ĥ�'���ä����...
		#   if,elsif,else,endif���ФƤ���ޤ�̵���˾ä���
		#
		# '�ä�'���ä����...
		#   if,elsif,else,endif���ФƤ���ޤ�̵���˻Ĥ���
		#
		# â�������ߤΥե졼�ब�ȥåץ�٥�Ǥʤ��ä����ǡ�
		# ���β��Υ�٥�Υ��������'�ä�'���ä����ϡ�̵���˾ä���
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
		    # ����if�֥�å���λ���롣
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

    # �ǽ�Ū��@ifstack�����ˤʤäƤ��ʤ��Ȥ������ϡ�@if�֥�å�������äƤ��ʤ��Ȥ�������
    if (@ifstack > 0) {
	die "There's \@if block which is not terminated.\n"
    }

    $result;
}

1;
