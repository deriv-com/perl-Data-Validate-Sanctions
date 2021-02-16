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

my %args = (
    eu_url                => "file://t/data/sample_eu.xml",
    ofac_sdn_url          => "file://t/data/sample_ofac_sdn.zip",
    ofac_consolidated_url => "file://t/data/sample_ofac_consolidated.xml",
    hmt_url               => "file://t/data/sample_hmt.csv",
);

my $mocked_ua = Test::MockModule->new('Mojo::UserAgent');
$mocked_ua->mock(
    get => sub {
        my ($self, $url) = @_;

        die "User agent MockObject is hit by the url: $url";
    });

subtest 'source url arguments' => sub {
    my %test_args = (
        eu_url                => 'eu.binary.com',
        ofac_sdn_url          => 'ofac_snd.binary.com',
        ofac_consolidated_url => 'ofac_con.binary.com',
        hmt_url               => 'hmt.binary.com',
    );

    my $data;
    warnings_like {
        $data = Data::Validate::Sanctions::Fetcher::run(%test_args);
    }
    [
        qr(EU-Sanctions list update failed: User agent MockObject is hit by the url: eu.binary.com),
        qr(HMT-Sanctions list update failed: User agent MockObject is hit by the url: hmt.binary.com ),
        qr(OFAC-Consolidated list update failed: User agent MockObject is hit by the url: ofac_con.binary.com),
        qr(OFAC-SDN list update failed: User agent MockObject is hit by the url: ofac_snd.binary.com),
    ],
        'Source urls are updated by params';

    is_deeply $data, {}, 'There is no result with invalid urls';

};

subtest 'EU Sanctions' => sub {
    my $source_name = 'EU-Sanctions';
    my $data;

    warnings_like {
        $data = Data::Validate::Sanctions::Fetcher::run(%args, eu_url => undef);
    }
    [qr/EU Sanctions will fail whithout eu_token or eu_url/, qr/Url is empty for EU-Sanctions/],
        'Correct warning when the EU sanctions token is missing';

    is $data->{$source_name}, undef, 'Result is empty as expected';

    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run(
            %args,
            eu_url   => undef,
            eu_token => 'ASDF'
        );
    }
    qr(EU-Sanctions list update failed: User agent MockObject is hit by the url: https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content\?token=ASDF),
        'token is added to the default url';
    is $data->{$source_name}, undef, 'Result is empty';

    warning_like {
        $data = Data::Validate::Sanctions::Fetcher::run(
            %args,
            eu_url   => 'http://dummy.binary.com',
            eu_token => 'ASDF'
        );
    }
    qr(EU-Sanctions list update failed: User agent MockObject is hit by the url: http://dummy.binary.com at), 'token is not added to eu_url value';

    $data = Data::Validate::Sanctions::Fetcher::run(%args);
    ok $data->{$source_name}, 'EU Sanctions are loaded from the sample file';
    is $data->{$source_name}{updated}, 1586908800, "EU sanctions update date matches the sample file";
    is scalar keys %{$data->{$source_name}{names_list}}, 15, "Number of names matches the content of the sample EU sanction";

    for my $ailias_name ('Fahd Bin Adballah BIN KHALID', 'Khalid Shaikh MOHAMMED', 'Khalid Adbul WADOOD', 'Ashraf Refaat Nabith HENIN', 'Salem ALI') {
        is_deeply $data->{$source_name}->{names_list}->{$ailias_name},
            {
            'dob_epoch'      => [-148867200, -184204800],
            'passport_no'    => ['488555'],
            'place_of_birth' => ['pk']
            },
            'Aslias names have the same dates + multiple epochs extacted from a single entry';
    }

    is_deeply $data->{$source_name}->{names_list}->{'Youcef Adel'},
        {
        'dob_epoch'      => [-127958400],
        'dob_year'       => ['1958'],
        'place_of_birth' => ['dz']
        },
        'Cases with both epoch and year';

    is_deeply $data->{$source_name}->{names_list}->{'Yu-ro Han'}, {}, 'Cases without epoch or year';

    is_deeply $data->{$source_name}->{names_list}->{'Leo Manzi'},
        {
        'dob_year'       => ['1954', '1953'],
        'place_of_birth' => ['rw'],
        'residence'      => ['cd']
        },
        'Case with multiple years';

    is_deeply $data->{$source_name}->{names_list}->{'Mohamed Ben Belkacem Aouadi'},
        {
        'dob_epoch'      => [155952000],
        'national_id'    => ['04643632'],
        'nationality'    => ['tn'],
        'passport_no'    => ['L191609'],
        'place_of_birth' => ['tn'],
        'residence'      => ['tn']
        },
        'All fields are correctly extracted';
};

subtest 'HMT Sanctions' => sub {
    my $source_name = 'HMT-Sanctions';
    my $data;

    $data = Data::Validate::Sanctions::Fetcher::run(%args);
    ok $data->{$source_name}, 'HMT Sanctions are loaded from the sample file';
    is $data->{$source_name}{updated}, 1587945600, "Sanctions update date matches the sample file";
    is scalar keys %{$data->{$source_name}{'names_list'}}, 7, "Number of names matches the content of the sample file";

    my $dataset = $data->{$source_name}->{names_list};

    is_deeply $dataset->{'HOJATI Mohsen'},
        {
        'dob_epoch' => [-450057600],
        },
        'Cases with a single epoch';

    is_deeply $dataset->{'HUBARIEVA Kateryna Yuriyivna'},
        {
        'dob_epoch'      => [426211200],
        'dob_year'       => ['1983', '1984'],
        'place_of_birth' => ['ua']
        },
        'Single epoch, multiple years';

    is_deeply $dataset->{'AL-TARAZI Mazen'},
        {
        'dob_year' => ['1962'],
        },
        'Case with multiple years';

    is_deeply $dataset->{'SO Sang Kuk'},
        {
        'dob_year' => ['1936', '1937', '1938', '1932', '1933', '1934', '1935'],
        },
        'Case with range dob years';

    is_deeply $dataset->{'PLOTNITSKII Igor Venediktovich'},
        {
        'dob_epoch'      => [-174268800, -174182400, -174096000],
        'place_of_birth' => ['ua']
        },
        'Case with multiple dob epoch';

    is_deeply $dataset->{'SAEED Hafez Mohammad'},
        {
        'dob_epoch'      => [-617760000],
        'national_id'    => ['3520025509842-7'],
        'place_of_birth' => ['pk'],
        'residence'      => ['pk'],
        'postal_code'    => ['123321'],
        },
        'All fields extracted with (explanation) removed';
};

subtest 'OFAC Sanctions' => sub {
    my $data = Data::Validate::Sanctions::Fetcher::run(%args);

    for my $source_name ('OFAC-SDN', 'OFAC-Consolidated') {
        # OFAC sources have the same structure. We've created the samle sample file for both of them.

        ok $data->{$source_name}, 'Sanctions are loaded from the sample file';
        is $data->{$source_name}{updated}, 1587513600, "Sanctions update date matches the content of sample file";
        is scalar keys %{$data->{$source_name}{'names_list'}}, 32, "Number of names matches the content of the sample file";

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
                'dob_epoch'      => [-617760000],
                'national_id'    => ['23250460642',      '3520025509842-7'],
                'passport_no'    => ['Booklet A5250088', 'BE5978421'],
                'place_of_birth' => ['pk'],
                'residence'      => ['pk']
                },
                "Alias names share the same information ($name)";
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
                'dob_year'       => [1976, 1977, 1978, 1979],
                'place_of_birth' => ['pk']
                },
                "Alias names share the same information ($name)";
        }

        is_deeply $dataset->{'Hafiz SAEED'},
            {
            'dob_epoch'      => [-617760000],
            'dob_year'       => [1976,               1977, 1978, 1979],
            'national_id'    => ['23250460642',      '3520025509842-7'],
            'passport_no'    => ['Booklet A5250088', 'BE5978421'],
            'place_of_birth' => ['pk'],
            'residence'      => ['pk']
            },
            'Hafiz Saeed appears in two group of alias names and inherits values of both';

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
                'dob_year'       => [1951, 1952, 1953, 1960, 1961, 1962],
                'place_of_birth' => ['iq', 'ir'],
                'residence'      => ['ir']
                },
                "Range dob year ($name)";
        }

        is_deeply $dataset->{'Donald Trump'},
            {
            'dob_text'  => ['circa-1951'],
            'residence' => ['us']
            },
            'dob_text is correctly extracted';
    }
};

done_testing;
