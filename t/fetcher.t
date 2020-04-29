use strict;
use warnings;

use Class::Unload;
use Data::Validate::Sanctions;
use YAML::XS qw(Dump);
use Path::Tiny qw(tempfile);
use List::Util qw(first);

use Test::More;
use Test::Warnings;
use Test::MockModule;
use Test::Warn;
use Test::MockObject;

my %sources = (
    'OFAC-SDN' => {
        url_pattern => 'www.treasury.gov/ofac/downloads/sdn_xml.zip',
        sample_file => 't/data/sample_ofac_sdn.zip'
    },
    'OFAC-Consolidated' => {
        url_pattern => 'www.treasury.gov/ofac/downloads/consolidated',
        sample_file => 't/data/sample_ofac_consolidated.xml'
    },
    'HMT-Sanctions' => {
        url_pattern => 'ofsistorage.blob.core.windows.net/publishlive/ConList.csv',
        sample_file => 't/data/sample_hmt.csv'
    },
    'EU-Sanctions' => {
        url_pattern => 'webgate.ec.europa.eu',
        sample_file => 't/data/sample_eu.xml'
    },
);

my $disable_mock = 0;

my %requested_urls;
my $mocked_ua = Test::MockModule->new('Mojo::UserAgent');
$mocked_ua->mock(
    get => sub {
        my ($self, $url) = @_;

        my $source = first { $url =~ qr($sources{$_}->{url_pattern}) } keys %sources;
        $source //= 'Unknown';

        $requested_urls{$source} = $url;

        # called the unmocked sub if flag is cleared
        return $mocked_ua->original('get')->(@_) if $disable_mock;

        my $mocked_response = Test::MockObject->new;
        $mocked_response->mock(
            result => sub {
                my $mocked_result = Test::MockObject->new;

                $mocked_result->mock(is_error => sub { return $source eq 'Unknown' });
                $mocked_result->mock(
                    body => sub {
                        return undef if $source eq 'Unknown';

                        my $file_name = $sources{$source}->{sample_file};
                        open my $fh, '<', $file_name or die "Can't open $source sample file $file_name $!";
                        return do { local $/; <$fh> };
                    },
                );

                return $mocked_result;
            });
        return $mocked_response;
    });

subtest 'Fetch all sources' => sub {
    $disable_mock = 1;

    my $data;
    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run();
    }
    qr/Url is empty for EU-Sanctions/, 'Correct warning when the EU sanctions token is missing';

    is_deeply [sort keys %$data], [qw(HMT-Sanctions OFAC-Consolidated OFAC-SDN )], 'sanction source list is correct';

    cmp_ok($data->{'HMT-Sanctions'}{updated}, '>=', 1541376000, "Fetcher::run HMT-Sanctions sanctions.yml");

    cmp_ok($data->{'OFAC-SDN'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-SDN sanctions.yml");

    cmp_ok($data->{'OFAC-Consolidated'}{updated}, '>=', 1541376000, "Fetcher::run OFAC-Consolidated sanctions.yml");

    cmp_ok(scalar keys %{$data->{'HMT-Sanctions'}{'names_list'}}, '>', 1000, "HMT-Sanctions namelist");

    cmp_ok(scalar @{$data->{'HMT-Sanctions'}{'names_list'}{'ADAM Nureldine'}{dob_epoch}}, '>=', 1, "check ADAM Nureldine");

    # better to always test with mock enabled
    $disable_mock = 0;

    my %args = (
        eu_url                => 'eu.binary.com',
        ofac_sdn_url          => 'ofac_snd.binary.com',
        ofac_consolidated_url => 'ofac_con.binary.com',
        hmt_url               => 'hmt.binary.com',
    );

    undef %requested_urls;
    warnings_like {
        $data = Data::Validate::Sanctions::Fetcher::run(%args);
    }
    [
        qr(EU-Sanctions list update failed: File not downloaded for eu.binary.com),
        qr(HMT-Sanctions list update failed: File not downloaded for hmt.binary.com),
        qr(OFAC-Consolidated list update failed: File not downloaded for ofac_con.binary.com),
        qr(OFAC-SDN list update failed: File not downloaded for ofac_snd.binary.com),
    ],
        'Source urls are updated by params';
    is_deeply [keys %requested_urls], ['Unknown'], 'All requested urls are unknown for the ';
    is_deeply $data, {}, 'There is no result with invalid urls';

};

subtest 'EU Sanctions' => sub {
    my $source_name = 'EU-Sanctions';
    my $data;

    undef %requested_urls;
    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run();
    }
    qr/Url is empty for EU-Sanctions/, 'Correct warning when there is no EU sanction list token';
    is $data->{$source_name}, undef, 'Result is empty as expected';
    is $requested_urls{$source_name}, undef, 'No http request';

    undef %requested_urls;
    $data = Data::Validate::Sanctions::Fetcher::run(eu_sanctions_token => 'ASDF');
    is $requested_urls{$source_name}, 'https://webgate.ec.europa.eu/europeaid/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=ASDF',
        'Correct http is requested';
    ok $data->{$source_name}, 'EU Sanctions are loaded from the sample file';
    is $data->{$source_name}{updated}, 1586908800, "EU sanctions update date matches the sample file";
    is scalar keys %{$data->{$source_name}{names_list}}, 13, "Number of names matches the content of the sample EU sanction";

    undef %requested_urls;
    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run(
            eu_url             => 'http://dummy.binary.com',
            eu_sanctions_token => 'ASDF'
        );
    }
    qr(File not downloaded for http://dummy.binary.com), 'Correct warning, because the url was UNKNOWN for the mocked User Agent';
    is $requested_urls{Unknown}, 'http://dummy.binary.com', 'The default url masked by eu_sanctions_url argument';

    $data = Data::Validate::Sanctions::Fetcher::run(eu_sanctions_token => 'ASDF');

    for my $ailias_name ('Fahd Bin Adballah BIN KHALID', 'Khalid Shaikh MOHAMMED', 'Khalid Adbul WADOOD', 'Ashraf Refaat Nabith HENIN', 'Salem ALI') {
        is_deeply $data->{$source_name}->{names_list}->{$ailias_name},
            {
            dob_epoch => [-148867200, -184204800],
            dob_year  => []
            },
            'Aslias names have the same dates + multiple epochs extacted from a single entry';
    }

    is_deeply $data->{$source_name}->{names_list}->{'Youcef Adel'},
        {
        dob_epoch => [-127958400],
        dob_year  => ['1958']
        },
        'Cases with both epoch and year';

    is_deeply $data->{$source_name}->{names_list}->{'Yu-ro Han'},
        {
        dob_epoch => [],
        dob_year  => []
        },
        'Cases without epoch or year';

    is_deeply $data->{$source_name}->{names_list}->{'Leo Manzi'},
        {
        dob_epoch => [],
        dob_year  => ['1954', '1953']
        },
        'Case with multiple years';
};

subtest 'HMT Sanctions' => sub {
    my $source_name = 'HMT-Sanctions';
    my $data;

    my %args = (eu_sanctions_token => 'ABCD');

    undef %requested_urls;
    $data = Data::Validate::Sanctions::Fetcher::run(%args);
    is $requested_urls{$source_name}, 'https://ofsistorage.blob.core.windows.net/publishlive/ConList.csv', 'Correct http is requested';
    ok $data->{$source_name}, 'HMT Sanctions are loaded from the sample file';
    is $data->{$source_name}{updated}, 1587945600, "Sanctions update date matches the sample file";
    is scalar keys %{$data->{$source_name}{'names_list'}}, 6, "Number of names matches the content of the sample file";

    my $dataset = $data->{$source_name}->{names_list};

    is_deeply $dataset->{'HOJATI Mohsen'},
        {
        'dob_epoch' => [-450057600],
        'dob_year'  => []
        },
        'Cases with a single epoch';

    is_deeply $dataset->{'HUBARIEVA Kateryna Yuriyivna'},
        {
        'dob_epoch' => [426211200],
        'dob_year'  => ['1983', '1984']
        },
        'Single epoch, multiple years';

    is_deeply $dataset->{'AL-TARAZI Mazen'},
        {
        'dob_epoch' => [],
        'dob_year'  => ['1962']
        },
        'Case with multiple years';

    is_deeply $dataset->{'SO Sang Kuk'},
        {
        'dob_epoch' => [],
        'dob_year'  => ['1936', '1937', '1938', '1932', '1933', '1934', '1935']
        },
        'Case with multiple years';

    is_deeply $dataset->{'SO Sang-kuk'},
        {
        'dob_epoch' => [],
        'dob_year'  => ['1936', '1937', '1938', '1932', '1933', '1934', '1935']
        },
        'Case with multiple years';

    is_deeply $dataset->{'PLOTNITSKII Igor Venediktovich'},
        {
        'dob_epoch' => [-174268800, -174182400, -174096000],
        'dob_year'  => []
        },
        'Case with multiple years';

};

subtest 'OFAC Sanctions' => sub {
    my $data = Data::Validate::Sanctions::Fetcher::run(eu_sanctions_token => 'ABCD');

    for my $source_name ('OFAC-SDN', 'OFAC-Consolidated') {

        ok $data->{$source_name}, 'Sanctions are loaded from the sample file';
        is $data->{$source_name}{updated}, 1587513600, "Snctions update date matches the sample file";
        is scalar keys %{$data->{$source_name}{'names_list'}}, 31, "Number of names matches the content of the sample file";

        my $dataset = $data->{$source_name}->{names_list};

        my $aka_names = [
            'HAFIZ SAHIB',
            'Hafez Mohammad SAYEED',
            'Hafiz Muhammad SAEED',
            'Muhammad SAEED HAFIZ',
            'Muhammad SAEED',
            'Hafiz Mohammad SAYED',
            'Hafiz Mohammad SAYID',
            'Hafiz Mohammad SAEED',
            'Hafiz Mohammad SYEED',
            'TATA JI',
        ];

        for my $name (@$aka_names) {
            is_deeply $dataset->{$name},
                {
                'dob_epoch' => [-617760000],
                'dob_year'  => []
                },
                "Alias names share the same dob information ($name)";
        }

        $aka_names = [
            'Hafiz Saeed KHAN',
            'Hafiz Said KHAN',
            'Shaykh Hafidh Sa\'id KHAN',
            'Hafiz Sa\'id KHAN',
            'Hafiz Said Muhammad KHAN',
            'Hafiz SA\'ID',
            'Wali Hafiz Sayid KHAN',
            'Said Khan HAFIZ',
            'Hafez Sayed KHAN',
            'Sayed AHMAD',
        ];

        for my $name (@$aka_names) {
            is_deeply $dataset->{$name},
                {
                'dob_epoch' => [],
                'dob_year'  => [1976, 1977, 1978, 1979]
                },
                "Alias names share the same dob information ($name)";
        }

        is_deeply $dataset->{'Hafiz SAEED'},
            {
            'dob_epoch' => [-617760000],
            'dob_year'  => [1976, 1977, 1978, 1979],
            },
            'Hafiz Saeed is shared between two groups';

        $aka_names = [
            'Mohammad Reza NAQDI',
            'Gholam-reza NAQDI',
            'Mohammad Reza SHAMS',
            'Mohammedreza NAGHDI',
            'Mohammad Reza NAGHDI',
            'Mohammad-Reza NAQDI',
            'Muhammad NAQDI',
            'Gholamreza NAQDI',
        ];
        for my $name (@$aka_names) {
            is_deeply $dataset->{$name},
                {
                'dob_epoch' => [],
                'dob_year'  => [1951, 1952, 1953, 1960, 1961, 1962]
                },
                "Alias names share the same dob information ($name)";
        }

    }
};

done_testing;
