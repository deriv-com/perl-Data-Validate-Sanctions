use strict;
use Test::More;
use Data::Validate::Sanctions;

my $validator = Data::Validate::Sanctions->new;

ok $validator->is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov is_sanctioned for sure";
ok ! $validator->is_sanctioned(qw(chris down)),   "Chris is a good guy";

done_testing;
