# -----------------------------------------------------------------------------
# $Id: L10N.pm,v 1.1 2003/09/20 11:06:19 admin Exp $
# -----------------------------------------------------------------------------
# ��å������Υ����饤����Ԥ��٤Υ��饹��
# ���Υ��饹��Tiarra��¾�Υ��饹�˰�¸���ޤ���
# -----------------------------------------------------------------------------
# �Ȥ���:
#
# -----------------------------------------------------------------------------
package L10N;
use strict;
use warnings;
use Carp;
# ���ꤵ�줿���줬���դ���ʤ����ˡ�ͥ�褷�����Ф����졣
our $secondary_language = 'en';

# {�ѥå�����̾ => L10N}
our %instances;
sub _instance {
    my $this = shift;
    if (ref $this) {
	# ���Τޤ�
	$this;
    }
    else {
	# �������caller�Υѥå��������Ф��ƤΥ��󥹥��󥹤��֤���
	my ($pkg) = caller(1);
	my $in = $instances{$pkg};
	if (!defined $in) {
	    $in = $instances{$pkg} = L10N->new($pkg);
	}
	$in;
    }
}

# ����̾��ά�������Ф�����
our $default_language = 'ja';
sub default_language {
    if (@_ == 0) {
	$default_language;
    }
    elsif (@_ == 1) {
	$default_language = $_[0];
    }
    else {
	$default_language = $_[1];
    }
}

sub instance {
    my $this = _instance(shift);
}

*reg = \&register;
sub register {
    my ($this, %args) = @_;
    $this = _instance($this);

    while (my ($key, $value) = each %args) {
	$this->{messages}{$key} = $value;
    }
    $this;
}

sub new {
    my ($class, $pkg_name) = @_;
    my $this = {
	pkg_name => $pkg_name,
	messages => {}, # {��å�����̾ => {����̾ => ��å�����}}
    };
    bless $this => $class;
}

sub get {
    my ($this, $key, $lang) = @_;
    $this = _instance($this);
    if (!defined $key) {
	return $this->_new_autoload;
    }
    
    $lang = $default_language if !defined $lang;

    my $msg_langs = $this->{messages}{$key};
    if (defined $msg_langs) {
	my $msg = $msg_langs->{$lang};
	if (defined $msg) {
	    $msg;
	}
	elsif (defined($_ = $msg_langs->{$secondary_language})) {
	    $_;
	}
	else {
	    (values %$msg_langs)[0];
	}
    }
    else {
	undef;
    }
}

# -----------------------------------------------------------------------------
package L10N::Autoload;
our $AUTOLOAD;

sub AUTOLOAD {
    my ($this, $lang) = @_;
    if ($AUTOLOAD =~ /::DESTROY$/) {
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    $this->{l10n}->get($key, $lang);
}

package L10N;
sub _new_autoload {
    my $this = shift;
    bless {l10n => $this} => 'L10N::Autoload';
}

1;
