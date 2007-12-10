# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# モジュール間の情報伝達に使われるクラス。
# インスタンスは共有される。
# -----------------------------------------------------------------------------
package BulletinBoard;
use strict;
use warnings;
our $AUTOLOAD;
use Tiarra::SharedMixin;
our $_shared_instance;

sub _new {
    my $class = shift;
    my $obj = {
	table => {},
    };
    bless $obj,$class;
}

sub set {
    my ($class_or_this,$key,$value) = @_;
    my $this = $class_or_this->_this;
    $this->{table}->{$key} = $value;
    $this;
}

sub get {
    my ($class_or_this,$key) = @_;
    my $this = $class_or_this->_this;
    $this->{table}->{$key};
}

sub keys {
    keys %{shift->_this->{table}};
}

sub AUTOLOAD {
    # $board->foo_bar => $board->get('foo-bar')
    # $board->foo_bar('foo') => $board->set('foo-bar','foo');
    my ($class_or_this,$newvalue) = @_;
    my $this = $class_or_this->_this;
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
