# -----------------------------------------------------------------------------
# $Id: BulletinBoard.pm,v 1.2 2003/03/15 12:37:43 admin Exp $
# -----------------------------------------------------------------------------
# モジュール間の情報伝達に使われるクラス。
# インスタンスは共有される。
# -----------------------------------------------------------------------------
package BulletinBoard;
use strict;
use warnings;
our $AUTOLOAD;
our $_shared_instance;

sub shared {
    if (!defined $_shared_instance) {
	$_shared_instance = BulletinBoard->_new;
    }
    $_shared_instance;
}

sub _new {
    my $class = shift;
    my $obj = {
	table => {},
    };
    bless $obj,$class;
}

sub set {
    my ($this,$key,$value) = @_;
    $this->{table}->{$key} = $value;
    $this;
}

sub get {
    my ($this,$key) = @_;
    $this->{table}->{$key};
}

sub keys {
    keys %{shift->{table}};
}

sub AUTOLOAD {
    # $board->foo_bar => $board->get('foo-bar')
    # $board->foo_bar('foo') => $board->set('foo-bar','foo');
    my ($this,$newvalue) = @_;
    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    $key =~ s/_/-/g;

    if (defined $newvalue) {
	$this->set($key,$newvalue);
    }
    else {
	$this->get($key);
    }
}

1;
