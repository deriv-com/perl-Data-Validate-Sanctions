use strict;
use Class::Unload;
use Data::Validate::Sanctions;
use YAML::XS qw(Dump);
use Path::Tiny qw(tempfile);
use Test::More;

my $validator = Data::Validate::Sanctions->new;

ok $validator->is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov is_sanctioned for sure";
is $validator->is_sanctioned(qw(sergei ivanov)), 'HMT-Sanctions', "Sergei Ivanov is_sanctioned for sure and in correct list";
ok !$validator->is_sanctioned(qw(chris down)), "Chris is a good guy";

my $tmpa = tempfile;
$tmpa->spew(
    Dump({
            test1 => {
                updated => time,
                names   => ['TMPA']}}));
my $tmpb = tempfile;
$tmpb->spew(
    Dump({
            test2 => {
                updated => time,
                names   => ['TMPB']}}));
$validator = Data::Validate::Sanctions->new(sanction_file => "$tmpa");
ok !$validator->is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov not is_sanctioned";
is $validator->is_sanctioned(qw(tmpa)), 'test1', "now sanction file is tmpa, and tmpa is in test1 list";

Class::Unload->unload('Data::Validate::Sanctions');
local $ENV{SANCTION_FILE} = "$tmpb";
require Data::Validate::Sanctions;
$validator = Data::Validate::Sanctions->new;
ok $validator->is_sanctioned(qw(tmpb)), "get sanction file from ENV";
$validator = Data::Validate::Sanctions->new(sanction_file => "$tmpa");
ok $validator->is_sanctioned(qw(tmpa)), "get sanction file from args";
done_testing;
