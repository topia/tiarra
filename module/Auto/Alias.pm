# -----------------------------------------------------------------------------
# $Id: Alias.pm,v 1.8 2003/07/31 07:34:13 topia Exp $
# -----------------------------------------------------------------------------
# $Clovery: tiarra/module/Auto/Alias.pm,v 1.13 2003/07/27 07:17:07 topia Exp $
package Auto::Alias;
use strict;
use warnings;
use base qw(Module);
use Module::Use qw(Auto::AliasDB Auto::Utils);
use Auto::AliasDB;
use Auto::Utils;
use Mask;

sub new {
  my $class = shift;
  my $this = $class->SUPER::new;
  Auto::AliasDB::setfile($this->config->alias,
			 $this->config->alias_encoding);
  $this;
}

sub message_arrived {
  my ($this,$msg,$sender) = @_;
  my @result = ($msg);

  if ($msg->command eq 'PRIVMSG') {

    if (Mask::match($this->config->confirm,$msg->param(1))) {
      # その人のエイリアスがあればprivで返す。
      my (undef,undef,$reply_as_priv,undef,undef)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result, 0); # Alias conversion disable.

      my $alias = Auto::AliasDB->shared->find_alias_prefix($msg->prefix);
      if (defined $alias) {
	while (my ($key,$values) = each %$alias) {
	  map {
	    $reply_as_priv->("$key: $_");
	  } @$values;
	}
      }
    }
    else {
      my (undef,undef,undef,$reply_anywhere,undef)
	= Auto::Utils::generate_reply_closures($msg,$sender,\@result, 1);

      my $msg_from_modifier_p = sub {
	  !defined $msg->prefix ||
	      Mask::match_deep([Mask::array_or_all($this->config->modifier('all'))],
			       $msg->prefix);
      };

      my ($temp) = $msg->param(1);
      $temp =~ s/^\s*(.+)\s*$/$1/;
      my ($keyword,$key,$value)
	= split(/\s+/, $temp, 3);

      if(Mask::match($this->config->get('add'),$keyword)) {
	if ($msg_from_modifier_p->() && defined $key && defined $value) {
	  if (Auto::AliasDB->shared->add_value_with_prefix($msg->prefix, $key, $value)) {
	    if (defined $this->config->added_format && $this->config->added_format ne '') {
	      $reply_anywhere->($this->config->added_format, 'key' => $key, 'value' => $value);
	    }
	  }
	}
      }
      elsif (Mask::match($this->config->get('remove'),$keyword)) {
	if ($msg_from_modifier_p->() && defined $key) {
	  my $count = Auto::AliasDB->shared->del_value_with_prefix($msg->prefix, $key, $value);
	  if ($count) {
	    if (defined $this->config->removed_format && $this->config->removed_format ne '') {
	      $reply_anywhere->($this->config->removed_format, 'key' => $key, 'value' => $value, 'count' => $count);
	    }
	  }
	}
      }
    }
  }
  return @result;
}

1;
