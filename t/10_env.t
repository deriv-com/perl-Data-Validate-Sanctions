use strict;
use JSON qw(encode_json);
use Path::Tiny qw(tempfile);
use Test::Exception;
use Test::More;

my ($tmpa, $tmpb);

BEGIN {
    $tmpa = tempfile;
    $tmpa->spew(
        encode_json({
                test1 => {
                    updated => time,
                    names   => ['TMPA']}}));
    $tmpb = tempfile;
    $tmpb->spew(
        encode_json({
                test1 => {
                    updated => time,
                    names   => ['TMPB']}}));
    $ENV{SANCTION_FILE} = "$tmpa";
}
use Data::Validate::Sanctions;

ok Data::Validate::Sanctions::is_sanctioned(qw(tmpa)), "get sanction file from ENV";
lives_ok { Data::Validate::Sanctions::set_sanction_file("$tmpb"); };
ok Data::Validate::Sanctions::is_sanctioned(qw(tmpb)), "file from args override env";

done_testing;
