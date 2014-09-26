use strict;
use Test::More;
use Data::Validate::Terrorist;

my $validator = Data::Validate::Terrorist->new;

ok $validator->is_terrorist(qw(sergei ivanov)), "Sergei Ivanov is ia terrorist for sure";
ok ! $validator->is_terrorist(qw(chris down)),   "Chris is a good guy";

done_testing;
