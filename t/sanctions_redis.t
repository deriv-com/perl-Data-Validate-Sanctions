use strict;
use warnings;

use Class::Unload;
use YAML::XS   qw(Dump);
use Path::Tiny qw(tempfile);
use Test::Warnings qw/warning/;
use Test::More;
use Test::Fatal;
use Test::MockModule;
use Test::RedisServer;
use Test::MockTime qw(set_fixed_time);
use RedisDB;
use JSON::MaybeUTF8 qw(decode_json_utf8);
use Clone qw(clone);

use Data::Validate::Sanctions::Redis;

my $redis_server = Test::RedisServer->new();
my $redis        = RedisDB->new($redis_server->connect_info);

# my $mock_data = {
#             'EU-Sanctions' => {
#                 updated => 100,
#                 content => [{
#                         names     => ['TMPA'],
#                         dob_epoch => [],
#                         dob_year  => []
#                     },
#                     {
#                         names     => ['MOHAMMAD EWAZ Mohammad Wali'],
#                         dob_epoch => [],
#                         dob_year  => []
#                     },
#                 ]},
#             'HMT-Sanctions' => {
#                 updated => 101,
#                 content => [
#                     {
#                         names     => ['Zaki Izzat Zaki AHMAD'],
#                         dob_epoch => [],
#                         dob_year  => [1999],
#                         dob_text  => ['other info'],
#                     },
#                 ]},
#             'OFAC-Consolidated' => {
#                 updated => 102,
#                 content => [
#                     {
#                         names    => ['Atom'],
#                         dob_year => [1999],
#                     },
#                     {
#                         names    => ['Donald Trump'],
#                         dob_text => ['circa-1951'],
#                     },
#                 ]},
#             'OFAC-SDN' => {
#                 updated => 103,
#                 content => [
#                     {
#                         names          => ['Bandit Outlaw'],
#                         place_of_birth => ['ir'],
#                         residence      => ['fr', 'us'],
#                         nationality    => ['de', 'gb'],
#                         citizen        => ['ru'],
#                         postal_code    => ['123321'],
#                         national_id    => ['321123'],
#                         passport_no    => ['asdffdsa'],
#                     }]
#             },
#         };

subtest 'Class constructor' => sub {
    my $validator;
    like exception { $validator = Data::Validate::Sanctions::Redis->new() }, qr/Redis read connection is missing/,
        'Correct error for missing redis-read';

    is exception { $validator = Data::Validate::Sanctions::Redis->new(redis_read => $redis) }, undef,
        'Successfully created the object with redis-read object';

    is_deeply $validator->{_data}, undef, 'There is no sanction data';
};

subtest 'Update Data' => sub {
    my $mock_fetcher = Test::MockModule->new('Data::Validate::Sanctions::Fetcher');
    my $mock_data    = {
        'EU-Sanctions' => {
            updated => 90,
            content => []}};
    $mock_fetcher->redefine(run => sub { return clone($mock_data) });

    clear_redis();
    set_fixed_time(1500);
    my $validator = Data::Validate::Sanctions::Redis->new(redis_read => $redis);
    like exception { $validator->update_data(verbose => 1) }, qr/Redis write connection is missing/, 'Redis-write is required for updating';

    # load and save into redis
    $validator = Data::Validate::Sanctions::Redis->new(
        redis_read  => $redis,
        redis_write => $redis
    );
    $validator->update_data();
    my $expected = {
        'EU-Sanctions' => {
            content => [],
            updated => 90
        },
        'HMT-Sanctions'     => {},
        'OFAC-Consolidated' => {},
        'OFAC-SDN'          => {},
    };
    is_deeply $validator->{_data}, $expected, 'Data is correctly loaded';
    check_redis_content('EU-Sanctions',      $mock_data->{'EU-Sanctions'}, 1500);
    check_redis_content('HMT-Sanctions',     {},                           1500);
    check_redis_content('OFAC-Consolidated', {},                           1500);
    check_redis_content('OFAC-SDN',          {},                           1500);

    # rewrite to redis if update (publish) time is changed
    set_fixed_time(1600);
    $mock_data->{'EU-Sanctions'}->{updated} = 91;
    $validator->update_data();
    $expected->{'EU-Sanctions'}->{updated} = 91;
    is_deeply $validator->{_data}, $expected, 'Data is loaded with new update time';
    check_redis_content('EU-Sanctions', $mock_data->{'EU-Sanctions'}, 1600, 'Redis content changed by increased update time');

    # don't rewrite if there is an error - just update verified time
    set_fixed_time(1700);
    $mock_data->{'EU-Sanctions'}->{error} = 'Test error';
    $mock_data->{'EU-Sanctions'}->{updated} = 92;
    $mock_data->{'EU-Sanctions'}->{content} = [1,2,3];
    warning {$validator->update_data()}, qr/EU-Sanctions list update failed because: Test error/, 'Error warning appears in logs';
    $expected->{'EU-Sanctions'}->{error} = 'Test error';
    is_deeply $validator->{_data}, $expected, 'Data is not changed if there is error';
    $mock_data->{'EU-Sanctions'}->{updated} = 91; # this is not updated because of the error
    $mock_data->{'EU-Sanctions'}->{content} = [];
    check_redis_content('EU-Sanctions', $mock_data->{'EU-Sanctions'}, 1600, 'Redis content changed by increased update time');
};

my $validator = Data::Validate::Sanctions::Redis->new(
    redis_read  => $redis,
    redis_write => $redis
);

ok !$validator->is_sanctioned(qw(sergei ivanov)),                      "Sergei Ivanov not is_sanctioned";
ok $validator->is_sanctioned(qw(tmpa)),                                "now sanction file is tmpa, and tmpa is in test1 list";
ok !$validator->is_sanctioned("Mohammad reere yuyuy", "wqwqw  qqqqq"), "is not in test1 list";
ok $validator->is_sanctioned("Zaki", "Ahmad"),                         "is in test1 list - searched without dob";
ok $validator->is_sanctioned("Zaki", "Ahmad", '1999-01-05'),           'the guy is sanctioned when dob year is matching';
ok $validator->is_sanctioned("atom", "test", '1999-01-05'),            "Match correctly with one world name in sanction list";

is_deeply $validator->get_sanctioned_info("Zaki", "Ahmad", '1999-01-05'),
    {
    'comment'      => undef,
    'list'         => 'test1',
    'matched'      => 1,
    'matched_args' => {
        'dob_year' => 1999,
        'name'     => 'Zaki Izzat Zaki AHMAD'
    }
    },
    'Sanction info is correct';
ok $validator->is_sanctioned("Ahmad", "Ahmad", '1999-10-10'), "is in test1 list";

is_deeply $validator->get_sanctioned_info("TMPA"),
    {
    'comment'      => undef,
    'list'         => 'test1',
    'matched'      => 1,
    'matched_args' => {'name' => 'TMPA'}
    },
    'Sanction info is correct';

is_deeply $validator->get_sanctioned_info('Donald', 'Trump', '1999-01-05'),
    {
    'comment'      => 'dob raw text: circa-1951',
    'list'         => 'test1',
    'matched'      => 1,
    'matched_args' => {'name' => 'Donald Trump'}
    },
    "When client's name matches a case with dob_text";

is_deeply $validator->get_sanctioned_info('Bandit', 'Outlaw', '1999-01-05'),
    {
    'comment'      => undef,
    'list'         => 'test1',
    'matched'      => 1,
    'matched_args' => {'name' => 'Bandit Outlaw'}
    },
    "If optional ares are empty, only name is matched";

my $args = {
    first_name     => 'Bandit',
    last_name      => 'Outlaw',
    place_of_birth => 'Iran',
    residence      => 'France',
    nationality    => 'Germany',
    citizen        => 'Russia',
    postal_code    => '123321',
    national_id    => '321123',
    passport_no    => 'asdffdsa',
};

is_deeply $validator->get_sanctioned_info($args),
    {
    'comment'      => undef,
    'list'         => 'test1',
    'matched'      => 1,
    'matched_args' => {
        name           => 'Bandit Outlaw',
        place_of_birth => 'ir',
        residence      => 'fr',
        nationality    => 'de',
        citizen        => 'ru',
        postal_code    => '123321',
        national_id    => '321123',
        passport_no    => 'asdffdsa',
    }
    },
    "All matched fields are returned";

for my $field (qw/place_of_birth residence nationality citizen postal_code national_id passport_no/) {
    is_deeply $validator->get_sanctioned_info({%$args, $field => 'Israel'}),
        {'matched' => 0}, "A single wrong field will result in mismatch - $field";

    my $expected_result = {
        'list'         => 'test1',
        'matched'      => 1,
        'matched_args' => {
            name           => 'Bandit Outlaw',
            place_of_birth => 'ir',
            residence      => 'fr',
            nationality    => 'de',
            citizen        => 'ru',
            postal_code    => '123321',
            national_id    => '321123',
            passport_no    => 'asdffdsa',
        },
        comment => undef,
    };

    delete $expected_result->{matched_args}->{$field};
    is_deeply $validator->get_sanctioned_info({%$args, $field => undef}), $expected_result, "Missing optional args are ignored - $field";
}

sub clear_redis {
    for my $key ($redis->keys('SANCTIONS::*')->@*) {
        $redis->del($key);
    }
}

sub check_redis_content {
    my ($source_name, $config, $verified_time, $comment) = @_;

    my %stored = $redis->hgetall("SANCTIONS::$source_name")->@*;
    $stored{content} = decode_json_utf8($stored{content});
    is_deeply \%stored,
        {
        content   => $config->{content} // [],
        published => $config->{updated} // 0,
        error     => $config->{error} // '',
        verified  => $verified_time,
        },
        $comment // "Redis content is correct for $source_name";
}

done_testing;
