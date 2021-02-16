package Data::Validate::Sanctions::Fetcher;

use strict;
use warnings;

use DateTime::Format::Strptime;
use Date::Utility;
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use List::Util qw(uniq any);
use Mojo::UserAgent;
use Text::CSV;
use Text::Trim qw(trim);
use Syntax::Keyword::Try;
use XML::Fast;

our $VERSION = '0.10';

=head2 config

Creastes a hash-ref of sanction source configuration, including their url, description and parser callback.
It accepts the following list of named args:

=over 4

=item B<-eu_token>: required if B<eu_url> is empty

The token required for accessing EU sanctions (usually added as an arg to URL).

=item <eu_url>: required if B<eu_token> is empty

EU Sanctions full url, token included.

=item B<ofac_sdn_url>: optional

OFAC-SDN download url.

=item B<ofac_consolidated_url>: optional

OFAC Consilidated download url.

=item B<hmt_url>: optional

MHT Sanctions download url.

=back

=cut

sub config {
    my %args = @_;

    my $eu_token = $args{eu_token} // $ENV{EU_SANCTIONS_TOKEN};
    my $eu_url   = $args{eu_url}   // $ENV{EU_SANCTIONS_URL};

    warn 'EU Sanctions will fail whithout eu_token or eu_url' unless $eu_token or $eu_url;

    if ($eu_token) {
        $eu_url //= "https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=$eu_token";
    }

    return {
        # 'OFAC-SDN' => {
        #     description => 'TREASURY.GOV: Specially Designated Nationals List with a.k.a included',
        #     url         => $args{ofac_sdn_url}
        #         // 'https://www.treasury.gov/ofac/downloads/sdn_xml.zip',    #let's be polite and use zippped version of this 7mb+ file
        #     parser => \&_ofac_xml_zip,
        # },
        # 'OFAC-Consolidated' => {
        #     description => 'TREASURY.GOV: Consolidated Sanctions List Data Files',
        #     url         => $args{ofac_consolidated_url} // 'https://www.treasury.gov/ofac/downloads/consolidated/consolidated.xml',
        #     parser      => \&_ofac_xml,
        # },
        'HMT-Sanctions' => {
            description => 'GOV.UK: Financial sanctions: consolidated list of targets',
            url         => $args{hmt_url} // 'https://ofsistorage.blob.core.windows.net/publishlive/ConList.csv',
            parser      => \&_hmt_csv,
        },
        # 'EU-Sanctions' => {
        #     description => 'EUROPA.EU: Consolidated list of persons, groups and entities subject to EU financial sanctions',
        #     url         => $eu_url,
        #     parser      => \&_eu_xml,
        # },
    };
}

#
# Parsers - returns timestamp of last update and arrayref of names
#

sub _process_name {
    my $r = join ' ', @_;
    $r =~ s/^\s+|\s+$//g;
    return $r;
}

sub _ofac_xml_zip {
    my $content = shift;
    my $output;
    unzip \$content => \$output or die "unzip failed: $UnzipError\n";
    return _ofac_xml($output);
}

sub _date_to_epoch {
    my $date = shift;

    $date = "$3-$2-$1" if $date =~ m/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/;

    return eval { Date::Utility->new($date)->epoch; };
}

sub _process_name_and_dob {
    my ($name_list, $dob_list, $dataset) = @_;

    my (@epoch_list, @year_list, @other_list);

    for my $dob (@$dob_list) {
        $dob =~ s/^\s+|\s+$//g;
        next unless $dob;

        $dob =~ s/[ \/]/-/g;
        #dobs with month = day = 0 are converted to year.
        if ($dob =~ m/^(\d{1,2})-(\d{1,2})-(\d{4})$/) {
            $dob = $3 if $1 == 0 or $2 == 0;
        } elsif ($dob =~ m/^(\d{4})-(\d0{1,2})-(\d{1,2})$/) {
            $dob = $1 if $2 == 0 or $3 == 0;
        }
        $dob = $1 if $dob =~ m/^[A-Z][a-z]{2}-(\d{4})$/;

        if ($dob =~ m/^\d{4}$/) {
            push @year_list, $dob;
        } elsif ($dob =~ m/(\d{4}).*to.*(\d{4})$/) {
            push @year_list, ($1 .. $2);
        } else {
            my $epoch = _date_to_epoch($dob);
            (defined $epoch) ? push(@epoch_list, $epoch) : push(@other_list, $dob);
        }
    }

    for my $name (@$name_list) {
        # some names contain comma
        $name =~ s/,//g;

        $dataset->{$name}->{$_} //= [] for qw(dob_epoch dob_year dob_text);
        push @{$dataset->{$name}->{dob_epoch}}, @epoch_list;
        push @{$dataset->{$name}->{dob_year}},  @year_list;
        push @{$dataset->{$name}->{dob_text}},  @other_list;
        $dataset->{$name}->{dob_epoch} = [uniq $dataset->{$name}->{dob_epoch}->@*];
        $dataset->{$name}->{dob_year}  = [uniq $dataset->{$name}->{dob_year}->@*];
        $dataset->{$name}->{dob_text}  = [uniq $dataset->{$name}->{dob_text}->@*];
        for (qw(dob_epoch dob_year dob_text)) {
            delete $dataset->{$name}->{$_} unless $dataset->{$name}->{$_}->@*;
        }
    }

    return $dataset;
}

sub _ofac_xml {
    my $content = shift;

    my $ref = xml2hash($content, array => ['aka'])->{sdnList};

    my $publish_epoch =
        $ref->{publshInformation}{Publish_Date} =~ m/(\d{1,2})\/(\d{1,2})\/(\d{4})/
        ? _date_to_epoch("$3-$1-$2")
        : undef;    # publshInformation is a typo in ofac xml tags
    die 'Publication date is invalid' unless defined $publish_epoch;
    
    my $parse_list_node = sub {
        my ($entry, $parent, $child, $attribute) = @_;
        
         my $node = $entry->{$parent}->{$child} // [];
            $node = [$node] if (ref $node eq 'HASH');
    
            return map { $_->{$attribute} // () } @$node;
    };

    my $ofac_ref = {};

    foreach my $entry (@{$ref->{sdnEntry}}) {
        next unless $entry->{sdnType} eq 'Individual';

        my @names;
        push @names, _process_name($_->{firstName} // '', $_->{lastName} // '') for ($entry, @{$entry->{akaList}{aka} // []});

        # my @dob_list;
        # my $dobs = $entry->{dateOfBirthList}{dateOfBirthItem};
        # # In one of the xml files, some of the clients have more than one date of birth
        # # Hence, $dob can be either an array or a hashref
        # foreach my $dob (map { $_->{dateOfBirth} || () } (ref($dobs) eq 'ARRAY' ? @$dobs : $dobs)) {
        #     push @dob_list, $dob;
        # }
        my @dob_list = $parse_list_node->($entry, 'dateOfBirthList', 'dateOfBirthItem', 'dateOfBirth');
        my @citizen = $parse_list_node->($entry, 'citizenshipList', 'citizenship', 'country');
        my @residence = $parse_list_node->($entry, 'addressList', 'address', 'country');
        my @postal_code = $parse_list_node->($entry, 'addressList', 'address', 'postalCode');
        my @nationality = $parse_list_node->($entry, 'naationalityList', 'nationality', 'country');
        my @birth_place = $parse_list_node->($entry, 'placeOfBirthList', 'placeOfBirthItem', 'placeOfBirth');
        @birth_place = map {my @parts = split ',', $_; $parts[-1] } @birth_place;
        
        # Passport id and national id are also available
        
        _process_name_and_dob(\@names, \@dob_list, $ofac_ref);
    }

    return {
        updated    => $publish_epoch,
        names_list => $ofac_ref,
    };
}

sub _hmt_csv {
    my $content = shift;
    my $hmt_ref = {};

    my $csv = Text::CSV->new({binary => 1}) or die "Cannot use CSV: " . Text::CSV->error_diag();

    my @lines = split("\n", $content);

    my $line = trim(shift @lines);
    my $parsed = $csv->parse($line);
    my @info = $parsed ? $csv->fields() : ();
    use Data::Dumper; warn Dumper \@info;
    die 'Publish date is invalid' unless @info && _date_to_epoch($info[1]);
    
    $line = trim(shift @lines);
    $parsed = $csv->parse($line);
    my @row = $csv->fields();
    use Data::Dumper; warn Dumper \@row;
    my %column = map { trim($row[$_]) => $_} (0 .. $#row);;
    
    return;
    foreach (@lines) {
        s/^\s+|\s+$//g;

        $parsed = $csv->parse($_);
        next unless $parsed;

        @row = $csv->fields();
        
        my $row = \@row;
        ($row->[$column{'Group Type'}] eq "Individual") or next;
        my $name = _process_name @{$row}[0 .. 5];

        next if $name =~ /^\s*$/;

        my $date_of_birth = $row->[$column{'DOB'}];
        my $birth_place = $row->[$column{'Country of Birth'}];
        my $nationality = $row->[$column{'Nationality'}];
        my $residence = $row->[$column{'Country'}];
        my $postal_code = $row->[$column{'Post/Zip Code'}]; 
        my $national_id = $row->[$column{'NI Number'}];

        _process_name_and_dob([$name], [$date_of_birth], $hmt_ref);
    }

    my $publish_epoch = _date_to_epoch($info[1]);
    die 'Publication date is invalid' unless defined $publish_epoch;

    return {
        updated    => $publish_epoch,
        names_list => $hmt_ref,
    };
}

sub _eu_xml {
    my $content = shift;
    my $ref     = xml2hash($content, array => ['nameAlias', 'birthdate'])->{export};
    my $eu_ref  = {};

    foreach my $entry (@{$ref->{sanctionEntity}}) {
        next unless $entry->{subjectType}->{'-code'} eq 'person';

        my @names;
        for (@{$entry->{nameAlias} // []}) {
            my $name = $_->{'-wholeName'};
            $name = join ' ', ($_->{'-firstName'} // '', $_->{'-lastName'} // '') unless $name;
            push @names, $name if $name ne ' ';
        }

        my @dob_list;
        foreach my $dob ($entry->{birthdate}->@*) {
            push @dob_list, $dob->{'-birthdate'} if $dob->{'-birthdate'};
            push @dob_list, $dob->{'-year'} if not $dob->{'-birthdate'} and $dob->{'-year'};
        }
        
        my @birth_place = map { $_->{'-countryDescription'} || () } $entry->{birthdate}->@*;
        my @citizen =  map { $_->{'-countryDescription'} || () } $entry->{citizenship}->@*;
        my @residence =  map { $_->{'-countryDescription'} || () } $entry->{address}->@*;
        my @postal_code = map { $_->{'-zipCode'} || $_->{'-poBox'} || () } $entry->{address}->@*;
        my @nationality =  map { $_->{'-countryDescription'} || () } $entry->{identification}->@*;
        my @national_id = map { $_->{'-identificationTypeCode'} eq 'id'? $_->{'-number'} || () : () } $entry->{identification}->@*;
        my @passport_no = map { $_->{'-identificationTypeCode'} eq 'passport'? $_->{'-number'} || () : () } $entry->{identification}->@*;

        _process_name_and_dob(\@names, \@dob_list, $eu_ref);
    }

    my @date_parts = split('T', $ref->{'-generationDate'} // '');
    my $publish_epoch = _date_to_epoch($date_parts[0] // '');

    die 'Publication date is invalid' unless $publish_epoch;

    return {
        updated    => $publish_epoch,
        names_list => $eu_ref,
    };
}

=head2 run

Fetches latest version of lists, and returns combined hash of successfully downloaded ones

=cut

sub run {
    my %args = @_;

    my $h  = {};
    my $ua = Mojo::UserAgent->new;
    $ua->connect_timeout(15);

    my $config = config(%args);

    foreach my $id (sort keys %$config) {
        my $d = $config->{$id};
        try {
            die "Url is empty for $id" unless $d->{url};

            my $content;

            if ($d->{url} =~ m/^file:\/\/(.*)$/) {
                open my $fh, '<', "$1" or die "Can't open $id file $1 $!";
                $content = do { local $/; <$fh> };
                close $fh;
            } else {
                die "File not downloaded for $d->{id}" if $ua->get($d->{url})->result->is_error;
                $content = $ua->get($d->{url})->result->body;
            }

            my $r = $d->{parser}->($content);

            $h->{$id} = $r if ($r->{updated} > 1);
        }
        catch {
            warn "$id list update failed: $@";
        }
    }

    return $h;
}

1;
