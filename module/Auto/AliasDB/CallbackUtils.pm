# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# copyright (C) 2003 Topia <topia@clovery.jp>. all rights reserved.

package Auto::AliasDB::CallbackUtils;
use Auto::AliasDB;
use strict;
use warnings;
use Carp;
use RunLoop;
use Multicast;
use Tiarra::SharedMixin;
our $_shared_instance;

sub _new {
    my ($class) = @_;
    my $obj = {
	loaded_modules => {},
    };
    bless $obj,$class;
}

sub _getmodule {
    my ($this, $modulename) = @_;

    return $this->shared->{loaded_modules}->{$modulename};
}

sub _loadmodule {
    my ($this, $modulename, $need_module_use) = @_;
    my ($module) = $this->_getmodule($modulename);
    if (defined $module) {
	# module already 'tryed' load.
    } else {
	if ($need_module_use) {
	    eval "use Module::Use ('$modulename')";
	}
	eval 'use ' . $modulename;
	unless ($@) {
	    $module = $this->shared->{loaded_modules}->{$modulename} = 1;

	    return $module;
	} else {
	    $module = $this->shared->{loaded_modules}->{$modulename} = 0;
	}
	carp "can't load $modulename" if $module != 1;
    }
    return $module;
}

sub register_callback {
    my ($reg_callback, $callbacks) = @_;

    my ($callback_code) = sub {
	if (ref($reg_callback) eq 'CODE') {
	    # code reference
	    return $reg_callback;
	} elsif (!ref($reg_callback)) {
	    # scalar
	    my $code = eval('\&' . $reg_callback);
	    return $code unless ($@);
	    carp($reg_callback . ' is scalar, but function not defined.');
	    return undef;
	} else {
	    carp($reg_callback . ' is not code_reference or scalar.');
	    return undef;
	}
    }->();

    return $callbacks unless defined($callback_code);

    foreach my $callback (@$callbacks) {
	return $callbacks if $callback == $callback_code;
    }
    push(@$callbacks, $callback_code);
    return $callbacks;
}

sub register_stdcallbacks {
    my ($callbacks, $msg, $sender) = @_;

    register_callback(\&DateConvert, $callbacks);
    register_callback(\&RandomConvert, $callbacks);
    register_callback(\&RandomSelectConvert, $callbacks);
    register_callback(\&RandomAliasConvert, $callbacks);
    register_callback(\&JoinedListConvert, $callbacks);
    if (defined $msg) {
	if (defined $sender) {
	    register_RandomNickConvert($callbacks, $msg->param(0), $sender);
	}
	register_MessageReplace($callbacks, $msg->param(1));
    }

    return $callbacks;
}

sub DateConvert {
    my ($key) = @_;
    my ($tag, $value) = split(/\:/, $key, 2);

    return undef unless ($tag eq 'date');
    return undef unless (Auto::AliasDB::CallbackUtils->shared->_loadmodule('Tools::DateConvert', 1));
    return Tools::DateConvert::replace($value);
}

sub RandomConvert {
    my ($key) = @_;
    my ($tag, $value) = split(/\:/, $key, 2);

    return undef unless defined($tag) and defined ($value);
    return undef unless ($tag eq 'random');
    return undef unless ($value =~ /^(\d+)-(\d+)$/);
    return (int(rand($2 - $1 + 1)) + $1);
}

sub RandomSelectConvert {
    my ($key) = @_;
    my ($tag, @values) = split(/\:/, $key);

    return undef unless ($tag eq 'randomselect');
    return @values[int(rand(scalar(@values)))];
}

sub RandomAliasConvert {
    my ($key, $hashtables) = @_;
    my ($tag, $name) = split(/\:/, $key, 2);

    return undef unless ($tag eq 'randomalias');
    return undef unless defined($name);
    # search hashtable
    foreach my $table (@$hashtables) {
	my $value = Auto::AliasDB::get_value_random($table, $name);
	return $value if defined($value);
    }
}

sub JoinedListConvert {
    my ($key, $hashtables) = @_;
    my ($tag, $name, $sep) = split(/\:/, $key, 3);

    return undef unless ($tag eq 'joined_list');
    return undef unless defined($name) && defined($sep);
    # search hashtable
    foreach my $table (@$hashtables) {
	my @values = @{Auto::AliasDB::get_array($table, $name)};
	if (@values) {
	    # È¯¸«
	    return join($sep, @values);
	}
    }
    return undef;
}


sub RandomNickConvert {
    my ($ch, $key) = @_;
    my $idx;

    return undef unless ($key eq 'randomnick');
    $idx = int(rand($ch->names(undef, undef, 'size')));
    return $ch->names((keys(%{$ch->names()}))[$idx])->person->nick;
}

sub register_RandomNickConvert {
    # using:
    #   Auto::AliasDB::CallbackUtils::register_RandomNickConvert($callbacks, $ch_name, $sender);
    my ($callbacks, $ch_name, $sender) = @_;
    return $callbacks unless $sender->isa('IrcIO::Server');
    my $ch = $sender->channel(Multicast::detatch($ch_name));

    return $callbacks unless defined $ch;
    register_callback(
	sub {
	    return RandomNickConvert($ch, @_);
	}, $callbacks);

    return $callbacks;
}

sub MessageReplace {
    my ($message, $key) = @_;
    my ($tag, $split_char, $place) = split(/\:/, $key, 3);
    my ($offsetlen);

    if ($tag eq 'message_replace') {
	$offsetlen = 2;
    } elsif ($tag eq 'message_replace_last') {
	$offsetlen = 1;
    } else {
	return undef;
    }
    return undef unless (defined $split_char) && (defined $place);
    return (split($split_char, $message, $place + $offsetlen))[$place];
}

sub register_MessageReplace {
    # using:
    #   Auto::AliasDB::CallbackUtils::register_MessageReplace($callbacks, $message);
    my ($callbacks, $message) = @_;

    return $callbacks unless defined $message;
    register_callback(
	sub {
	    MessageReplace($message, @_);
	}, $callbacks);

    return $callbacks;
}

# --- not secure ---

sub register_extcallbacks {
    my ($callbacks, $msg, $sender) = @_;

    Auto::AliasDB::CallbackUtils::register_Nick_setMode($callbacks, $msg, $sender);
    Auto::AliasDB::CallbackUtils::register_callback(\&ReadFileConvert, $callbacks);
    Auto::AliasDB::CallbackUtils::register_callback(\&FileLinesConvert, $callbacks);

    return $callbacks;
}

sub ReadFileConvert {
    my ($key) = @_;
    my ($tag, $fpath, $mode, $charset) = split(/\:/, $key, 4);

    return undef unless $tag eq 'read_file';
    return undef unless (Auto::AliasDB::CallbackUtils->shared->_loadmodule('Tools::FileCache', 1));
    $mode = 'std' if (!defined($mode));
    my $file = Tools::FileCache->shared->find_file($fpath, $mode, $charset);
    return undef unless defined($file);
    return $file->get_value();
}

sub FileLinesConvert {
    my ($key) = @_;
    my ($tag, $fpath, $mode, $charset) = split(/\:/, $key, 4);

    return undef unless $tag eq 'file_lines';
    return undef unless (Auto::AliasDB::CallbackUtils->shared->_loadmodule('Tools::FileCache', 1));
    $mode = 'std' if (!defined($mode));
    my $file = Tools::FileCache->shared->find_file($fpath, $mode, $charset);
    return undef unless defined($file);
    return $file->length();
}

sub Nick_setMode {
    my ($irc_message, $sender, $key) = @_;
    my ($tag, $value) = split(/\:/, $key, 2);

    return undef unless ($tag eq 'set_chmode');
    return undef unless ($value =~ /^[+-][vo]$/);
    return '' unless ($sender->isa('IrcIO::Server'));
    $irc_message->param(1, $value);
    Timer->new(
	After => 0,
	Repeat => 0,
	Code => sub {
	    my $timer = shift;
	    $sender->send_message($irc_message);
	})->install;
    return '';
}

sub register_Nick_setMode {
    # using:
    #   Auto::AliasDB::CallbackUtils::register_Nick_setMode($callbacks, $msg, $sender);
    my ($callbacks, $msg, $sender) = @_;
    my ($ch_name) = $msg->param(0);
    return $callbacks if (Multicast::nick_p($ch_name)); #priv
    $ch_name = scalar(Multicast::detatch($ch_name));
    my $irc_message = IRCMessage->new(
	Command => 'MODE',
	Params => [$ch_name,
		   '',		#set later
		   $msg->nick]);

    register_callback(
	sub {
	    Nick_setMode($irc_message, $sender, @_);
	}, $callbacks);

    return $callbacks;
}


1;
