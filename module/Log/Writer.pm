# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Log::Writer;
use strict;
use warnings;
use RunLoop;
use Carp;
use File::Spec;
use DirHandle;
use Tiarra::SharedMixin qw(shared shared_writer);
use Tiarra::WrapMainLoop;
use Tiarra::Utils;
our $_shared_instance;

Tiarra::Utils->define_attr_getter(0, qw(mainloop));
Tiarra::Utils->define_proxy('mainloop', 0,
			    map { ["_mainloop_$_", "lazy_$_"] }
				qw(install uninstall));

# todo:
#  - accept uri(maybe: ssh, syslog, ...)

sub _new {
    my $class = shift;
    my ($this) = {
	objects => {},
	schemes => {},
	protocols => {},
	fallbacks => [],
    };
    bless $this, $class;
    $this->{mainloop} = Tiarra::WrapMainLoop->new(
	type => 'timer',
	interval => 120,
	closure => sub { $this->run; });

    return $this;
}

sub _initialize {
    my $this = shift;
    $this->load_all_protocols;
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
	$this->_mainloop_install;
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
	$object->destruct(1) if $destruct;
    }
}

sub destruct {
    shared_writer->run(1);
    shared_writer->{mainloop} = undef;
}

sub object_release {
    my ($this, $path) = @_;

    delete $this->{objects}->{$path};

    if (!(%{$this->{objects}})) {
	$this->_mainloop_uninstall;
    }
}


# protocol
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
		$this->load_protocol(ref($this).'::'.$1);
	    }
	}
    }
}

sub load_protocol {
    my ($class_or_this, $pkg) = @_;
    my $this = $class_or_this->_this;

    return 1 if $this->{protocols}->{$pkg};
    eval 'use ' . $pkg;
    if ($@) {
	$this->notify_error("load protocol($pkg) error: $@");
	return undef;
    }
    eval 'use Module::Use ($pkg);';
    if ($@) {
	$this->notify_error("regist using protocol($pkg) error: $@");
	return undef;
    }

    foreach my $scheme ($pkg->supported_schemes) {
	push(@{$this->{schemes}->{$scheme}}, $pkg);
    }
    if ($pkg->capability('fallback')) {
	push(@{$this->{fallbacks}}, $pkg);
    }
    $this->{protocols}->{$pkg} = 1;
    return 1;
}

sub unload_protocol {
    my ($class_or_this, $pkg) = @_;
    my $this = $class_or_this->_this;

    return 0 if !$this->{protocols}->{$pkg};
    if ($pkg->capability('fallback')) {
	@{$this->{fallbacks}} = grep $_ ne $pkg, @{$this->{fallbacks}};
    }
    foreach my $scheme ($pkg->supported_schemes) {
	@{$this->{schemes}->{$scheme}} = grep $_ ne $pkg,
	    @{$this->{schemes}->{$scheme}};
    }
    delete $this->{protocols}->{$pkg};
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

1;
