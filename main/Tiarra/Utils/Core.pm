# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Tiarra::Utils Core feature
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils::Core;
use strict;
use warnings;

=head1 NAME

Tiarra::Utils::Core - Tiarra misc Utility Functions: Core

=head1 SYNOPSIS

  use Tiarra::Utils; # import master

=head1 DESCRIPTION

Tiarra::Utils is misc helper functions class. this class is implement core.

class splitting is maintainer issue only. please require/use Tiarra::Utils.

=head1 METHODS

=over 4

=cut

=item _this

  foopkg->_this

return shared object(singleton) if ->shared method defined and called as class method.
otherwise(called as object method, or non-singleton class) return $this self.

=cut

sub _this {
    my $class_or_this = shift;

    if (!ref($class_or_this)) {
	if ($class_or_this->can('shared')) {
	    # fetch shared
	    $class_or_this = $class_or_this->shared;
	}
    }

    return $class_or_this;
}

1;

__END__
=back

=head1 SEE ALSO

L<Tiarra::Utils>

=head1 AUTHOR

Topia E<lt>topia@clovery.jpE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Topia.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
