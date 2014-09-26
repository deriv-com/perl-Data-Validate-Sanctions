use strict;
use Test::More;
use Data::Validate::Terrorist qw/is_terrorist/;

ok( is_terrorist('HERRERA BUITRAGO, Stella') );
ok(! is_terrorist('Fayland Lam') );

done_testing;
