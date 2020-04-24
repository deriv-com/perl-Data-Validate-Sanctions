use strict;
use Class::Unload;
use Data::Validate::Sanctions;
use YAML::XS qw(Dump);
use Path::Tiny qw(tempfile);
use Test::More;

my $data = Data::Validate::Sanctions::Fetcher::run();

is_deeply [sort keys %$data], [qw(EU-Sanctions HMT-Sanctions OFAC-Consolidated OFAC-SDN )], 'sanction source list is correct';

cmp_ok($data->{'HMT-Sanctions'}{updated}, '>=', 1541376000, "Fetcher::run HMT-Sanctions sanctions.yml");

cmp_ok($data->{'OFAC-SDN'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-SDN sanctions.yml");

cmp_ok($data->{'OFAC-Consolidated'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-Consolidated sanctions.yml");

cmp_ok($data->{'EU-Sanctions'}{updated}, '>=', 1541376000, "EU sanctions update date is accepatble");

cmp_ok(scalar keys %{$data->{'HMT-Sanctions'}{'names_list'}}, '>', 1000, "HMT-Sanctions namelist");

cmp_ok(scalar keys %{$data->{'EU-Sanctions'}{'names_list'}}, '>', 1000, "Number of names in EU sanctions is high enough");

cmp_ok(scalar @{$data->{'HMT-Sanctions'}{'names_list'}{'ADAM Nureldine'}{'dob_epoch'}}, '>=', 1, "check ADAM Nureldine");

done_testing;
