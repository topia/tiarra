# -----------------------------------------------------------------------------
# $Id: PersonalInfo.pm,v 1.8 2003/09/28 05:15:22 admin Exp $
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
use Carp;
our $AUTOLOAD;

use constant NICK     => 0;
use constant USERNAME => 1;
use constant USERHOST => 2;
use constant REALNAME => 3;
use constant SERVER   => 4;
use constant REMARK   => 5;
use constant AWAY     => 6;

sub new {
    my ($class,%args) = @_;

    # 最低限Nickさえ指定されていれば良い。
    unless (defined $args{Nick}) {
	croak "PersonalInfo must be created with Nick parameter.\n";
    }

    my $def_or_null = sub{ defined $_[0] ? $_[0] : '' };
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
	sprintf('%s!%s@%s', $this->nick, $this->username, $this->userhost);
}

BEGIN {
    foreach my $constname (qw/NICK USERNAME USERHOST REALNAME SERVER AWAY/) {
	my $methodname = lc $constname;
	eval qq{
	    sub $methodname {
		my (\$this, \$new) = \@_;

		if (defined \$new) {
		    \$this->[$constname] = \$new;
		}
		\$this->[$constname];
	    }
	};
    }
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
