# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# nick,username,userhost等を持つ個人情報保持クラス。
# このオブジェクトはIrcIO::Serverが管理する。
# 
# my $info = new PersonalInfo(Nick => 'saitama');
# print $info->nick;
# $info->nick("taiyou");
# -----------------------------------------------------------------------------
package PersonalInfo;
use strict;
use warnings;
use Tiarra::IRC::Prefix;
use Tiarra::Utils;
use enum (qw(NICK USERNAME USERHOST REALNAME SERVER REMARK AWAY));
use Carp;
our $AUTOLOAD;

utils->define_array_attr_accessor(0,
				  qw(nick username userhost realname),
				  qw(server away));

sub new {
    my ($class,%args) = @_;

    # 最低限Nickさえ指定されていれば良い。
    unless (defined $args{Nick}) {
	croak "PersonalInfo must be created with Nick parameter.\n";
    }

    my $def_or_null = sub{ utils->get_first_defined(@_,''); };
    my $obj = bless [] => $class;
    $obj->[NICK] = $def_or_null->($args{Nick});
    $obj->[USERNAME] = $def_or_null->($args{UserName});
    $obj->[USERHOST] = $def_or_null->($args{UserHost});
    $obj->[REALNAME] = $def_or_null->($args{RealName});
    $obj->[SERVER] = $def_or_null->($args{Server});
    $obj->[REMARK] = undef; # HASH
    $obj->[AWAY] = $def_or_null->($args{Away});

    $obj;
}

sub info {
    my ($this, $wantarray) = @_;
    $wantarray ?
      @$this[NICK, USERNAME, USERHOST] :
	Tiarra::IRC::Prefix->new(
	    Nick => $this->nick,
	    User => $this->username,
	    Host => $this->userhost);
}

sub remark {
    my ($this, $key, $value) = @_;
    if (defined($value) or @_ >= 3) {
	$this->[REMARK] ||= {};
	$this->[REMARK]{$key} = $value;
    }

    $this->[REMARK] ?
      $this->[REMARK]{$key} : undef;
}

1;
