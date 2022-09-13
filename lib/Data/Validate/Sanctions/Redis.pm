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

our $VERSION = '0.1';

# for OO
sub new {    ## no critic (RequireArgUnpacking)
    my ($class, %args) = @_;

    my $self = {};
    $self->{redis_read} = $args{redis_read} or 'Redis read connection is missing';
    $self->{redis_write} = $args{redis_write} or 'Redis write connection is missing';

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
    my $self = shift;
    unless ($self) {
        die 'This method should be called on an object';
    }

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
        my $updated = $redis_read->hget("SANCTIONS::$source", 'updated') // 0;
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

    for my $source ($self->{sources}->@*) {
        $self->{redis_write}->hmset(
            "SANCTIONS::$source", 
            'updated', $self->{_data}->{$source}->{updated}, 
            'content', encode_json_utf8($self->{_data}->{$source}->{content}),
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

Data::Validate::Sanctions - Validate a name against sanctions lists

=head1 SYNOPSIS

    # as exported function
    use Data::Validate::Sanctions qw/is_sanctioned get_sanction_file set_sanction_file/;
    set_sanction_file('/var/storage/sanction.csv');

    my ($first_name, $last_name) = ("First", "Last Name");
    print 'BAD' if is_sanctioned($first_name, $last_name);

    # as OO
    use Data::Validate::Sanctions;

    #You can also set sanction_file in the new method.
    my $validator = Data::Validate::Sanctions->new(sanction_file => '/var/storage/sanction.csv');
    print 'BAD' if $validator->is_sanctioned("$last_name $first_name");

=head1 DESCRIPTION

Data::Validate::Sanctions is a simple validitor to validate a name against sanctions lists.

The list is from:
- L<https://www.treasury.gov/ofac/downloads/sdn.csv>,
- L<https://www.treasury.gov/ofac/downloads/consolidated/cons_prim.csv>
- L<https://ofsistorage.blob.core.windows.net/publishlive/ConList.csv>
- L<https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=$eu_token>

run F<update_sanctions_csv> to update the bundled csv.

The path of list can be set by function L</set_sanction_file> or by method L</new>. If not set, then environment variable $ENV{SANCTION_FILE} will be checked, at last
the default file in this package will be used.

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

    my $result =get_sanctioned_info($last_name, $first_name, $date_of_birth);
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

Create the object, and set sanction_file

    my $validator = Data::Validate::Sanctions->new(sanction_file => '/var/storage/sanction.csv');

=head2 get_sanction_file

get sanction_file which is used by L</is_sanctioned> (procedure-oriented)

=head2 set_sanction_file

set sanction_file which is used by L</is_sanctioned> (procedure-oriented)

=head2 _name_matches

Pass in the client's name and sanctioned individual's name to see if they are similar or not

=head1 AUTHOR

Binary.com E<lt>fayland@binary.comE<gt>

=head1 COPYRIGHT

Copyright 2014- Binary.com

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Data::OFAC>

=cut
