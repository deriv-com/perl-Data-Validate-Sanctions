package Data::Validate::Terrorist;

use strict;
use 5.008_005;
our $VERSION = '0.01';

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/is_terrorist/;

use Carp;

sub is_terrorist {
    my $self = shift if ref($_[0]); # OO
    my $name = shift;

    $name = uc($name);
    $name =~ s/[[:^alpha:]]//g;

    my @data = __load_data();
    return (grep { $_ eq $name } @data) ? 1 : 0;
}

my @__data;
sub __load_data {
    return @__data if @__data;

    my $file = __FILE__;
    $file =~ s/\.pm/\.csv/;
    open(my $fh, '<', $file) or croak "Can't find $file, please re-install the module.\n";
    @__data = <$fh>;
    close($fh);

    chomp(@__data);
    @__data;
}

1;
__END__

=encoding utf-8

=head1 NAME

Data::Validate::Terrorist - Validate a name against terrorist lists

=head1 SYNOPSIS

  use Data::Validate::Terrorist;

=head1 DESCRIPTION

Data::Validate::Terrorist is

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
