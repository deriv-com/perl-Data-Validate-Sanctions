use strict;
use warnings;
use Class::Unload;
use Data::Validate::Sanctions;
use YAML::XS qw(Dump);
use Path::Tiny qw(tempfile);
use Test::More;
use Test::MockModule;
use Test::Warn;

        my $mocked_ua = Test::MockModule->new('Mojo::UserAgent');
    $mocked_ua->redefine(
        get => sub {
            my $self = shift;

            return 'Mocked User Agent Result';
        });

my %args = (eu_url => '',
        ofac_consolidated_url => '',
        ofac_sdn_url => '',
        hmt_url => 'file://t/data/sample_hmt.csv',
    );
my $data = Data::Validate::Sanctions::Fetcher::run(%args);
exit;

subtest 'Fetch all sources' => sub {

    my %args = (eu_url => 'file://t/data/sample_eu.xml',
        ofac_consolidated_url => 'file://t/data/sample_ofac_consolidated.xml',
        ofac_sdn_url => 'file://t/data/sample_ofac_sdn.zip',
        hmt_url => 'file://t/data/sample_hmt.csv',
    );
        
    my $data = Data::Validate::Sanctions::Fetcher::run(%args);

    is_deeply [sort keys %$data], [qw(EU-Sanctions HMT-Sanctions OFAC-Consolidated OFAC-SDN )], 'sanction source list is correct';

    cmp_ok($data->{'HMT-Sanctions'}{updated}, '>=', 1541376000, "Fetcher::run HMT-Sanctions sanctions.yml");

    cmp_ok($data->{'OFAC-SDN'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-SDN sanctions.yml");

    cmp_ok($data->{'OFAC-Consolidated'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-Consolidated sanctions.yml");

    cmp_ok(scalar keys %{$data->{'HMT-Sanctions'}{'names_list'}}, '>', 1000, "HMT-Sanctions namelist");

    cmp_ok(scalar @{$data->{'HMT-Sanctions'}{'names_list'}{'ADAM Nureldine'}{'dob_epoch'}}, '>=', 1, "check ADAM Nureldine");

    is $data->{'EU-Sanctions'}{updated}, 1586908800, "EU sanctions update date is accepatble";

    is scalar keys %{$data->{'EU-Sanctions'}{'names_list'}}, 23, "Number of names in EU sanctions is high enough";
};

subtest 'EU Sanctions' => sub {
    my $requested_url;
    my $mocked_ua = Test::MockModule->new('Mojo::UserAgent');
    $mocked_ua->redefine(
        get => sub {
            my $self = shift;
            $requested_url = shift;

            return 'Mocked User Agent Result';
        });

    my %args = (eu_url => undef,
        ofac_consolidated_url => 'file://t/data/sample_ofac_consolidated.xml',
        ofac_sdn_url => 'file://t/data/sample_ofac_sdn.zip',
        hmt_url => 'file://t/data/sample_hmt.xml',
    );
    my $data;
    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run(%args);
    }
    qr/Url is empty for EU-Sanctions/, 'Correct warning when there is no EU sanction list token';
    is_deeply $data, {}, 'Result is empty as expected';
    is $requested_url, undef, 'No http request';

    $args{eu_sanctions_token} = 'ASDF';
    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run(%args);
    }
    qr/Mocked User Agent Result/, 'Correct warning from mocked user agent';
    is $requested_url, 'https://webgate.ec.europa.eu/europeaid/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=ASDF',
        'Correct http is requested';
    is_deeply $data, {}, 'Result is empty as expected';
    $requested_url = undef;

    $args{eu_url} = 'http://dummy.binary.com';
    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run(%args);
    }
    qr/Mocked User Agent Result/, 'Correct warning from mocked user agent';
    is $requested_url, 'http://dummy.binary.com', 'The default url masked by eu_sanctions_url argument';
    is_deeply $data, {}, 'Result is empty as expected';
    $requested_url = undef;

    $args{eu_url} = 'file://t/data/sample_eu.xml';
    $data = Data::Validate::Sanctions::Fetcher::run(%args);
    is $requested_url, undef, 'No http request is made for file url';
    is_deeply [sort keys %$data], [qw(EU-Sanctions)], 'sanction source list is correct';
    is $data->{'EU-Sanctions'}{updated}, 1586908800, "EU sanctions update date is accepatble";
    is scalar keys %{$data->{'EU-Sanctions'}{'names_list'}}, 23, "Number of names in EU sanctions is high enough";

};

done_testing;
