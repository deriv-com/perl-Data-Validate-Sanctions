use strict;
use Test::More;
use File::Temp qw(tempfile);
use FindBin qw($Bin);
use File::stat;
use Path::Tiny;
use YAML::XS qw(Dump);

my $sanction_file;
my $sanction_data;

BEGIN {
    $sanction_data = Dump({
            test1 => {
                updated    => time,
                names_list => {'ABCD' => {'dob_epoch' => []}}}});

    (my $fh, $sanction_file) = tempfile();
    print $fh $sanction_data;
    close($fh);
    $ENV{SANCTION_FILE} = $sanction_file;
}
use Data::Validate::Sanctions qw/is_sanctioned get_sanction_file/;

is(get_sanction_file(), $sanction_file, "sanction file is correct");

ok(is_sanctioned('ABCD'),  "correct file content");
ok(!is_sanctioned('AAAA'), "correct file content");

#sleep 1 to make the mtime greater than old mtime
my $last_mtime = stat($sanction_file)->mtime;
path($sanction_file)->spew('{}');
sleep 1;
my $script = "$Bin/../bin/update_sanctions_csv";
my $lib    = "$Bin/../lib";
is(system($^X, "-I$lib", $script, $sanction_file), 0, "download file successfully");
ok($last_mtime < stat($sanction_file)->mtime, "mtime updated");

ok(!is_sanctioned('ABCD'), "correct file content");
$last_mtime = stat($sanction_file)->mtime;
ok(is_sanctioned('NEVEROV', 'Sergei Ivanovich', -253411200), "correct file content");
path($sanction_file)->spew($sanction_data);
ok(utime($last_mtime, $last_mtime, $sanction_file), 'change mtime to pretend the file not changed');
ok(is_sanctioned('NEVEROV', 'Sergei Ivanovich', -253411200), "the module still use old data because it think the file is not changed");
ok(is_sanctioned('Nashwan',               'Razzaq'),            "Name matches regardless of order");
ok(is_sanctioned('Nashwan1234~!@!      ', 'Al-Razzaq'),         "Name matches even if non-alphabets are present");
ok(is_sanctioned('Nashwan',               'Razzaq Abcert1234'), "Sanctioned when two words match");
ok(is_sanctioned('Haroon'), "Sanctioned when sanctioned individual has only one name");
done_testing;
