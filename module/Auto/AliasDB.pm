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
use Module::Use qw(Auto::AliasDB::CallbackUtils Tools::GroupDB);
use Auto::AliasDB::CallbackUtils;
use Tools::GroupDB;
use Mask;
use Configuration;
use Configuration::Block;
use Tiarra::SharedMixin;
use Tiarra::Utils;
our $_shared_instance;

Tiarra::Utils->define_attr_getter(1, qw(database config));
Tiarra::Utils->define_proxy('database', 1,
			    [qw(add_alias add_group)],
			    map { [$_.'_prefix', $_.'_primary'] }
				qw(add_value_with del_value_with));

sub setfile {
    # クラス関数。
    my ($fpath,$charset) = @_;
    # re-initialize
    __PACKAGE__->_shared_init($fpath,$charset);
}

sub _new {
    # fpathを省略するか空の文字列を指定すると、空のAliasDBが作られます。
    my ($class,$fpath,$charset) = @_;
    my $obj = {
	database => Tools::GroupDB->new($fpath, 'user', $charset || undef, 0),
	config => Configuration::shared_conf->get(__PACKAGE__)
	    || Configuration::Block->new(__PACKAGE__),
    };
    bless $obj,$class;
}

sub find_alias_prefix {
    # userinfoはnick!user@hostの形式。
    # 見付からなければundefを返す。
    # flagに付いてはfind_alias参照。
    my ($class_or_this, $userinfo, $flag) = @_;
    my $this = $class_or_this->_this;

    return $this->find_alias('user', $userinfo, $flag);
}

sub find_alias {
    # on not found return 'undef'
    # $keys is ref[array or scalar]
    # $values is ref[array or scalar]
    # $flag is public_alias flag. true is 'public', default false.
    my ($class_or_this, $keys, $values, $flag) = @_;
    my $this = $class_or_this->_this;

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

sub add_value {
    my ($class_or_this, $alias, $key, $value) = @_;

    return $alias->add_value($key, $value);
}

sub del_value {
    my ($class_or_this, $alias, $key, $value) = @_;

    return $alias->del_value($key, $value);
}

# alias misc functions
sub find_alias_with_stdreplace {
    my ($class_or_this, $nick, $name, $host, $prefix, $flag) = @_;
    my $this = $class_or_this->_this;

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
    my ($class_or_this, $alias, $prefix, $suffix) = @_;
    my $this = $class_or_this->_this;

    $prefix = '' unless defined($prefix);
    $suffix = '' unless defined($suffix);

    foreach my $remove_key ($this->config->private('all')) {
	delete $alias->{$prefix . $remove_key . $suffix};
    }

    return $alias;
}

sub check_readonly {
    my ($class_or_this, $keys) = @_;
    my $this = $class_or_this->_this;

    foreach my $check_key ($this->config->readonly('all')) {
	@$keys = grep {
	    $_ ne $check_key;
	} @$keys;
    }

    return $keys;
}

sub dup_struct {
    my ($alias) = @_;

    return undef unless defined($alias);
    return $alias->clone;
}

sub concat_string_to_key {
    return Tools::GroupDB::concat_string_to_key(@_);
}

# first param should be Tool::Hash.
sub get_value_random { shift->get_value_random(@_); }
sub get_value { shift->get_value(@_) }
sub get_array { shift->get_array(@_) }

# replace support functions
sub replace {
    # エイリアスマクロの置換を行なう。%optionalは置換に追加するキーと値の組みで、省略可。
    # optionalの値はSCALARでもARRAY<SCALAR>でも良い。
    # userinfoはnick!user@hostの形式。
    my ($class_or_this,$userinfo,$str,%optional) = @_;
    my $this = $class_or_this->_this;
    $this->replace_with_callbacks($userinfo,$str,undef,%optional);
}

sub stdreplace {
    my ($class_or_this, $userinfo, $str, $msg, $sender, %optional) = @_;
    my $this = $class_or_this->_this;
    my (@callbacks);

    return $this->stdreplace_add($userinfo, $str, \@callbacks, $msg, $sender, %optional);
}

sub stdreplace_add {
    my ($class_or_this, $userinfo, $str, $callbacks, $msg, $sender, %optional) = @_;
    my $this = $class_or_this->_this;

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
    my ($class_or_this,$userinfo,$str,$callbacks,%optional) = @_;
    my $this = $class_or_this->_this;
    return $this->{database}->replace_with_callbacks($userinfo, $str, $callbacks, %optional);
}

1;
