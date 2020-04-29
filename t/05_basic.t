use strict;
use warnings;

use Class::Unload;
use Data::Validate::Sanctions;
use YAML::XS qw(Dump);
use Path::Tiny qw(tempfile);
use Test::Exception;
use Test::Warnings;
use Test::More;

ok Data::Validate::Sanctions::is_sanctioned('NEVEROV', 'Sergei Ivanovich', -253411200), "Sergei Ivanov is_sanctioned for sure";
ok !Data::Validate::Sanctions::is_sanctioned('NEVEROV', 'Sergei Ivanovich'), "Sergei Ivanov is not sanctioned without a birthdate";
ok !Data::Validate::Sanctions::is_sanctioned(qw(chris down)), "Chris is a good guy";
ok !Data::Validate::Sanctions::is_sanctioned(qw(Luke Lucky)), "Luke is a good boy";

throws_ok { Data::Validate::Sanctions::set_sanction_file() } qr/sanction_file is needed/, "sanction file is required";

my $tempfile = Path::Tiny->tempfile;
$tempfile->spew(
    Dump({
            test1 => {
                updated    => time,
                names_list => {
                    'CHRIS DOWN' => {'dob_epoch' => []},
                    'Lucky Luke' => {
                        'dob_epoch' => [],
                        'dob_year'  => [qw(1996 2000)]
                    },
                },
            },
        }));
lives_ok { Data::Validate::Sanctions::set_sanction_file("$tempfile"); };
is(Data::Validate::Sanctions::get_sanction_file(), "$tempfile", "get sanction file ok");

ok !Data::Validate::Sanctions::is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov is a good boy now";
ok Data::Validate::Sanctions::is_sanctioned(qw(chris down)),     "Chris is a bad boy now";
ok Data::Validate::Sanctions::is_sanctioned(qw(chris down), Date::Utility->new('1996-10-10')->epoch), "Chris is a bad boy even with birthdate";
ok !Data::Validate::Sanctions::is_sanctioned(qw(Luke Lucky)), "Luke is a good boy without date of birth";
ok Data::Validate::Sanctions::is_sanctioned(qw(Luke Lucky), Date::Utility->new('1996-10-10')->epoch), "Luke is a bad boy if year of birth matches";
ok !Data::Validate::Sanctions::is_sanctioned(qw(Luke Lucky), Date::Utility->new('1990-01-10')->epoch),
    "Luke is not sanctioned with mismatching year of birth";

done_testing;
