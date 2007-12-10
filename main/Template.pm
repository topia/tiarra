# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
package Template;
use strict;
use warnings;
use Symbol;
use Carp;
use UNIVERSAL;
our $AUTOLOAD;

sub new {
    # $fpath: �ƥ�ץ졼�ȤȤ��ƻ��Ѥ���ե�����
    # $strip_empty_line (��ά��ǽ): <!begin>��<!end>��ľ��β��Ԥ������뤫�ɤ�����
    my ($class,$fpath,$strip_empty_line) = @_;
    my $this = {
	original => undef, # �꡼�դ�<!mark:foo>���ִ�������ȡ�
	current => undef, # <&foo>���ִ�������Τ�Ρ�
	leaves => {}, # {̾�� => Template}
	parent => undef, # ���줬�ȥåץ�٥�Ǥʤ���С���(Template)��
	leafname => undef, # ���줬�ȥåץ�٥�Ǥʤ���С��꡼��̾��
    };
    bless $this,$class;

    local $/ = undef;
    my $fh = gensym;
    open($fh,'<',$fpath) or croak "couldn't open file $fpath";
    my $source = <$fh>;
    close($fh);
    ungensym($fh);

    # <!begin:foo>��<!end:foo>��ľ�夬���ԥ����ɤʤ顢�����ä���
    # ���β��ԥ����ɤ���Ϥޤ륹�ڡ����ޤ��ϥ��֤⡢����ǥ�Ȥȸ������ƾä���
    if ($strip_empty_line) {
	$source =~ s/(<!begin:.+?>|<!end:.+?>)\x0d?\x0a[ \t]*/$1/g;
    }
    
    $this->_load($source);
    $this;
}

sub reset {
    my $this = shift;
    $this->{current} = $this->{original};
    $this;
}

sub expand {
    # $t->expand({foo => '---' , bar => '+++'});
    # �⤷����
    # $t->expand(foo => '---' , bar => '+++');

    # ���Υ᥽�åɤϡ�������˸���줿���������������
    # �ϥ��ե�˥ե�����Хå������������ޤ���
    # �Ĥޤꡢ<&foo-bar>�Ȥ��������򡢥���̾"foo_bar"�ǻ��ꤹ���������ޤ���
    my $this = shift;
    my $hash = do {
	if (@_ == 1 && UNIVERSAL::isa($_[0],'HASH')) {
	    $_[0];
	}
	elsif (@_ % 2 == 0) {
	    my %h = @_;
	    \%h;
	}
	else {
	    croak "Illegal argument for Template->expand";
	}
    };
    while (my ($key,$value) = each %$hash) {
	# $key,$value���˥����顼�ͤǤʤ���Фʤ�ʤ���
	# ��ե��ʤ饨�顼��
	if (!defined $value) {
	    croak "Values must not be undef; key: $key";
	}
	if (ref($key) ne '') {
	    croak "Keys and values must be scalar values: $key";
	}
	if (ref($value) ne '') {
	    croak "Keys and values must be scalar values: $value";
	}

	if ($this->{current} !~ s/<\&\Q$key\E>/$value/g) {
	    # ̵�������������������ϥ��ե���Ѥ��Ƥߤ롣
	    (my $tred_key = $key) =~ tr/_/-/;
	    if ($this->{current} !~ s/<\&\Q$tred_key\E>/$value/g) {
		# ���Τ褦�ʥ�����¸�ߤ��ʤ��ä����ٹ�
		carp "No <\&$key> are in template, or you have replaced it already.";
	    }
	}
    }
    $this;
}

sub add {
    my $this = shift;
    
    # �����������expand���롣
    if (@_ > 0) {
	eval {
	    $this->expand(@_);
	}; if ($@) {
	    croak $@;
	}
    }

    # �Ƥ�¸�ߤ��ʤ����croak��
    if (!defined $this->{parent}) {
	croak "This template doesn't have its parent.";
    }

    # �Ƥ�<!mark:foo>��ľ���ˡ����Υ꡼�դ�������
    my $str = $this->str;
    $this->{parent}{current} =~ s/(<!mark:\Q$this->{leafname}\E>)/$str$1/g;

    # �ꥻ�å�
    $this->reset;

    $this;
}

sub str {
    my $this = shift;
    my $result = $this->{current};

    # ̤�ִ���<&foo>������Ф����ä���carp��
    while ($result =~ s/<\&(.+?)>//) {
	carp "Unexpanded tag: <\&$1>";
    }

    # <!mark:foo>��ä���
    $result =~ s/<!mark:.+?>//g;

    $result;
}

sub leaf {
    my ($this,$leafname) = @_;
    $this->{leaves}{$leafname};
}

sub AUTOLOAD {
    my $this = shift;
    (my $leafname = $AUTOLOAD) =~ s/.+?:://g;

    # ��������������ϥϥ��ե���ִ���
    $leafname =~ tr/_/-/;
    $this->{leaves}{$leafname};
}

sub _new_leaf {
    my ($class,$parent,$leafname,$source) = @_;
    my $this = {
	original => undef,
	current => undef,
	leaves => {},
	parent => $parent,
	leafname => $leafname,
    };
    bless $this,$class;

    $this->_load($source);
}

sub _load {
    my ($this,$source) = @_;

    # <!begin:foo> ... <!end:foo>��<!mark:foo>���ִ����Ĥġ����Υ꡼�դ���¸��
    while ($source =~ s/<!begin:(.+?)>(.+?)<!end:\1>/<!mark:$1>/s) {
	my ($leafname,$source) = ($1,$2);
	
	if (defined $this->{leaves}{$leafname}) {
	    # ���ˤ��Υ꡼�դ��������Ƥ�����croak��
	    croak "duplicated leaves in template: $leafname";
	}
	else {
	    $this->{leaves}{$leafname} = Template->_new_leaf($this,$leafname,$source);
	}
    }
    $this->{original} = $this->{current} = $source;
    
    $this;
}

1;
