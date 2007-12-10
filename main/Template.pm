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
    # $fpath: テンプレートとして使用するファイル
    # $strip_empty_line (省略可能): <!begin>や<!end>の直後の改行を削除するかどうか。
    my ($class,$fpath,$strip_empty_line) = @_;
    my $this = {
	original => undef, # リーフを<!mark:foo>に置換した中身。
	current => undef, # <&foo>を置換した後のもの。
	leaves => {}, # {名前 => Template}
	parent => undef, # これがトップレベルでなければ、親(Template)。
	leafname => undef, # これがトップレベルでなければ、リーフ名。
    };
    bless $this,$class;

    local $/ = undef;
    my $fh = gensym;
    open($fh,'<',$fpath) or croak "couldn't open file $fpath";
    my $source = <$fh>;
    close($fh);
    ungensym($fh);

    # <!begin:foo>や<!end:foo>の直後が改行コードなら、それを消す。
    # その改行コードから始まるスペースまたはタブも、インデントと見做して消す。
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
    # もしくは
    # $t->expand(foo => '---' , bar => '+++');

    # このメソッドは、キー内に現われたアンダースコアを
    # ハイフンにフォールバックする事が出来ます。
    # つまり、<&foo-bar>というタグを、キー名"foo_bar"で指定する事が出来ます。
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
	# $key,$value共にスカラー値でなければならない。
	# リファならエラー。
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
	    # 無い。アンダースコアをハイフンに変えてみる。
	    (my $tred_key = $key) =~ tr/_/-/;
	    if ($this->{current} !~ s/<\&\Q$tred_key\E>/$value/g) {
		# そのようなキーは存在しなかった。警告。
		carp "No <\&$key> are in template, or you have replaced it already.";
	    }
	}
    }
    $this;
}

sub add {
    my $this = shift;
    
    # 引数があればexpandする。
    if (@_ > 0) {
	eval {
	    $this->expand(@_);
	}; if ($@) {
	    croak $@;
	}
    }

    # 親が存在しなければcroak。
    if (!defined $this->{parent}) {
	croak "This template doesn't have its parent.";
    }

    # 親の<!mark:foo>の直前に、このリーフを挿入。
    my $str = $this->str;
    $this->{parent}{current} =~ s/(<!mark:\Q$this->{leafname}\E>)/$str$1/g;

    # リセット
    $this->reset;

    $this;
}

sub str {
    my $this = shift;
    my $result = $this->{current};

    # 未置換の<&foo>があればそれを消してcarp。
    while ($result =~ s/<\&(.+?)>//) {
	carp "Unexpanded tag: <\&$1>";
    }

    # <!mark:foo>を消す。
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

    # アンダースコアはハイフンに置換。
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

    # <!begin:foo> ... <!end:foo>を<!mark:foo>に置換しつつ、そのリーフを保存。
    while ($source =~ s/<!begin:(.+?)>(.+?)<!end:\1>/<!mark:$1>/s) {
	my ($leafname,$source) = ($1,$2);
	
	if (defined $this->{leaves}{$leafname}) {
	    # 既にこのリーフが定義されていたらcroak。
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
