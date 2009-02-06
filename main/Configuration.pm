# -----------------------------------------------------------------------------
# $Id$
# -----------------------------------------------------------------------------
# このクラスはフック`reloaded'を用意します。
# フック`reloaded'は、設定ファイルがリロードされた時に呼ばれます。
# -----------------------------------------------------------------------------
package Configuration;
# Configuration及びConfiguration::BlockはUTF-8バイト列でデータを保持します。
use strict;
use warnings;
use UNIVERSAL;
use Carp;
use Configuration::Preprocessor;
use Configuration::Parser;
use Configuration::Block;
use Hook;
our @ISA = 'HookTarget';
our $AUTOLOAD;
use Tiarra::SharedMixin qw(shared shared_conf);
our $_shared_instance;
# 値を取得するにはgetメソッドを用いる他、エントリ名をそのままメソッドとして呼ぶ事も出来ます。
#
# $conf->hoge;
# ブロックhogeを返す。hogeが未定義ならundef値を返す。

sub _new {
    my ($class) = @_;
    my $obj = {
	conf_file => '', # confファイルへのパス
	time_on_load => 0, # 最後にloadが実行された時刻。
	blocks => {}, # 汎用ブロック名 -> Configuration::Block ここにモジュール設定は入らない。
	modules => [], # +で指定されたモジュールのConfiguration::Block
	included_files => [], # include されたすべてのファイル(面倒なので conf_file を含む)
    };
    bless $obj,$class;
    $obj;
}

sub get {
    my ($class_or_this,$block_name) = @_;
    my $this = $class_or_this->_this;
    # 汎用ブロックを検索

    if (!defined $block_name) {
	carp "Configuration->get, Arg[0] is undef.\n";
    }

    $this->{blocks}->{$block_name};
}

sub find_module_conf {
    my ($class_or_this,$module_name,$option) = @_;
    my $this = $class_or_this->_this;
    # モジュールの設定を検索
    foreach my $conf (@{$this->{modules}}) {
	return $conf if $conf->block_name eq $module_name;
    }
    if ($option eq 'block') {
	Configuration::Block->new($module_name);
    } else {
	undef;
    }
}

sub get_list_of_modules {
    # confで指定された順番で、+とされた全てのモジュールの
    # Configuration::Blockを持つ配列を指すリファレンスを返す。
    shift->_this->{modules};
}

sub check_if_updated {
    # 最後にloadを実行してからconfファイルが更新されたか。
    # 一度もloadしていなければ必ず1を返す。
    # ファイル名が保存されていなければ必ず0を返す。
    my $this = shift->_this;
    if ($this->{time_on_load} == 0) {
	1;
    } else {
	if (defined $this->{conf_file}) {
	    #$this->{time_on_load} < (stat $this->{conf_file})[9];
	    foreach (@{$this->{included_files}}) {
		return 1 if ($this->{time_on_load} < (stat $_)[9]);
	    }
	    0;
	} else {
	    0;
	}
    }
}

sub load {
    # confファイルを読む。ファイルへのパスを省略すると、
    # 前回のload時に指定されたパスからリロードする。
    # ファイル名の代わりにIO::Handleのオブジェクトを渡しても良い。
    # その場合はリロードは不可能になる。
    my ($class_or_this,$conf_file) = @_;
    my $this = $class_or_this->_this;
    my $this_is_reload = !defined $conf_file;

    if (defined $conf_file) {
	if (ref($conf_file) && UNIVERSAL::isa($conf_file,'IO::Handle')) {
	    # IO::Handleだった場合は保存しておけない。
	    $this->{conf_file} = undef;
	} else {
	    # ファイル名なので保存しておく。
	    $this->{conf_file} = $conf_file;
	}
    } else {
	if (defined $this->{conf_file}) {
	    $conf_file = $this->{conf_file};
	} else {
	    croak "Configuration->load, Arg[1] was omitted or undef, but no file names were saved yet.\n";
	}
    }

    $this->{time_on_load} = time;

    # プリプロセスしてからパース
    my $preprocessor = Configuration::Preprocessor->new;
    my $body = $preprocessor->execute($conf_file);
    my $parser = Configuration::Parser->new($body);
    my $parsed = $parser->parsed;

    # 定義されていない値はデフォルト値で埋める。
    $this->_complete_table_with_defaults($parsed);

    # general->conf-encodingを見て文字コードをUTF-8に変換
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

    # とりあえずモジュールのブロックとそうでないものに分ける。
    my $blocks = {};
    my $modules = [];
    foreach my $block (@$parsed) {
	my $blockname = $block->block_name;

	if ($blockname =~ m/^-/) {
	    # -ブロックなので捨てる。
	    next;
	} elsif ($blockname =~ m/^\+/) {
	    # +ブロックなので+を消して登録
	    $blockname =~ s/^\+\s*//;
	    $block->block_name($blockname);

	    push @$modules,$block;
	} else {
	    # 普通のブロック。
	    $blocks->{$blockname} = $block;
	}
    }

    $this->_check_required_definitions($blocks); # 省略不可能な定義を調べ、もし有ればdieする。
    $this->_check_duplicated_modules($modules); # 同じモジュールが複数回定義されていたらdieする。

    # ここまでdieせずに来れたという事は、何もエラーが出なかったという事。
    # $thisに登録する事で確定する。
    $this->{blocks} = $blocks;
    $this->{modules} = $modules;
    $this->{included_files} = [$preprocessor->included_files]
	if (defined $this->{conf_file}); # リロード可能な場合は include_files を登録する。

    # リロードした場合はフックを呼ぶ。
    if ($this_is_reload) {
	$this->call_hooks('reloaded');
    }
}


# デフォルト値のテーブル。
my $defaults = {
    general => {
	'conf-encoding' => 'auto',
	'server-in-encoding' => 'jis',
	'server-out-encoding' => 'jis',
	'client-in-encoding' => 'jis',
	'client-out-encoding' => 'jis',
	'stdout-encoding' => 'utf8',
	'sysmsg-prefix' => 'tiarra',
	'sysmsg-prefix-use-masks' => {
	    'system' => '*',
	    'priv' => '',
	    'channel' => '*',
	},
	# nick-fix-mode のデフォルト値も後で別処理。
	'messages' => {
	    'quit' => {
		'netconf-changed-reconnect' =>
		    'Server Configuration changed; reconnect',
		'netconf-changed-disconnect' =>
		    'Server Configuration changed; disconnect',
	    }
	   },
    },
    networks => {
	'name' => 'main',
	# defaultのデフォルト値は特殊なので後で別処理。
	'multi-server-mode' => 1,
	'channel-network-separator' => '@',
	'action-when-disconnected' => 'part-and-join',
    },
};
sub _complete_table_with_defaults {
    my ($this, $blocks) = @_;

    my $root_block = Configuration::Block->new('ROOT');
    map {
	$root_block->set($_->block_name, $_);
    } @$blocks;
    $this->_complete_block_with_defaults($root_block, $defaults);

    # networksのdefaultだけは別処理。
    my $networks = $root_block->networks;
    if (!defined $networks->default) {
	$networks->set('default',$networks->name);
    }

    my $general = $root_block->general;
    if (!defined $general->nick_fix_mode) {
	$general->set('nick-fix-mode', do {
	    if ($networks->multi_server_mode) {
		0;
	    } else {
		1;
	    }
	});
    }

    @$blocks = values(%{$root_block->table});
    $blocks;
}

sub _complete_block_with_defaults {
    my ($this, $blocks, $defaults) = @_;

    while (my ($default_block_name,$default_block) = each %$defaults) {
	# このブロックは存在しているか？
	unless (defined $blocks->get($default_block_name)) {
	    # ブロックごと省略されていたので空のブロックを定義。
	    $blocks->set($default_block_name,
			 Configuration::Block->new($default_block_name));
	}

	my $block = $blocks->get($default_block_name);
	my $must_check_child = {};
	while (my ($default_key,$default_value) = each %{$default_block}) {
	    if ((!ref($default_value)) ||
		    (ref($default_value) eq 'ARRAY')) {
		# この値は存在しているか？
		if (!defined $block->get($default_key)) {
		    # 値が省略されていたので値を定義。
		    $block->set($default_key,$default_value);
		}
	    } elsif (ref($default_value) eq 'HASH') {
		$must_check_child->{$default_key} = $default_value;
	    }
	}
	if (values %$must_check_child) {
	    $this->_complete_block_with_defaults($block, $must_check_child);
	}
    }
}

my $required = {
    general => ['nick','user','name'],
    # [ネットワーク名]のhost,portは別処理。
};
sub _check_required_definitions {
    my ($this,$blocks) = @_;
    if (!defined $blocks) {
	$blocks = $this->{blocks};
    }
    
    my $error = sub {
	my ($block_name,$key) = @_;
	die "Required definition '$key' in block '$block_name' was not found.\n";
    };
    
    # $requiredで定義されているものに関してチェックを行なう。
    while (my ($required_block_name,$required_keys) = each %{$required}) {
	foreach my $required_key (@{$required_keys}) {
	    unless ($blocks->{$required_block_name}->get($required_key)) {
		# 必要だとされているのに定義が無かった。
		$error->($required_block_name,$required_key);
	    }
	}
    }
    
    # 各ネットワークのserver/host,portをチェック。
    my @network_names = $blocks->{networks}->name('all');
    foreach my $network_name (@network_names) {
	my $block = $blocks->{$network_name};
	if (!defined $block) {
	    die "Block $network_name was not found. It was enumerated in networks/name.\n";
	}
	if (!defined $block->get('server')) {
	    foreach my $required_key (qw(host port)) {
		if (!defined $block->get($required_key)) {
		    # 必要だとされているのに定義が無かった。
		    $error->($network_name,$required_key);
		}
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
	# DESTROYは伝達させない。
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
