# -*- cperl -*-
# -----------------------------------------------------------------------------
# Tools::FileCache, Data shared file cache service.
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Tools::FileCache;
use strict;
use warnings;
use RunLoop;
use Carp;
use Tiarra::SharedMixin;
use Module::Use qw(Tools::FileCache::EachFile);
use Tools::FileCache::EachFile;
our $_shared_instance;

sub _new {
    my $class = shift;
    my ($this) = {
	files => {},

	timer => undef,
    };
    bless $this, $class;

    return $this;
}

sub find_file {
    my ($class_or_this, $fpath, $mode, $charset) = @_;
    my $this = $class_or_this->_this;

    my $file = $this->{files}->{$fpath};
    if (defined($file)) {
	# とりあえずファイルは存在した。
	my $obj = $file->{$mode};
	if (defined($obj)) {
	    # そのモードも存在した。オブジェクトを返す。
	    return $obj;
	} else {
	    # そのモードは存在しなかった。登録して返す。
	    return $this->_register_inner($fpath, $mode, $charset);
	}
    } else {
	# ファイルは存在しない。登録して返す。
	return $this->_register_inner($fpath, $mode, $charset);
    }
}

sub register {
    my ($class_or_this, $fpath, $mode, $charset) = @_;
    my $this = $class_or_this->_this;

    my $file = $this->find_file($fpath, $mode, $charset);
    if (defined $file) {
	# ファイルがあった or ファイルを登録した。
	# 参照回数を増やして返す。
	$file->register();
	return $file;
    } else {
	# ファイルの登録が出来なかった。
	return undef;
    }
}

sub unregister {
    my ($class_or_this, $fpath) = @_;
    my $this = $class_or_this->_this;

    my $file = $this->{files}->{$fpath};
    if (defined($file)) {
	$file->unregister();
	return 0;
    } else {
	croak('file "' . $fpath . '" has not registered yet!');
    }
}

sub _register_inner {
    my ($class_or_this, $fpath, $mode, $charset) = @_;
    my $this = $class_or_this->_this;

    my $obj = Tools::FileCache::EachFile->new($this, $fpath, $mode, $charset);
    if (defined $obj) {
	$this->{files}->{$fpath} = {} unless (defined($this->{files}->{$fpath}));
	$this->{files}->{$fpath}->{$mode} = $obj;
	$this->_install_timer();
	return $obj;
    } else {
	return undef;
    }
}

sub main_loop {
    my $this = shift;

    # check expire
    foreach my $key (keys(%{$this->{files}})) {
	my $file = $this->{files}->{$key};
	foreach my $mode (keys(%$file)) {
	    my $obj = $file->{$mode};
	    if ($obj->can_remove() && ($obj->expire() < time())) {
		# expired.
		$obj->clean();
		delete $this->{files}->{$key}->{$mode};
	    }
	}
	if (scalar(keys(%$file)) == 0) {
	    delete $this->{files}->{$key};
	}
    }

    # check struct-size
    if (scalar(keys(%{$this->{files}})) == 0) {
	$this->_uninstall_timer();
    }
}

sub destruct {
    my $this = shared;

    # expire all
    foreach my $key (keys(%{$this->{files}})) {
	my $file = $this->{files}->{$key};
	foreach my $mode (keys(%$file)) {
	    my $obj = $file->{$mode};
	    $obj->clean();
	    delete $this->{files}->{$key}->{$mode};
	}
	delete $this->{files}->{$key};
    }

    # re-run main_loop (for uninstall timer)
    $this->main_loop();
}

# misc/timer
sub _check_timer {
    my $this = shift;

    return defined($this->{timer});
}

sub _install_timer {
    my $this = shift;

    unless ($this->_check_timer) {
	$this->{timer} = Timer->new(
	    Interval => 30,
	    Repeat => 1,
	    Code => sub {
		my $timer = shift;
		$this->main_loop();
	    },
	   )->install();
    }

    return 0;
}

sub _uninstall_timer {
    my $this = shift;

    if ($this->_check_timer()) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }

    return 0;
}

1;
