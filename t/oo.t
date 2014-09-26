use strict;
use Test::More;
use Data::Validate::Terrorist;

my $validator = Data::Validate::Terrorist->new;

ok( $validator->is_terrorist('HERRERA BUITRAGO, Stella') );
ok(! $validator->is_terrorist('Fayland Lam') );

done_testing;
