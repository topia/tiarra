# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# Misc Utilities
# -----------------------------------------------------------------------------
# copyright (C) 2004 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::Utils;
use strict;
use warnings;
use Carp;
use List::Util qw(first);
use base qw(Tiarra::Utils::Core);
use base qw(Tiarra::Utils::DefineHelper);
use base qw(Tiarra::Utils::CallWrapper);
use base qw(Exporter);
our @EXPORT = qw(utils);

=head1 NAME

Tiarra::Utils - Tiarra misc Utility Functions

=head1 SYNOPSIS

  use Tiarra::Utils; # import utils
  utils->get_first_defined(..., ...);

=head1 DESCRIPTION

misc helper functions.

this class inherited some classes'(L<Tiarra::Utils::Core>,
L<Tiarra::Utils::DefineHelper>, L<Tiarra::Utils::CallWrapper>) methods.
so please refer these classes' documents.

=head1 METHODS

=over 4

=cut

=item utils

  utils->foo_method;

default export function for shorthand use of Tiarra::Utils functions.

=cut

sub utils {
    __PACKAGE__->shared;
}

=item simple_caller_formatter

  utils->simple_caller_formatter([$msg[, $caller_level]]);

format "<msg> at <file> line <line>" style caller information.

args:

=over 4

=item * $msg

subject of caller information. default is 'called'.

=item * $caller_level

caller level to dig. default is 0(caller of your function).

=back

=cut

sub simple_caller_formatter {
    my $pkg = shift;
    my $msg = $pkg->get_first_defined(shift, 'called');
    my $caller_level = shift || 0;

    sprintf('%s at %s line %s', $msg,
	    ($pkg->get_caller($caller_level + 1))[1,2]);
}

=item cond_yesno

  utils->cond_yesno($value[, $default]);

check yes-or-no style condition.

return true on yes(or 1, true, and so on),
false on no(or 0, false, and so on).

if $value is undefined, return $default.

=cut

sub cond_yesno {
    shift; # drop
    my ($value, $default) = @_;

    return $default unless defined $value;
    return 0 if $value =~ /[fn]/i; # false/no
    return 1 if $value =~ /[ty]/i; # true/yes
    return 1 if $value; # ¿ôÃÍÈ½Äê
    return 0;
}

=item to_str

  utils->to_str(@strings);

stringify without undefined warning.

=cut

sub to_str {
    shift; # drop
    # undef(and so on) to str without warning
    no warnings 'uninitialized';
    grep {
	if (!wantarray) {
	    return $_;
	} else {
	    1;
	}
    } map {
	"$_"
    } @_;
}

=item get_first_defined

  utils->get_first_defined(@values);

(deprecated): return first defined value.

this function is deprecated; please use
C<< List::Util::first { defined } @values >> instead.

=cut

sub get_first_defined {
    shift; # drop
    first { defined } @_;
}

=item to_ordinal_number

  utils->to_ordinal_number($int);

format number to ordinal number.

=cut

sub to_ordinal_number {
    shift; # drop
    grep {
	if (!wantarray) {
	    return $_;
	} else {
	    1;
	}
    } map {
	if (/1$/) {
	    $_ . 'st';
	} elsif (/(?:[^1]|^)([23])$/) {
	    $_ . ($2 eq '2' ? 'nd' : 'rd');
	} else {
	    $_ . 'th';
	}
    } @_;
}

1;

__END__
=back

=head1 SEE ALSO

L<Tiarra::Utils::Core>,
L<Tiarra::Utils::DefineHelper>,
L<Tiarra::Utils::CallWrapper>

=head1 AUTHOR

Topia E<lt>topia@clovery.jpE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Topia.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
