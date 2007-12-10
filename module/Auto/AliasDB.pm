# -*- cperl -*-
# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# �����ꥢ���ե�������ɤ߹��ߤ�������#(name|nick)�Ȥ��ä�ʸ������ִ���Ԥʤ����饹��
# Tiarra�⥸�塼��ǤϤʤ���
# ���Υ��饹�϶��̤Υ��󥹥��󥹤��Ĥ������ġ�
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
    # ���饹�ؿ���
    my ($fpath,$charset) = @_;
    # re-initialize
    __PACKAGE__->_shared_init($fpath,$charset);
}

sub _new {
    # fpath���ά���뤫����ʸ�������ꤹ��ȡ�����AliasDB������ޤ���
    my ($class,$fpath,$charset) = @_;
    my $obj = {
	database => Tools::GroupDB->new($fpath, 'user', $charset || undef, 0),
	config => Configuration::shared_conf->get(__PACKAGE__)
	    || Configuration::Block->new(__PACKAGE__),
    };
    bless $obj,$class;
}

sub find_alias_prefix {
    # userinfo��nick!user@host�η�����
    # ���դ���ʤ����undef���֤���
    # flag���դ��Ƥ�find_alias���ȡ�
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
    # �����ꥢ���ޥ�����ִ���Ԥʤ���%optional���ִ����ɲä��륭�����ͤ��Ȥߤǡ���ά�ġ�
    # optional���ͤ�SCALAR�Ǥ�ARRAY<SCALAR>�Ǥ��ɤ���
    # userinfo��nick!user@host�η�����
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
    # �����ꥢ���ޥ�����ִ���Ԥʤ���%optional���ִ����ɲä��륭�����ͤ��Ȥߤǡ���ά�ġ�
    # $callbacks��alias/optional���ִ��Ǥ��ʤ��ä��ݤ˸ƤӽФ���륳����Хå��ؿ��Υ�ե���󥹡�
    # optional���ͤ�SCALAR�Ǥ�ARRAY<SCALAR>�Ǥ��ɤ���
    # userinfo��nick!user@host�η�����
    my ($class_or_this,$userinfo,$str,$callbacks,%optional) = @_;
    my $this = $class_or_this->_this;
    return $this->{database}->replace_with_callbacks($userinfo, $str, $callbacks, %optional);
}

1;
