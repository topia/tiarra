use strict;
use warnings;
use Test::More;
use lib qw(main module);
use Tools::HashTools;

my $hashtables = [{foo => 'hoge', bar => 'fuga'}];
sub r {
    Tools::HashTools::replace_recursive(shift, $hashtables);
}

my @testcases = (
    ['#(foo)'			=> 'hoge'],
    ['#(bar)'			=> 'fuga'],
    ['#(FOO|foo)'		=> 'hoge',	'keys must be case sensitive'],
    ['#(wrong|;moge)'		=> 'moge',	'default static value'],
    ['#(foo;%s moge)'		=> 'hoge moge',	'basic formatting'],
    ['#(foo;(%s))'		=> '(hoge)',	'formatting with paren'],
    ['#(all|failed)'		=> 'all|failed','expansion failed at all'],
    ['#(foo;#(bar) moge)'	=> 'fuga moge',	'recursive expansion'],
    ['#(foo;%% %s)'		=> '% hoge',	'test to escape in formatting'],
);

plan tests => scalar @testcases;
is r($_->[0]), $_->[1], $_->[2] || "expand $_->[0]" for @testcases;
