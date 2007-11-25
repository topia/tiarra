# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Mixin::NewIRCMessage;
use strict;
use warnings;
use Tiarra::IRC::Message;

=head1 NAME

Tiarra::Mixin::NewIRCMessage - Tiarra::IRC::Message Construction Interface Mixin
=head1 SYNOPSIS

  package foo::class;
  use base qw(Tiarra::Mixin::NewIRCMessage); # use this
  $this->irc_message_class->foo_class_method;
  $this->construct_irc_message(Command => ...);

=head1 DESCRIPTION

Tiarra::Mixin::NewIRCMessage is define Tiarra::IRC::Message Construction Interface as Mixin.

=head1 METHODS

=over 4

=cut

=item irc_message_class

  __PACKAGE__->irc_message_class; # return Tiarra::IRC::Message
  $this->irc_message_class; # likewise.

return Tiarra::IRC::Message class. you can change class to override this.

=cut

sub irc_message_class () { 'Tiarra::IRC::Message' }

=item construct_irc_message

  __PACKAGE__->construct_irc_message(...);
  $this->construct_irc_message(...); # likewise.

constraction Tiarra::IRC::Message(or specified by ->irc_message_class).

=cut

sub construct_irc_message {
    my $this = shift;

    $this->irc_message_class->new(
	Generator => $this,
	@_);
}

1;

__END__
=back

=head1 SEE ALSO

L<Tiarra::IRC::Message>

=head1 AUTHOR

Topia E<lt>topia@clovery.jpE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Topia.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
