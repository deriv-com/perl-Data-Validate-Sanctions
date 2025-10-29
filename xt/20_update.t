use strict;
use warnings;

use Test::More;
use File::Temp qw(tempfile);
use FindBin    qw($Bin);
use File::stat;
use Path::Tiny;
use YAML::XS       qw(Dump);
use Test::MockTime qw(set_fixed_time);

my $sanction_file;
my $sanction_data;

BEGIN {
    set_fixed_time(1500);

    $sanction_data = Dump({
            test1 => {
                updated => time,
                content => [{
                        names => ['ABCD'],
                    }]}});

    (my $fh, $sanction_file) = tempfile();
    print $fh $sanction_data;
    close($fh);
    $ENV{SANCTION_FILE} = $sanction_file;
}
use Data::Validate::Sanctions qw/is_sanctioned get_sanction_file/;
is(get_sanction_file(), $sanction_file, "sanction file is correct");

ok(is_sanctioned('ABCD'),  "correct file content");
ok(!is_sanctioned('AAAA'), "correct file content");

#fast-forward time to make the mtime greater than old mtime
my $last_mtime = stat($sanction_file)->mtime;
path($sanction_file)->spew('{}');

set_fixed_time(1500 + Data::Validate::Sanctions->IGNORE_OPERATION_INTERVAL);

my $script = "$Bin/../bin/update_sanctions_csv";
my $lib    = "$Bin/../lib";
my %args   = (
    # EU sanctions need a token. Sample data should be used here to avoid failure.
    '-eu_url' => "file://$Bin/../t/data/sample_eu.xml",
    # the default HMT url takes too long to download. Let's use sample data to speed it up.
    '-hmt_url'               => "file://$Bin/../t/data/sample_hmt.csv",
    '-unsc_url'              => "file://$Bin/../t/data/sample_unsc.xml",
    '-moha_url'              => "file://$Bin/../t/data/sample_moha.xml",
    '-ofac_sdn_url'          => "file://$Bin/../t/data/sample_ofac_sdn.zip",
    '-ofac_consolidated_url' => "file://$Bin/../t/data/sample_ofac_consolidated.xml",
    '-sanction_file'         => $sanction_file // ''
);

is(system($^X, "-I$lib", $script, %args), 0, "download file successfully");
ok($last_mtime < stat($sanction_file)->mtime, "mtime updated");

ok(!is_sanctioned('ABCD'), "correct file content");

# Create a Data::Validate::Sanctions object to use for testing
my $validator = Data::Validate::Sanctions->new(sanction_file => $sanction_file);

# Test that the name exists in the updated file
ok($validator->is_sanctioned('Abid', 'Hammadou'), "correct file content");

# Test name matching features
ok($validator->is_sanctioned('Hammadou',           'Abid'),          "Name matches regardless of order");
ok($validator->is_sanctioned('Abid1234~!@!      ', 'Hammadou'),      "Name matches even if non-alphabets are present");
ok($validator->is_sanctioned('Abid1234~!@!      ', 'Hammadou abcd'), "Sanctioned when two words match");

# Now test caching behavior
# First, create a validator that will cache the current data
my $cached_validator = Data::Validate::Sanctions->new(sanction_file => $sanction_file);
ok($cached_validator->is_sanctioned('Abid', 'Hammadou'), "validator can find the name before modification");

# Now modify the file but keep the same mtime
$last_mtime = stat($sanction_file)->mtime;
path($sanction_file)->spew($sanction_data);
ok(utime($last_mtime, $last_mtime, $sanction_file), 'change mtime to pretend the file not changed');

# The cached validator should still use the cached data
ok($cached_validator->is_sanctioned('Abid', 'Hammadou'), "the module still use old data because it think the file is not changed");
ok(is_sanctioned('TestOneWord'), "Sanctioned when sanctioned individual has only one name (coming from t/data/sample_eu.xml)");

done_testing;
