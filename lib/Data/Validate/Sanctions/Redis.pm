package Data::Validate::Sanctions::Redis;

use strict;
use warnings;

use parent 'Data::Validate::Sanctions';

use Carp;
use Data::Validate::Sanctions::Fetcher;
use Scalar::Util qw(blessed);
use Date::Utility;
use Data::Compare;
use List::Util qw(any uniq max min);
use Locale::Country;
use Text::Trim qw(trim);
use JSON::MaybeUTF8 qw(encode_json_utf8 decode_json_utf8);

our $VERSION = '0.13';

my $instance;

sub new {
    my ($class, %args) = @_;

    return $instance if $instance;

    my $self = {};
    $self->{redis_read} = $args{redis_read} or die 'Redis read connection is missing';
    $self->{redis_write} = $args{redis_write} or die 'Redis write connection is missing';

    $self->{sources} = [keys Data::Validate::Sanctions::Fetcher::config(eu_token => 'dummy')->%*];

    $self->{args} = {%args};

    $self->{last_time} = 0;
    return bless $self, ref($class) || $class;
}

sub last_updated {
    my $self = shift;
    my $list = shift;

    if ($list) {
        return $self->{_data}->{$list}->{updated};
    } else {
        $self->_load_data();
        return max(map { $_->{updated} } values %{$self->{_data}});
    }
}

sub set_sanction_file {
    die 'Not applicable';
}

sub get_sanction_file {
    die 'Not applicable';
}

sub get_sanctioned_info {
    my $self = blessed($_[0]) ? shift : $instance;

    die "This function can only be called on an object" unless $self;

    return Data::Validate::Sanctions::get_sanctioned_info($self, @_);
}

sub _load_data {
    my $self                              = shift;

    $self->{last_time}                    //= 0;
    $self->{_data}                        //= {};
    $self->{_sanctioned_name_tokens}      //= {};
    $self->{_token_sanctioned_names}      //= {};
    
    my $last_time;
    for my $source ($self->{sources}->@*) {
        my $updated = $self->{redis_read}->hget("SANCTIONS::$source", 'updated') // 0;
        next if $updated <= $self->{last_time};

        $self->{_data}->{$source}->{content} = decode_json_utf8($self->{redis_read}->hget("SANCTIONS::$source", 'content'));
        $self->{_data}->{$source}->{updated} = $updated;
        $last_time = $updated if $updated > $last_time;
    }
    $self->{_last_time} = $last_time;

    $self->_index_data();

    foreach my $sanctioned_name (keys $self->{_index}->%*) {
        my @tokens = _clean_names($sanctioned_name);
        $self->{_sanctioned_name_tokens}->{$sanctioned_name} = \@tokens;
        foreach my $token (@tokens){
            $self->{_token_sanctioned_names}->{$token}->{$sanctioned_name}=1;
        }
    }

    return $self->{_data};
}

sub _save_data {
    my $self = shift;

    my $now = time;
    for my $source ($self->{sources}->@*) {
        $self->{redis_write}->hmset(
            "SANCTIONS::$source", 
            'updated', $self->{_data}->{$source}->{updated}, 
            'content', encode_json_utf8($self->{_data}->{$source}->{content}),
            'fetched', $now,
            'error',   $self->{_data}->{$source}->{error}
        );
    }

    return;
}

sub _default_sanction_file {
    die 'Not applicable';
}

1;
__END__

=encoding utf-8

=head1 NAME

Data::Validate::Sanctions::Redis - An extention of L<Data::Validate::Sanctions> that stores sanction data in redis rather than a local file.

=head1 SYNOPSIS
    # it only works with OO calls
    use Data::Validate::Sanctions::Redis;

    my $validator = Data::Validate::Sanctions->new(redis_read => $redis_read, redis_write => $redis_write);
    print 'BAD' if $validator->is_sanctioned("$last_name $first_name");

    # In order to update the sanction dataset:
    my $validator = Data::Validate::Sanctions->new(redis_read => $redis_read, redis_write => $redis_write);

    # eu_token or eu_url is required
    $validator->update_data(eu_token => $token);


=head1 DESCRIPTION

Data::Validate::Sanctions::Redis is a simple validitor to validate a name against sanctions lists.
For more details about the sanction sources please refer to L<Data::Validate::Sanctions>.

=head1 METHODS

=head2 is_sanctioned

    is_sanctioned($last_name, $first_name);
    is_sanctioned($first_name, $last_name);
    is_sanctioned("$last_name $first_name");

when one string is passed, please be sure last_name is before first_name.

or you can pass first_name, last_name (last_name, first_name), we'll check both "$last_name $first_name" and "$first_name $last_name".

retrun 1 if match is found and 0 if match is not found.

It will remove all non-alpha chars and compare with the list we have.

=head2 get_sanctioned_info

    my $result = $validator->get_sanctioned_info($last_name, $first_name, $date_of_birth);
    print 'match: ', $result->{matched_args}->{name}, ' on list ', $result->{list} if $result->{matched};

return hashref with keys:
    B<matched>      1 or 0, depends if name has matched
    B<list>         name of list matched (present only if matched)
    B<matched_args> The list of arguments matched (name, date of birth, residence, etc.)

It will remove all non-alpha chars and compare with the list we have.

=head2 update_data

Fetches latest versions of sanction lists, and updates corresponding sections of stored file, if needed

=head2 last_updated

Returns timestamp of when the latest list was updated.
If argument is provided - return timestamp of when that list was updated.

=head2 new

Create the object, and set the redis reader and writer objects:

    my $validator = Data::Validate::Sanctions::Redis->new(redis_read => $redis_read, redis_write => $redis_write);

The validator is a singleton object; so it will always return the same object if it's called for multiple times in a process.

=head2 _name_matches

Pass in the client's name and sanctioned individual's name to see if they are similar or not

=head1 AUTHOR

Binary.com E<lt>fayland@binary.comE<gt>

=head1 COPYRIGHT

Copyright 2022- Binary.com

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Data::Validate::Sanctions>

L<Data::Validate::Sanctions::Fetcher>

=cut
