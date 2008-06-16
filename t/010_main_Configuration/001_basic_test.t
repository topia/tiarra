use strict;
use warnings;
use Test::More;
use lib qw(bundle main module);
use FindBin qw($Bin);

plan tests => 25;

require_ok 'Configuration::Preprocessor';
require_ok 'Configuration::Parser';
require_ok 'Configuration::Block';

my $conf_file = "$Bin/testdata1.conf";
my $conf_encoding = 'utf8';
# プリプロセスしてからパース
my $preprocessor = Configuration::Preprocessor->new;
my $body = $preprocessor->execute($conf_file);
my $parser = Configuration::Parser->new($body);
my $parsed = $parser->parsed;

foreach my $block (@$parsed) {
    $block->reinterpret_encoding($conf_encoding);
}

isa_ok $parsed, 'ARRAY', 'parsed';
is @$parsed, 2, "testdata has 2 blocks";

my $block = $parsed->[0];
isa_ok $block, 'Configuration::Block', 'block';
is $block->block_name, "foo", "first block named 'foo'";
is_deeply [$block->abc('all')], ['def'], "foo/abc has single value 'def'";
isa_ok $block->abc('block'),
    'Configuration::Block', "result of get with 'block' option";
is $block->single_block('all', 'block'), 1,
    "foo/single-block has single block";
is $block->single_block('block')->some_key, 'some-value',
    'some-key has some-value.';

$block = $parsed->[1];
isa_ok $block, 'Configuration::Block', '2nd block';
is $block->block_name, "bar", "second block named 'bar'";
is $block->get('baz'), 'qux', "bar/baz is 'qux'";

my @blocks = $block->multiple_block('block', 'all');
is @blocks, 2, "bar/multiple-block has 2 blocks";

$block = $blocks[0];
isa_ok $block, 'Configuration::Block', '1st nested block';
is $block->block_name, 'multiple-block', "nested block named 'multiple-block'";
is $block->key1, 'val1', "1st nested block has 'key1'";
is $block->key2, 'val2', "1st nested block has 'key2'";
is $block->key3, undef, "1st nested block doesn't have 'key3'";

$block = $blocks[1];
isa_ok $block, 'Configuration::Block', '2nd nested block';
is $block->block_name, 'multiple-block', "nested block named 'multiple-block'";
is $block->key2, undef, "2nd nested block doesn't have 'key2'";
is $block->key3, 'val3', "2nd nested block has 'key3'";
is $block->key4, 'val4', "2nd nested block has 'key4'";


