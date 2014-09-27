use strict;
use Test::More;
use Data::Validate::Sanctions qw/is_sanctioned/;

ok is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov is_sanctioned for sure";
ok ! is_sanctioned(qw(chris down)),   "Chris is a good guy";

done_testing;
