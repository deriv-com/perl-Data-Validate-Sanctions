package Data::Validate::Sanctions;

use strict;
use 5.008_005;
our $VERSION = '0.05';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw/is_sanctioned/;

use Carp;
use File::stat;

our $sanction_file = $ENV{SANCTION_FILE};
unless ($sanction_file) {
    $sanction_file = __FILE__;
    $sanction_file =~ s/\.pm/\.csv/;
}

my $last_time = 0;

sub is_sanctioned {
    my $self = shift if ref($_[0]);    # OO

    my $name = join('', @_);
    $name = uc($name);
    $name =~ s/[[:^alpha:]]//g;

    my @data = __load_data();
    return 1 if grep { $_ eq $name } @data;

    # try reverse
    if (@_ > 1) {
        $name = join('', reverse @_);
        $name = uc($name);
        $name =~ s/[[:^alpha:]]//g;
        return 1 if grep { $_ eq $name } @data;
    }

    return 0;
}

my @__data;

sub __load_data {
    my $stat = stat($sanction_file) or croak "Can't get stat of file $sanction_file, please check it.\n";
    return @__data if ($stat->mtime <= $last_time && @__data);

    open(my $fh, '<', $sanction_file) or croak "Can't open file $sanction_file, please check it.\n";
    @__data = <$fh>;
    close($fh);
    chomp(@__data);
    $last_time = $stat->mtime;
    @__data;
}

# for OO
sub new {
    my $class = shift;
    my %args  = @_;
    $sanction_file = $args{sanction_file} if exists $args{sanction_file};
    return bless {}, ref($class) || $class;
}

1;
__END__

=encoding utf-8

=head1 NAME

Data::Validate::Sanctions - Validate a name against sanctions lists

=head1 SYNOPSIS

    # as exported function
    use Data::Validate::Sanctions qw/is_sanctioned/;
    # You can set sanction file in $ENV{SANCTION_FILE} or like this:
    #$Data::Validate::Sanctions::sanction_file = '/var/storage/sanction.csv';

    print 'BAD' if is_sanctioned($first_name, $last_name);

    # as OO
    use Data::Validate::Sanctions;

    #You can also set sanction_file in the new method.
    my $validator = Data::Validate::Sanctions->new(sanction_file => '/var/storage/sanction.csv');
    print 'BAD' if $validator->is_sanctioned("$last_name $first_name");

=head1 DESCRIPTION

Data::Validate::Sanctions is a simple validitor to validate a name against sanctions lists.

The list is from L<https://www.treasury.gov/ofac/downloads/sdn.csv>, L<https://www.treasury.gov/ofac/downloads/consolidated/cons_prim.csv>

run L<update_sanctions_csv> to update the bundled csv.

=head1 METHODS

=head2 is_sanctioned

    is_sanctioned($last_name, $first_name);
    is_sanctioned($first_name, $last_name);
    is_sanctioned("$last_name $first_name");

when one string is passed, please be sure last_name is before first_name.

or you can pass first_name, last_name (last_name, first_name), we'll check both "$last_name $first_name" and "$first_name $last_name".

return 1 for yes, 0 for no.

it will remove all non-alpha chars and compare with the list we have.

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
