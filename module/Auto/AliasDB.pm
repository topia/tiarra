# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# エイリアスファイルの読み込みと生成、#(name|nick)といった文字列の置換を行なうクラス。
# Tiarraモジュールではない。
# このクラスは共通のインスタンスを一つだけ持つ。
# -----------------------------------------------------------------------------
package Auto::AliasDB;
use strict;
use warnings;
use IO::File;
use File::stat;
use Unicode::Japanese;
use Module::Use qw(Auto::AliasDB::CallbackUtils Tools::GroupDB);
use Auto::AliasDB::CallbackUtils;
use Tools::GroupDB;
use Mask;
use Configuration;
use Configuration::Block;
use Tiarra::SharedMixin;
our $_shared_instance;

sub setfile {
    # クラスメソッド。
    my ($fpath,$charset) = @_;
    $_shared_instance = Auto::AliasDB->_new($fpath,$charset);
}

sub _new {
    # fpathを省略するか空の文字列を指定すると、空のAliasDBが作られます。
    my ($class,$fpath,$charset) = @_;
    my $obj = {
	database => Tools::GroupDB->new($fpath, 'user', $charset || undef, 0),
	config => Configuration::shared_conf->get('Auto::AliasDB')
	    || Configuration::Block->new('Auto::AliadDB'), 
    };
    bless $obj,$class;
}

sub config {
    my ($this) = @_;

    return $this->{config};
}

sub find_alias_prefix {
    # userinfoはnick!user@hostの形式。
    # 見付からなければundefを返す。
    # flagに付いてはfind_alias参照。
    my ($this, $userinfo, $flag) = @_;

    return $this->find_alias(['user'], \$userinfo, $flag);
}

sub find_alias {
    # on not found return 'undef'
    # $keys is ref[array or scalar]
    # $values is ref[array or scalar]
    # $flag is public_alias flag. true is 'public', default false.
    my ($this, $keys, $values, $flag) = @_;

    $flag = 0 unless defined($flag);

    my $person = $this->{database}->find_group($keys, $values);

    if (defined($person)) {
	if ($flag) {
	    # public. remove private alias.
	    return $this->remove_private(dup_struct($person));
	} else {
	    # not public
	    return $person;
	}
    }

    return undef;
}

sub add_alias {
    my ($this,$alias) = @_;

    return $this->{database}->add_group($alias);
}

sub add_value {
    my ($this, $alias, $key, $value) = @_;

    return $this->{database}->add_value($alias, $key, $value);
}

sub add_value_with_prefix {
    my ($this, $prefix, $key, $value) = @_;

    return $this->{database}->add_value_with_primary($prefix, $key, $value);
}

sub del_value {
    my ($this, $alias, $key, $value) = @_;

    return $this->{database}->del_value($alias, $key, $value);
}

sub del_value_with_prefix {
    my ($this, $prefix, $key, $value) = @_;

    return $this->{database}->del_value_with_primary($prefix, $key, $value);
}

# alias misc functions
sub find_alias_with_stdreplace {
    my ($this, $nick, $name, $host, $prefix, $flag) = @_;

    return add_stdreplace(dup_struct($this->find_alias_prefix($prefix, $flag)),
			  $nick, $name, $host, $prefix);
}

sub add_stdreplace {
    my ($alias, $nick, $name, $host, $prefix) = @_;

    $alias = {} unless defined($alias);

    $alias->{'nick.now'} = $nick;
    $alias->{'user.now'} = $name;
    $alias->{'host.now'} = $host;
    $alias->{'prefix.now'} = $prefix;

    return $alias;
}

sub remove_private {
    my ($this, $alias, $prefix, $suffix) = @_;

    $prefix = '' unless defined($prefix);
    $suffix = '' unless defined($suffix);

    foreach my $remove_key ($this->config->private('all')) {
	delete $alias->{$prefix . $remove_key . $suffix};
    }

    return $alias;
}

sub check_readonly {
    my ($this, $keys) = @_;

    foreach my $check_key ($this->config->readonly('all')) {
	@$keys = grep {
	    $_ ne $check_key;
	} @$keys;
    }

    return $keys;
}

sub dup_struct {
    my ($alias) = @_;
    my ($new_alias) = {};

    return undef unless defined($alias);

    map {
	$new_alias->{$_} = $alias->{$_};
    } keys(%$alias);

    return $new_alias;
}

sub concat_string_to_key {
    return Tools::GroupDB::concat_string_to_key(@_);
}

sub get_value_random {
    return Tools::GroupDB::get_value_random(@_);
}

sub get_value {
    my ($alias, $key) = @_;

    my $values = get_array($alias, $key);
    if ($values) {
	# 発見.
	return $values->[0];
    }
    return undef;
}

sub get_array {
    my ($alias, $key) = @_;

    my $value = $alias->{$key};
    if (defined $value) {
	# 発見
	if (ref($value) eq 'ARRAY') {
	    return $value;
	}
	else {
	    return [$value];
	}
	last;
    }
    return ();
}

# replace support functions
sub replace {
    # エイリアスマクロの置換を行なう。%optionalは置換に追加するキーと値の組みで、省略可。
    # optionalの値はSCALARでもARRAY<SCALAR>でも良い。
    # userinfoはnick!user@hostの形式。
    my ($this,$userinfo,$str,%optional) = @_;
    $this->replace_with_callbacks($userinfo,$str,undef,%optional);
}

sub stdreplace {
    my ($this, $userinfo, $str, $msg, $sender, %optional) = @_;
    my (@callbacks);

    return $this->stdreplace_add($userinfo, $str, \@callbacks, $msg, $sender, %optional);
}

sub stdreplace_add {
    my ($this, $userinfo, $str, $callbacks, $msg, $sender, %optional) = @_;

    Auto::AliasDB::CallbackUtils::register_stdcallbacks($callbacks, $msg, $sender);
    my ($add_alias) = add_stdreplace(
	undef,
	$msg->nick || RunLoop->shared->current_nick,
	$msg->name,
	$msg->host,
	$msg->prefix);

    return $this->replace_with_callbacks($userinfo, $str, $callbacks, %optional, %$add_alias);
}

sub replace_with_callbacks {
    # エイリアスマクロの置換を行なう。%optionalは置換に追加するキーと値の組みで、省略可。
    # $callbacksはalias/optionalで置換できなかった際に呼び出されるコールバック関数のリファレンス。
    # optionalの値はSCALARでもARRAY<SCALAR>でも良い。
    # userinfoはnick!user@hostの形式。
    my ($this,$userinfo,$str,$callbacks,%optional) = @_;
    return $this->{database}->replace_with_callbacks($userinfo, $str, $callbacks, %optional);
}

1;
