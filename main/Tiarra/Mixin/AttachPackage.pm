# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Mixin::AttachPackage;
use strict;
use warnings;

=head1 NAME

Tiarra::Mixin::AttachPackage - generate package-attached name.

=head1 SYNOPSIS

  package SomePackage;
  use base qw(Tiarra::Mixin::AttachPackage); # define
  __PACKAGE__->attach_package("foo");  # SomePackage/foo
  $this->attach_package("bar", "baz"); # SomePackage/bar/baz

=head1 DESCRIPTION

generate package attached name.

=head1 METHODS

=over 4

=cut

=item attach_package

  __PACKAGE__->attach_package("foo", "bar", "baz");
  $this->attach_package("foo", "bar", "baz");

generate package attached name.

=cut

sub attach_package {
    my $this = shift;
    if (ref($this)) {
	# fetch package name
	$this = ref($this);
    }
    join('/', $this, @_);
}

1;

__END__
=back

=head1 AUTHOR

Topia E<lt>topia@clovery.jpE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Topia.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
