use strict;
use warnings;

use Data::Validate::Sanctions::Fetcher;
use Test::More;
use Test::Warnings;
use Test::Warn;

subtest 'Fetch and process all sources from default urls' => sub {
    # EU sanctions cannot be tested without a tooken; let's skip it
    my $data = Data::Validate::Sanctions::Fetcher::run(eu_url => 'file://t/data/sample_eu.xml');

    is_deeply [sort keys %$data], [qw(EU-Sanctions HMT-Sanctions OFAC-Consolidated OFAC-SDN )], 'sanction source list is correct';

    cmp_ok($data->{'EU-Sanctions'}{updated}, '>=', 1541376000, "Fetcher::run HMT-Sanctions sanctions.yml");

    cmp_ok($data->{'HMT-Sanctions'}{updated}, '>=', 1541376000, "Fetcher::run HMT-Sanctions sanctions.yml");

    cmp_ok($data->{'OFAC-SDN'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-SDN sanctions.yml");

    cmp_ok($data->{'OFAC-Consolidated'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-Consolidated sanctions.yml");

    cmp_ok(scalar keys %{$data->{'HMT-Sanctions'}{'names_list'}}, '>', 1000, "HMT-Sanctions namelist");

    cmp_ok(scalar @{$data->{'HMT-Sanctions'}{'names_list'}{'ADAM Nureldine'}{dob_epoch}}, '>=', 1, "check ADAM Nureldine");
};

done_testing;
