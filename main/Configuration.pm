# -----------------------------------------------------------------------------
# $Id: Configuration.pm,v 1.25 2004/03/07 10:34:19 topia Exp $
# -----------------------------------------------------------------------------
# ���Υ��饹�ϥեå�`reloaded'���Ѱդ��ޤ���
# �եå�`reloaded'�ϡ�����ե����뤬����ɤ��줿���˸ƤФ�ޤ���
# -----------------------------------------------------------------------------
package Configuration;
# Configuration�ڤ�Configuration::Block��UTF-8�Х�����ǥǡ������ݻ����ޤ���
use strict;
use warnings;
use Unicode::Japanese;
use UNIVERSAL;
use Carp;
use Configuration::Preprocessor;
use Configuration::Parser;
use Configuration::Block;
use Hook;
our @ISA = 'HookTarget';
our $AUTOLOAD;
our $_shared_instance;
# �ͤ��������ˤ�get�᥽�åɤ��Ѥ���¾������ȥ�̾�򤽤Τޤޥ᥽�åɤȤ��ƸƤֻ������ޤ���
#
# $conf->hoge;
# �֥�å�hoge���֤���hoge��̤����ʤ�undef�ͤ��֤���

*shared = \&shared_conf;
sub shared_conf {
    unless (defined $_shared_instance) {
	$_shared_instance = _new Configuration();
    }
    $_shared_instance;
}

sub _new {
    my ($class) = @_;
    my $obj = {
	conf_file => '', # conf�ե�����ؤΥѥ�
	time_on_load => 0, # �Ǹ��load���¹Ԥ��줿���
	blocks => {}, # ���ѥ֥�å�̾ -> Configuration::Block �����˥⥸�塼�����������ʤ���
	modules => [], # +�ǻ��ꤵ�줿�⥸�塼���Configuration::Block
    };
    bless $obj,$class;
    $obj;
}

sub get {
    my ($this,$block_name) = @_;
    # ���ѥ֥�å��򸡺�

    if (!defined $block_name) {
	carp "Configuration->get, Arg[0] is undef.\n";
    }

    $this->{blocks}->{$block_name};
}

sub find_module_conf {
    my ($this,$module_name) = @_;
    # �⥸�塼�������򸡺�
    foreach my $conf (@{$this->{modules}}) {
	return $conf if $conf->block_name eq $module_name;
    }
    undef;
}

sub get_list_of_modules {
    # conf�ǻ��ꤵ�줿���֤ǡ�+�Ȥ��줿���ƤΥ⥸�塼���
    # Configuration::Block����������ؤ���ե���󥹤��֤���
    shift->{modules};
}

sub check_if_updated {
    # �Ǹ��load��¹Ԥ��Ƥ���conf�ե����뤬�������줿����
    # ���٤�load���Ƥ��ʤ����ɬ��1���֤���
    # �ե�����̾����¸����Ƥ��ʤ����ɬ��0���֤���
    my $this = shift;
    if ($this->{time_on_load} == 0) {
	1;
    }
    else {
	if (defined $this->{conf_file}) {
	    $this->{time_on_load} < (stat $this->{conf_file})[9];
	}
	else {
	    0;
	}
    }
}

sub load {
    # conf�ե�������ɤࡣ�ե�����ؤΥѥ����ά����ȡ�
    # �����load���˻��ꤵ�줿�ѥ��������ɤ��롣
    # �ե�����̾�������IO::Handle�Υ��֥������Ȥ��Ϥ��Ƥ��ɤ���
    # ���ξ��ϥ���ɤ��Բ�ǽ�ˤʤ롣
    my ($this,$conf_file) = @_;
    my $this_is_reload = !defined $conf_file;

    if (defined $conf_file) {
	if (ref($conf_file) && UNIVERSAL::isa($conf_file,'IO::Handle')) {
	    # IO::Handle���ä�������¸���Ƥ����ʤ���
	    $this->{conf_file} = undef;
	}
	else {
	    # �ե�����̾�ʤΤ���¸���Ƥ�����
	    $this->{conf_file} = $conf_file;
	}
    }
    else {
	if (defined $this->{conf_file}) {
	    $conf_file = $this->{conf_file};
	}
	else {
	    croak "Configuration->load, Arg[1] was omitted or undef, but no file names were saved yet.\n";
	}
    }

    $this->{time_on_load} = time;

    # �ץ�ץ������Ƥ���ѡ���
    my $body = Configuration::Preprocessor::preprocess($conf_file);
    my $parser = Configuration::Parser->new($body);
    my $parsed = $parser->parsed;

    # �������Ƥ��ʤ��ͤϥǥե�����ͤ����롣
    &_complete_table_with_defaults($parsed);

    # general->conf-encoding�򸫤�ʸ�������ɤ�UTF-8���Ѵ�
    my $conf_encoding = do {
	my $result;
	foreach my $block (@$parsed) {
	    if ($block->block_name eq 'general') {
		$result = $block->conf_encoding;
		last;
	    }
	}
	$result;
    };
    foreach my $block (@$parsed) {
	$block->reinterpret_encoding($conf_encoding);
    }

    # �Ȥꤢ�����⥸�塼��Υ֥�å��Ȥ����Ǥʤ���Τ�ʬ���롣
    my $blocks = {};
    my $modules = [];
    foreach my $block (@$parsed) {
	my $blockname = $block->block_name;

	if ($blockname =~ m/^-/) {
	    # -�֥�å��ʤΤǼΤƤ롣
	    next;
	}
	elsif ($blockname =~ m/^\+/) {
	    # +�֥�å��ʤΤ�+��ä�����Ͽ
	    $blockname =~ s/^\+\s*//;
	    $block->block_name($blockname);

	    push @$modules,$block;
	}
	else {
	    # ���̤Υ֥�å���
	    $blocks->{$blockname} = $block;
	}
    }

    $this->_check_required_definitions($blocks); # ��ά�Բ�ǽ�������Ĵ�١��⤷ͭ���die���롣
    $this->_check_duplicated_modules($modules); # Ʊ���⥸�塼�뤬ʣ�����������Ƥ�����die���롣

    # �����ޤ�die��������줿�Ȥ������ϡ����⥨�顼���Фʤ��ä��Ȥ�������
    # $this����Ͽ������ǳ��ꤹ�롣
    $this->{blocks} = $blocks;
    $this->{modules} = $modules;

    # ����ɤ������ϥեå���Ƥ֡�
    if ($this_is_reload) {
	$this->call_hooks('reloaded');
    }
}


# �ǥե�����ͤΥơ��֥롣
my $defaults = {
    general => {
	'conf-encoding' => 'auto',
	'server-in-encoding' => 'jis',
	'server-out-encoding' => 'jis',
	'client-in-encoding' => 'jis',
	'client-out-encoding' => 'jis',
	'stdout-encoding' => 'euc',
	'sysmsg-prefix' => 'tiarra',
	'sysmsg-prefix-use-masks' => {
	    'system' => '*',
	    'priv' => '',
	    'channel' => '*',
	},
    },
    networks => {
	'name' => 'main',
	# default�Υǥե�����ͤ��ü�ʤΤǸ���̽�����
	'multi-server-mode' => 1,
	'channel-network-separator' => '@',
	'action-when-disconnected' => 'part-and-join',
    },
};
sub _complete_table_with_defaults {
    my ($blocks) = @_;

    my $root_block = Configuration::Block->new('ROOT');
    map {
	$root_block->set($_->block_name, $_);
    } @$blocks;
    _complete_block_with_defaults($root_block, $defaults);

    # networks��default�������̽�����
    my $networks = $root_block->networks;
    if (!defined $networks->default) {
	$networks->set('default',$networks->name);
    }

    @$blocks = values(%{$root_block->table});
    $blocks;
}

sub _complete_block_with_defaults {
    my ($blocks, $defaults) = @_;

    while (my ($default_block_name,$default_block) = each %$defaults) {
	# ���Υ֥�å���¸�ߤ��Ƥ��뤫��
	unless (defined $blocks->get($default_block_name)) {
	    # �֥�å����Ⱦ�ά����Ƥ����ΤǶ��Υ֥�å��������
	    $blocks->set($default_block_name,
			 Configuration::Block->new($default_block_name));
	}
	
	my $block = $blocks->get($default_block_name);
	my $must_check_child = {};
	while (my ($default_key,$default_value) = each %{$default_block}) {
	    if ((!ref($default_value)) ||
		    (ref($default_value) eq 'ARRAY')) {
		# �����ͤ�¸�ߤ��Ƥ��뤫��
		if (!defined $block->get($default_key)) {
		    # �ͤ���ά����Ƥ����Τ��ͤ������
		    $block->set($default_key,$default_value);
		}
	    } elsif (ref($default_value) eq 'HASH') {
		$must_check_child->{$default_key} = $default_value;
	    }
	}
	if (values %$must_check_child) {
	    _complete_block_with_defaults($block, $must_check_child);
	}
    }
}

my $required = {
    general => ['nick','user','name'],
    # [�ͥåȥ��̾]��host,port���̽�����
};
my $required_in_each_networks = ['host','port'];
sub _check_required_definitions {
    my ($this,$blocks) = @_;
    if (!defined $blocks) {
	$blocks = $this->{blocks};
    }
    
    my $error = sub {
	my ($block_name,$key) = @_;
	die "Required definition '$key' in block '$block_name' was not found.\n";
    };
    
    # $required���������Ƥ����Τ˴ؤ��ƥ����å���Ԥʤ���
    while (my ($required_block_name,$required_keys) = each %{$required}) {
	foreach my $required_key (@{$required_keys}) {
	    unless ($blocks->{$required_block_name}->get($required_key)) {
		# ɬ�פ��Ȥ���Ƥ���Τ������̵���ä���
		$error->($required_block_name,$required_key);
	    }
	}
    }
    
    # �ƥͥåȥ����host��port������å���
    my @network_names = $blocks->{networks}->name('all');
    foreach my $network_name (@network_names) {
	foreach my $required_key (@{$required_in_each_networks}) {
	    my $block = $blocks->{$network_name};
	    if (!defined $block) {
		die "Block $network_name was not found. It was enumerated in networks/name.\n";
	    }
	    if (!defined $blocks->{$network_name}->get($required_key)) {
		# ɬ�פ��Ȥ���Ƥ���Τ������̵���ä���
		$error->($network_name,$required_key);
	    }
	}
    }
}

sub _check_duplicated_modules {
    my ($this,$modules) = @_;
    if (!defined $modules) {
	$modules = $this->{modules};
    }

    my $modnames = {};
    foreach my $block (@$modules) {
	my $modname = $block->block_name;
	if (defined $modnames->{$modname}) {
	    die "Module $modname has multiple definitions. Only one is allowed.\n";
	}
	$modnames->{$modname} = 1;
    }
}

sub AUTOLOAD {
    my $this = shift;
    if ($AUTOLOAD =~ /::DESTROY$/) {
	# DESTROY����ã�����ʤ���
	return;
    }

    (my $key = $AUTOLOAD) =~ s/.+?:://g;
    return $this->get($key);
}

# -----------------------------------------------------------------------------
package Configuration::Hook;
use FunctionalVariable;
use base 'Hook';

our $HOOK_TARGET_NAME = 'Configuration';
our @HOOK_NAME_CANDIDATES = 'reloaded';
our $HOOK_TARGET_DEFAULT;
FunctionalVariable::tie(
    \$HOOK_TARGET_DEFAULT,
    FETCH => sub {
	Configuration->shared;
    },
);

1;
