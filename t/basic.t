use strict;
use Test::More;
use Data::Validate::Terrorist qw/is_terrorist/;

ok is_terrorist(qw(sergei ivanov)), "Sergei Ivanov is ia terrorist for sure";
ok ! is_terrorist(qw(chris down)),   "Chris is a good guy";

done_testing;
