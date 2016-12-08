use strict;
use Test::More;
use Test::Exception;
use Path::Tiny;
use Data::Validate::Sanctions qw/is_sanctioned get_sanction_file set_sanction_file/;

ok is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov is_sanctioned for sure";
ok !is_sanctioned(qw(chris down)),   "Chris is a good guy";

throws_ok { set_sanction_file() } qr/sanction_file is needed/, "sanction file is required";

my $tempfile = Path::Tiny->tempfile;
$tempfile->spew(qw(CHRISDOWN));
lives_ok { set_sanction_file("$tempfile"); };
is(get_sanction_file(), "$tempfile", "get sanction file ok");

ok !is_sanctioned(qw(sergei ivanov)), "Sergei Ivanov is a good boy now";
ok is_sanctioned(qw(chris down)),     "Chris is a bad boy now";
done_testing;
