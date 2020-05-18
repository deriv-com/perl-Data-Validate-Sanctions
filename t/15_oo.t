use strict;
use Class::Unload;
use Data::Validate::Sanctions;
use YAML::XS qw(Dump);
use Path::Tiny qw(tempfile);
use Test::Warnings;
use Test::More;

my $validator = Data::Validate::Sanctions->new;

ok $validator->is_sanctioned('NEVEROV', 'Sergei Ivanovich', -253411200), "Sergei Ivanov is_sanctioned for sure";
my $result = $validator->get_sanctioned_info('abu', 'usama', -306028800);
is_deeply $result,
    {
    list        => 'EU-Sanctions',
    matched     => 1,
    matched_dob => -306028800,
    name        => 'Abu Usama',
    reason      => 'Date of birth matches'
    },
    'Validation details are correct';

ok !$validator->is_sanctioned(qw(chris down)), "Chris is a good guy";

$result = $validator->get_sanctioned_info('ABBATTAY', 'Mohamed', 174614567);
is $result->{matched}, 0, 'ABBATTAY Mohamed is safe';

$result = $validator->get_sanctioned_info('Abu', 'Salem');
is $result->{matched}, 0, 'He used to match previously; but he has date of birth now.';

$result = $validator->get_sanctioned_info('Abu', 'Salem', '1948-10-10');
is_deeply $result,
    {
    list        => 'OFAC-Consolidated',
    matched     => 1,
    matched_dob => '1948',
    name        => 'Ibrahim ABU SALEM',
    reason      => 'Year of birth matches'
    },
    'Validation details are correct';

my $tmpa = tempfile;

$tmpa->spew(
    Dump({
            test1 => {
                updated    => time,
                names_list => {
                    'TMPA' => {
                        'dob_epoch' => [],
                        'dob_year'  => []
                    },
                    'MOHAMMAD EWAZ Mohammad Wali' => {
                        'dob_epoch' => [],
                        'dob_year'  => []
                    },
                    'Zaki Izzat Zaki AHMAD' => {
                        'dob_epoch' => [],
                        'dob_year'  => [1999],
                        'dob_text' => ['other info'],
                    },
                    'Donald Trump' => {
                        dob_text => ['circa-1951'],
                    },
                },
            },
        }));

my $tmpb = tempfile;

$tmpb->spew(
    Dump({
            test2 => {
                updated    => time,
                names_list => {
                    'TMPB' => {
                        'dob_epoch' => [],
                        'dob_year'  => []}}
            },
        }));

$validator = Data::Validate::Sanctions->new(sanction_file => "$tmpa");
ok !$validator->is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov not is_sanctioned";
ok $validator->is_sanctioned(qw(tmpa)), "now sanction file is tmpa, and tmpa is in test1 list";
ok !$validator->is_sanctioned("Mohammad reere yuyuy", "wqwqw  qqqqq"), "is not in test1 list";
ok !$validator->is_sanctioned("Zaki",                 "Ahmad"),        "is in test1 list - but with a dob year";
ok $validator->is_sanctioned("Zaki", "Ahmad", '1999-01-05'), 'the guy is sanctioned when dob year is matching';
is_deeply $validator->get_sanctioned_info("Zaki", "Ahmad", '1999-01-05'),
    {
    name        => 'Zaki Izzat Zaki AHMAD',
    matched     => 1,
    list        => 'test1',
    reason      => 'Year of birth matches',
    matched_dob => '1999',
    },
    'Sanction info is correct';
ok $validator->is_sanctioned("Ahmad", "Ahmad", '1999-10-10'), "is in test1 list";

is_deeply $validator->get_sanctioned_info("TMPA"),
    {
    list        => 'test1',
    matched     => 1,
    matched_dob => 'N/A',
    name        => 'TMPA',
    reason      => 'Name is similar'
    },
    'Sanction info is correct';

is_deeply $validator->get_sanctioned_info('Donald', 'Trump', '1999-01-05'),
    {
    name        => 'Donald Trump',
    matched     => 1,
    matched_dob => 'N/A',
    list        => 'test1',
    reason      => 'Name is similar - dob raw text: circa-1951',
    },
    "When client's name matches a case with dob_text";

Class::Unload->unload('Data::Validate::Sanctions');
local $ENV{SANCTION_FILE} = "$tmpb";
require Data::Validate::Sanctions;
$validator = Data::Validate::Sanctions->new;
ok $validator->is_sanctioned(qw(tmpb)), "get sanction file from ENV";
$validator = Data::Validate::Sanctions->new(sanction_file => "$tmpa");
ok $validator->is_sanctioned(qw(tmpa)), "get sanction file from args";

done_testing;
