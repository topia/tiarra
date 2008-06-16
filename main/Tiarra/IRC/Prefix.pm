# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2005 Topia <topia@clovery.jp>. all rights reserved.
package Tiarra::IRC::Prefix;
use strict;
use warnings;
use enum qw(PREFIX NICK NAME HOST);
use Tiarra::Utils;
use overload
    '""' => sub { shift->prefix };

=head1 NAME

Tiarra::IRC::Prefix - Tiarra IRC Prefix class

=head1 SYNOPSIS

  use Tiarra::IRC::Prefix;
  my $prefix = Tiarra::IRC::Prefix->new(Prefix => 'foo!~bar@baz')
  $prefix = Tiarra::IRC::Prefix->new(Nick => 'foo',
				     Name => '~bar',
				     Host => 'baz');
  if ($prefix eq 'foo!~bar@baz') { # stringify
      # ...
  }

=head1 DESCRIPTION

Tiarra IRC Prefix class.

=head1 CONSTRUCTOR

=over 4

=cut

=item new

  # parse
  my $prefix = Tiarra::IRC::Prefix->new(Prefix => 'foo!~bar@baz')
  # construct
  $prefix = Tiarra::IRC::Prefix->new(Nick => 'foo',
				     Name => '~bar',
				     Host => 'baz');

Construct IRC Prefix from string or parts.

=over 4

=item * Construct with parsing

=over 4

=item * Prefix

prefix to parse.

=back

=item * Construct with parts

=over 4

=item * Nick

Nickname or Server FQDN.

=item * Name or User

Username.

=item * Host

Hostname.

=back

=back

=cut

sub new {
    my ($class,%args) = @_;
    my $obj = bless [] => $class;
    $obj->[PREFIX] = undef;
    $obj->[NICK] = undef;
    $obj->[NAME] = undef;
    $obj->[HOST] = undef;

    foreach (qw(Prefix Nick User Name Host)) {
	if (exists $args{$_}) {
	    my $method = lc($_);
	    $obj->$method($args{$_});
	}
    }
    $obj;
}


=back

=head1 METHODS

=over 4

=item nick

accessor for nick.

=item name or user

accessor for name.

=item host

accessor for host.

=item prefix

accessor for prefix.

=cut

utils->define_array_attr_notify_accessor(
    0, '$this->_update_prefix', qw(nick name host));
utils->define_array_attr_notify_accessor(
    0, '$this->_parse_prefix', qw(prefix));

*user = \&name;

=item clone

  # deep clone
  $deep_clone = $prefix->clone(deep => 1);
  # shallow clone
  $shallow_clone = $prefix->clone;

Clone prefix.

same behavior eithor deep or shallow clone for this class.

=cut

sub clone {
    my ($this, %args) = @_;
    if ($args{deep}) {
	require Data::Dumper;
	eval(Data::Dumper->new([$this])->Terse(1)
		->Deepcopy(1)->Purity(1)->Dump);
    } else {
	my @new = @$this;
	bless \@new => ref($this);
    }
}

sub _parse_prefix {
    my $this = shift;
    delete $this->[NICK];
    delete $this->[NAME];
    delete $this->[HOST];
    if (defined $this->[PREFIX]) {
	if ($this->[PREFIX] !~ /@/) {
	    $this->[NICK] = $this->[PREFIX];
	} elsif ($this->[PREFIX] =~ m/^(.+?)!(.+?)@(.+)$/) {
	    $this->[NICK] = $1;
	    $this->[NAME] = $2;
	    $this->[HOST] = $3;
	} elsif ($this->[PREFIX] =~ m/^(.+?)@(.+)$/) {
	    $this->[NICK] = $1;
	    $this->[HOST] = $2;
	}
    } else {
	delete $this->[PREFIX];
    }
}

sub _update_prefix {
    my $this = shift;
    if (defined $this->[NICK]) {
	$this->[PREFIX] = $this->[NICK];
	if (defined $this->[HOST]) {
	    if (defined $this->[NAME]) {
		$this->[PREFIX] .= '!'.$this->[NAME];
		$this->[PREFIX] .= '@'.$this->[HOST];
	    } else {
		$this->[PREFIX] .= '@'.$this->[HOST];
		delete $this->[NAME];
	    }
	} else {
	    delete $this->[NAME];
	    delete $this->[HOST];
	}
    } else {
	delete $this->[NICK];
	delete $this->[NAME];
	delete $this->[HOST];
    }
}

1;

__END__
=back

=head1 SEE ALSO

L<Tiarra::IRC::Message>

=head1 AUTHOR

originally developed by phonohawk E<lt>phonohawk@ps.sakura.ne.jpE<gt>
and Topia E<lt>topia@clovery.jpE<gt>.

now maintained by Tiarra Development Team.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut
