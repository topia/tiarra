# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Log::Writer;
use strict;
use warnings;
use RunLoop;
use Timer;
use Carp;
use File::Spec;
use DirHandle;
our $_shared_instance;

# todo:
#  - accept uri(maybe: ssh, syslog, ...)

*shared = \&shared_writer;
sub shared_writer {
    if (!defined $_shared_instance) {
	$_shared_instance = __PACKAGE__->_new;
	$_shared_instance->load_all_protocols;
    }
    $_shared_instance;
}

sub _this {
    my $class_or_this = shift;

    if (!ref($class_or_this)) {
	# fetch shared_writer
	$class_or_this = $class_or_this->shared_writer;
    }

    $class_or_this;
}

sub _new {
    my $class = shift;
    my ($this) = {
	objects => {},
	schemes => {},
	protocols => [],
	fallbacks => [],
	timer => undef,
    };
    bless $this, $class;

    return $this;
}

sub find_object {
    my ($this, $path, %options) = @_;

    my $object = $this->{objects}->{$path};
    if (defined($object)) {
	# ファイルが存在したので返す。
	return $object;
    } else {
	# ファイルは存在しないので、登録して返す。
	return $this->_register_inner($path, %options);
    }
}

sub register {
    my ($this, $path, %options) = @_;

    my $object = $this->find_object($path, %options);
    if (defined $object) {
	# ファイルを得られた。
	# 参照回数を増やして返す。
	$object->register;
	return $object;
    } else {
	return undef;
    }
}

sub unregister {
    my ($this, $path) = @_;

    my $object = $this->{objects}->{$path};
    if (defined $object) {
	return $object->unregister;
    } else {
	croak('object "' . $path . '" has not registered yet!');
    }
}

sub _register_inner {
    my ($this, $path, %options) = @_;

    my $object;
    my @classes;
    if ($path =~ m|^([^:]+):|) {
	if (defined $this->{schemes}->{$1}) {
	    push(@classes, @{$this->{schemes}->{$1}});
	}
    }
    push(@classes, @{$this->{fallbacks}});
    foreach my $class (@classes) {
	$object = $class->new($this, $path, %options);
	last if defined $object;
    }
    if (defined $object) {
	$this->{objects}->{$path} = $object;
	$this->_install_timer;
	return $object;
    } else {
	return undef;
    }
}

sub run {
    my ($this, $destruct) = @_;

    # do object
    foreach my $key (keys %{$this->{objects}}) {
	my $object = $this->{objects}->{$key};
	$object->flush;
	$object->destruct(1) if ($destruct);
    }
}

sub destruct {
    shared_writer->run(1);
}

sub object_release {
    my ($this, $path) = @_;

    delete $this->{objects}->{$path};

    if (scalar(keys(%{$this->{objects}})) == 0) {
	$this->_uninstall_timer;
    }
}


# protocol
sub register_as_protocol {
    my $class_or_this = shift;
    my $pkg = (caller)[0];
    my $this = $class_or_this->_this;

    foreach my $scheme ($pkg->supported_schemes) {
	push(@{$this->{schemes}->{$scheme}}, $pkg);
    }
}

sub register_as_fallback {
    my $class_or_this = shift;
    my $pkg = (caller)[0];
    my $this = $class_or_this->_this;

    push(@{$this->{fallbacks}}, $pkg);
}

sub load_all_protocols {
    my $class_or_this = shift;
    my $this = $class_or_this->_this;

    my $pkg_dir = File::Spec->catdir(split(/::/, ref($this)));
    foreach (@INC) {
	my $dir = File::Spec->catdir($_, $pkg_dir);
	my $dh = DirHandle->new($dir);
	if (defined $dh) {
	    my $path;
	    foreach my $file ($dh->read) {
		$path = File::Spec->catdir($dir, $file);
		next if !-r $path || -d $path;
		next if $file !~ /^(.+)\.pm$/;
		$this->load_protocol($1);
	    }
	}
    }
}

sub load_protocol {
    my ($class_or_this, $protocol) = @_;
    my $this = $class_or_this->_this;

    my $pkg = ref($this) . '::' . $protocol;
    eval 'use ' . $pkg;
    if ($@) {
	$this->notify_error("load protocol($protocol) error: $@");
	return undef;
    }
    eval 'use Module::Use ($pkg);';
    if ($@) {
	$this->notify_error("regist using protocol($protocol) error: $@");
	return undef;
    }
    push(@{$this->{protocols}}, $protocol);
    return 1;
}

sub unload_protocol {
    my ($class_or_this, $protocol) = shift;
    my $this = $class_or_this->_this;

    @{$this->{protocols}} = grep {
	$_ ne $protocol;
    } @{$this->{protocols}};
    return 1;
}

# util
sub notify_warn {
    my ($this, $str) = @_;

    RunLoop->shared_loop->notify_warn($str);
}

sub notify_error {
    my ($this, $str) = @_;

    RunLoop->shared_loop->notify_error($str);
}

sub notify_msg {
    my ($this, $str) = @_;

    RunLoop->shared_loop->notify_msg($str);
}

# timer
sub _check_timer {
    return defined(shift->{timer});
}

sub _install_timer {
    my $this = shift;

    if (!$this->_check_timer) {
	$this->{timer} = Timer->new(
	    Interval => 120,
	    Repeat => 1,
	    Code => sub {
		my $timer = shift;
		$this->run;
	    },
	   )->install;
    }

    return 0;
}

sub _uninstall_timer {
    my $this = shift;

    if ($this->_check_timer) {
	$this->{timer}->uninstall;
	$this->{timer} = undef;
    }

    return 0;
}

1;
