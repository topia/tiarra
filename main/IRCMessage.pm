# -----------------------------------------------------------------------------
# $Id: IRCMessage.pm,v 1.18 2004/06/04 12:57:30 topia Exp $
# -----------------------------------------------------------------------------
# IRCMessage��IRC�Υ�å�������ɽ�魯���饹�Ǥ����ºݤΥ�å�������UTF-8���ݻ����ޤ���
# ���Υ�å������Υѡ��������ꥢ�饤���������ƥ�å������������򥵥ݡ��Ȥ��ޤ���
# �ѡ����ȥ��ꥢ�饤���ˤ�ʸ�������ɤ���ꤷ�Ʋ������������ɤ��Ѵ����ޤ���
# Line��Encoding�ʳ��μ��ʤǥ��󥹥��󥹤���������ݤϡ�
# �ѥ�᡼���Ȥ���UTF-8���ͤ��Ϥ��Ʋ�������
# -----------------------------------------------------------------------------
# ������ˡ����
#
# $msg = new IRCMessage(Line => ':foo!~foo@hogehoge.net PRIVMSG #hoge :hoge',
#                       Encoding => 'jis');
# print $msg->command; # 'PRIVMSG'��ɽ��
#
# $msg = new IRCMessage(Server => 'irc.hogehoge.net', # Server��Prefix�Ǥ��ɤ���
#                       Command => '366',
#                       Params => ['hoge','#hoge','End of /NAMES list.']);
# print $msg->serialize('jis'); # ":irc.hogehoge.net 366 hoge #hoge :End of /NAMES list."��ɽ��
#
# $msg = new IRCMessage(Nick => 'foo',
#                       User => '~bar',
#                       Host => 'hogehoge.net', # �ʾ壳�ĤΥѥ�᡼���������Prefix => 'foo!~bar@hogehoge.net'�Ǥ��ɤ���
#                       Command => 'NICK',
#                       Params => 'huga', # Params�����Ǥ���Ĥ����ʤ饹���顼�ͤǤ��ɤ���(���λ���Params�Ǥʤ�Param�Ǥ��ɤ���)
#                       Remarks => {'saitama' => 'SAITAMA'}, # �����󡣥��ꥢ�饤���ˤϱƶ����ʤ���
# print $msg->serialize('jis'); # ":foo!~bar@hogehoge.net NICK :huga"��ɽ��
#
# $msg = new IRCMessage(Command => 'NOTICE',
#                       Params => ['foo','hugahuga']);
# print $msg->serialize('jis'); # "NOTICE foo :hugahuga"��ɽ��
#
package IRCMessage;
use strict;
use warnings;
use Carp;
use Unicode::Japanese;
use Data::Dumper;

# constants
use constant MAX_PARAMS => 14;

# variable indices
use constant PREFIX  => 0;
use constant COMMAND => 1;
use constant PARAMS  => 2;

use constant NICK    => 3;
use constant NAME    => 4;
use constant HOST    => 5;

use constant REMARKS => 6;

sub new {
    my ($class,%args) = @_;
    my $obj = bless [] => $class;
    $obj->[PREFIX] = undef;
    $obj->[COMMAND] = undef;
    $obj->[PARAMS] = undef;

    $obj->[NICK] = undef;
    $obj->[NAME] = undef;
    $obj->[HOST] = undef;

    $obj->[REMARKS] = undef;

    if (exists $args{'Line'}) {
	$args{'Line'} =~ s/\x0d\x0a$//s; # ������crlf�Ͼõ
	$obj->_parse($args{'Line'},$args{'Encoding'} || 'auto'); # Encoding����ά���줿�鼫ưȽ��
    }
    else {
	if (exists $args{'Prefix'}) {
	    $obj->[PREFIX] = $args{'Prefix'}; # prefix�����ꤵ�줿
	}
	elsif (exists $args{'Server'}) {
	    $obj->[PREFIX] = $args{'Server'}; # prefix����
	}
	elsif (exists $args{'Nick'}) {
	    $obj->[PREFIX] = $args{'Nick'}; # �ޤ���nick�����뤳�Ȥ�ʬ���ä�
	    if (exists $args{'User'}) {
		$obj->[PREFIX] .= '!'.$args{'User'}; # user�⤢�ä���
	    }
	    if (exists $args{'Host'}) {
		$obj->[PREFIX] .= '@'.$args{'Host'}; # host�⤢�ä���
	    }
	}

	# Command�����Ф�̵����Фʤ�ʤ���
	if (exists $args{'Command'}) {
	    ($obj->[COMMAND] = $args{'Command'}) =~ tr/a-z/A-Z/;
	}
	else {
	    die "You can't make IRCMessage without a COMMAND.\n";
	}

	if (exists $args{'Params'}) {
	    # Params�����ä������ϥ����顼�⤷���������ե�
	    my $params = $args{'Params'};
	    my $type = ref($params);
	    if ($type eq '') {
		$obj->[PARAMS] = [$params];
	    }
	    elsif ($type eq 'ARRAY') {
		my @copy_of_params = @{$params};
		$obj->[PARAMS] = \@copy_of_params; # ���ԡ����Ǽ
	    }
	}
	elsif (exists $args{'Param'}) {
	    # Param�����ä������ϥ����顼�Τ�
	    $obj->[PARAMS] = [$args{'Param'}];
	}
    }
    if (exists $args{'Remarks'}) {
	my %copy_of_remarks = %{$args{'Remarks'}};
	$obj->[REMARKS] = \%copy_of_remarks;
    }
    $obj->_parse_prefix;
    $obj;
}

sub clone {
    my ($this, %args) = @_;
    if ($args{deep}) {
	eval
	    Data::Dumper->new([$this])->Terse(1)->Deepcopy(1)->Purity(1)->Dump;
    } else {
	my @new = @$this;
	bless \@new => ref($this);
    }
}

sub _parse {
    my ($this,$line,$encoding) = @_;
    delete $this->[PREFIX];
    delete $this->[COMMAND];
    delete $this->[PARAMS];

    my $pos = 0;
    # prefix
    if (substr($line,0,1) eq ':') {
	# :�ǻϤޤäƤ�����
	my $pos_space = index($line,' ');
	$this->[PREFIX] = substr($line,1,$pos_space - 1);
	$pos = $pos_space + 1; # ���ڡ����μ�������Ƴ�
    }
    # command & params
    my @encodings = split(/\s*,\s*/, $encoding);
    my $unicode = new Unicode::Japanese;
    my $add_command_or_param = sub {
	my $value_raw = shift;
	my $use_encoding = $encodings[0];
	if (scalar(@encodings) != 1) {
	  my $auto_charset = $unicode->getcode($value_raw);
	  # getcode�Ǹ��Ф��줿ʸ�������ɤ�encodings�˻��ꤵ��Ƥ����Τ�����к��ѡ�
	  # ̵�����encodings�ΰ��ֺǽ����Ѥ��롣 (UTF-8��SJIS��ǧ�������ꤹ�뤿�ᡣ)
	  $use_encoding = ((map {$auto_charset eq $_ ? $_ : ()} @encodings), @encodings)[0];
	}
	my $value = do {
	    if (length ($value_raw) == 0) {
		'';
	    }
	    else {
		$unicode->set($value_raw,$use_encoding)->utf8;
	    }
	};

	if ($this->[COMMAND]) {
	    # command�Ϥ⤦����Ѥߡ����ϥѥ�᡼������
	    $this->push($value);
	}
	else {
	    # �ޤ����ޥ�ɤ����ꤵ��Ƥ��ʤ���
	    ($this->[COMMAND] = $value) =~ tr/a-z/A-Z/;
	}
    };
    while (1) {
	my $param = '';

	my $pos_space = index($line,' ',$pos);
	if ($pos_space == -1) {
	    # ��λ
	    $param = substr($line,$pos);
	}
	else {
	    $param = substr($line,$pos,$pos_space - $pos);
	}

	if ($param ne '') {
	    if (substr($param,0,1) eq ':') {
		# ����ʹߤ����ư�Ĥΰ�����
		$add_command_or_param->(substr($line,$pos+1)); # :�ϳ�����
		last; # �����ǽ���ꡣ
	    }
	    else {
		$add_command_or_param->($param);
	    }
	}

	if ($pos_space == -1) {
	    last;
	}
	else {
	    $pos = $pos_space + 1; # ���ڡ����μ�������Ƴ�
	}
    }

    # ����̤�������������å���
    # command��̵���ä���die��
    unless ($this->[COMMAND]) {
	die "IRCMessage parsed invalid one, which doesn't have command.\n  $line\n";
    }
}

sub _parse_prefix {
    my $this = shift;
    if (defined $this->[PREFIX]) {
	$this->[PREFIX] =~ m/^(.+?)!(.+?)@(.+)$/;
	if (!defined($1)) {
	    $this->[NICK] = $this->[PREFIX];
	}
	else {
	    $this->[NICK] = $1;
	    $this->[NAME] = $2;
	    $this->[HOST] = $3;
	}
    }
}

sub _update_prefix {
    my $this = shift;
    if (defined $this->[NICK]) {
	if (defined $this->[NAME]) {
	    $this->[PREFIX] =
		$this->[NICK].'!'.$this->[NAME].'@'.$this->[HOST];
	}
	else {
	    $this->[PREFIX] = $this->[NICK];
	}
    }
    else {
	delete $this->[NICK];
    }
}

sub serialize {
    # encoding���ά�����utf8�ˤʤ롣
    my ($this,$encoding) = @_;
    $encoding = 'utf8' unless defined $encoding;
    my $result = '';

    if ($this->[PREFIX]) {
	$result .= ':'.$this->[PREFIX].' ';
    }

    $result .= $this->[COMMAND].' ';

    if ($this->[PARAMS]) {
	my $unicode = new Unicode::Japanese;
	my $n_params = scalar @{$this->[PARAMS]||[]};
	for (my $i = 0;$i < $n_params;$i++) {
	    if ($i == $n_params - 1) {
		# �Ǹ�Υѥ�᥿�ʤ�Ƭ�˥������դ��Ƹ�ˤϥ��ڡ������֤��ʤ���
		# â��Ⱦ�ѥ��ڡ�������Ĥ�̵������ĥ����ǻϤޤäƤ��ʤ���Х������դ��ʤ���
		# �ѥ�᥿����ʸ����Ǥ��ä������㳰�Ȥ��ƥ������դ��롣
		my $arg = $unicode->set($this->[PARAMS]->[$i])->conv($encoding);
		if (length($arg) > 0 and
		      index($arg, ' ') == -1 and
			index($arg, ':') != 0) {
		    $result .= $arg;
		}
		else {
		    $result .= ":$arg";
		}
		# ������CTCP��å������򳰤��ƥ��󥳡��ɤ��٤������Τ�ʤ���
	    }
	    else {
		# �Ǹ�Υѥ�᥿�Ǥʤ���и�˥��ڡ������֤���
		$result .= $unicode->set($this->[PARAMS]->[$i])->conv($encoding).' ';
	    }
	}
    }

    return $result;
}

sub length {
    my ($this) = shift;
    length($this->serialize(@_));
}

sub prefix {
    my ($this,$new_val) = @_;
    $this->[PREFIX] = $new_val if defined($new_val);
    $this->[PREFIX];
}

sub nick {
    my ($this,$new_val) = @_;
    if (defined $new_val) {
	$this->[NICK] = $new_val;
	$this->_update_prefix;
    }
    $this->[NICK];
}

sub name {
    my ($this,$new_val) = @_;
    if (defined $new_val) {
	$this->[NAME] = $new_val;
	$this->_update_prefix;
    }
    $this->[NAME];
}

sub host {
    my ($this,$new_val) = @_;
    if (defined $new_val) {
	$this->[HOST] = $new_val;
	$this->_update_prefix;
    }
    $this->[HOST];
}

sub command {
    my ($this,$new_val) = @_;
    $this->[COMMAND] = $new_val if defined($new_val);
    $this->[COMMAND];
}

sub params {
    croak "Parameter specified to params(). You must mistaked with param().\n" if (@_ > 1);
    my $this = shift;
    $this->[PARAMS] = [] if !defined $this->[PARAMS];
    $this->[PARAMS];
}

sub n_params {
    scalar @{shift->params};
}

sub param {
    my ($this,$index,$new_value) = @_;
    croak "Parameter index wasn't specified to param(). You must be mistaken with params().\n" if (@_ <= 1);
    if (defined $new_value) {
	$this->[PARAMS]->[$index] = $new_value;
    }
    $this->[PARAMS]->[$index];
}

sub push {
    my $this = shift;
    CORE::push(@{$this->params}, @_);
}

sub pop {
    CORE::pop(@{shift->params});
}

sub remark {
    my ($this,$key,$value) = @_;
    # remark() -> HASH*
    # remark('key') -> SCALAR
    # remark('key','value') -> 'value'
    if (!defined($key)) {
	$this->[REMARKS] || {};
    }
    else {
	if (defined $value) {
	    if (defined $this->[REMARKS]) {
		$this->[REMARKS]->{$key} = $value;
	    }
	    else {
		$this->[REMARKS] = {$key => $value};
	    }
	}
	defined $this->[REMARKS] ?
	    $this->[REMARKS]->{$key} : undef;
    }
}

1;
