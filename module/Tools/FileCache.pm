# -*- cperl -*-
# Tools::FileCache, Data shared file cache service.
# $Id: FileCache.pm,v 1.3 2003/09/25 13:16:00 topia Exp $
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.
package Tools::FileCache;
use strict;
use warnings;
use RunLoop;
use Module::Use qw(Tools::FileCache::EachFile);
use Tools::FileCache::EachFile;
our $_shared;

sub shared {
    if (!defined $_shared) {
	$_shared = Tools::FileCache->_new;
    }

    return $_shared;
}

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
    my ($this, $fpath, $mode, $charset) = @_;

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
    my ($this, $fpath, $mode, $charset) = @_;

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
    my ($this, $fpath) = @_;

    my $file = $this->{files}->{$fpath};
    if (defined($file)) {
	$file->unregister();
	return 0;
    } else {
	croak('file "' . $fpath . '" has not registered yet!');
    }
}

sub _register_inner {
    my ($this, $fpath, $mode, $charset) = @_;

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
    my $this = shared();

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
