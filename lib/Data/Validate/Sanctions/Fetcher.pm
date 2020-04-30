package Data::Validate::Sanctions::Fetcher;

use strict;
use warnings;

use DateTime::Format::Strptime;
use Date::Utility;
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use List::Util qw(uniq any);
use Mojo::UserAgent;
use Text::CSV;
use Syntax::Keyword::Try;
use XML::Fast;

our $VERSION = '0.10';

sub config {
    my %args = @_;

    my $eu_sanctions_token = $args{eu_sanctions_token} // $ENV{EU_SANCTIONS_TOKEN};
    my $eu_url             = $args{eu_url}             // $ENV{EU_SANCTIONS_URL};

    warn 'EU Sanctions will fail whithout eu_sanctions_token or eu_url' unless $eu_sanctions_token or $eu_url;

    if ($eu_sanctions_token) {
        $eu_url //= "https://webgate.ec.europa.eu/europeaid/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=$eu_sanctions_token";
    }

    return {
        'OFAC-SDN' => {
            description => 'TREASURY.GOV: Specially Designated Nationals List with a.k.a included',
            url         => $args{ofac_sdn_url}
                // 'https://www.treasury.gov/ofac/downloads/sdn_xml.zip',    #let's be polite and use zippped version of this 7mb+ file
            parser => \&_ofac_xml_zip,
        },
        'OFAC-Consolidated' => {
            description => 'TREASURY.GOV: Consolidated Sanctions List Data Files',
            url         => $args{ofac_consolidated_url} // 'https://www.treasury.gov/ofac/downloads/consolidated/consolidated.xml',
            parser      => \&_ofac_xml,
        },
        'HMT-Sanctions' => {
            description => 'GOV.UK: Financial sanctions: consolidated list of targets',
            url         => $args{hmt_url} // 'https://ofsistorage.blob.core.windows.net/publishlive/ConList.csv',
            parser      => \&_hmt_csv,
        },
        'EU-Sanctions' => {
            description => 'EUROPA.EU: Consolidated list of persons, groups and entities subject to EU financial sanctions',
            url         => $eu_url,
            parser      => \&_eu_xml,
        },
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

    try {
        return Date::Utility->new($date)->epoch;
    }
    catch {
        return undef;
    }
}

sub _process_name_and_dob {
    my ($name_list, $dob_list, $dataset) = @_;

    my (@epoch_list, @year_list);

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
        } elsif (my $epoch = _date_to_epoch($dob)) {
            push @epoch_list, $epoch if defined $epoch;
        }
    }

    for my $name (@$name_list) {
        # some names contain comma
        $name =~ s/,//g;

        $dataset->{$name}->{dob_epoch} //= [] if @epoch_list;
        $dataset->{$name}->{dob_year}  //= [] if @year_list;
        push @{$dataset->{$name}->{dob_epoch}}, @epoch_list;
        push @{$dataset->{$name}->{dob_year}},  @year_list;
        $dataset->{$name}->{dob_epoch} = [uniq $dataset->{$name}->{dob_epoch}->@*];
        $dataset->{$name}->{dob_year}  = [uniq $dataset->{$name}->{dob_year}->@*];
    }
}

sub _ofac_xml {
    my $content = shift;

    my $ref = xml2hash($content, array => ['aka'])->{sdnList};
    
    my $publish_epoch = $ref->{publshInformation}{Publish_Date} =~ m/(\d{1,2})\/(\d{1,2})\/(\d{4})/
      ? _date_to_epoch("$3-$1-$2") : undef;                      # publshInformation is a typo in ofac xml tags
    die 'Publication date is invalid' unless defined $publish_epoch;
    
    my $ofac_ref = {};

    foreach my $entry (@{$ref->{sdnEntry}}) {
        next unless $entry->{sdnType} eq 'Individual';

        my @names;

        push @names, _process_name($_->{firstName} // '', $_->{lastName} // '') for ($entry, @{$entry->{akaList}{aka} // []});

        my $dobs = $entry->{dateOfBirthList}{dateOfBirthItem};

        my @dob_list;
        # In one of the xml files, some of the clients have more than one date of birth
        # Hence, $dob can be either an array or a hashref
        foreach my $dob (map { $_->{dateOfBirth} || () } (ref($dobs) eq 'ARRAY' ? @$dobs : $dobs)) {
            push @dob_list, $dob;
        }

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
    my @info;
    my $i = 0;
    foreach (@lines) {
        $i++;

        s/^\s+|\s+$//g;

        my $status = $csv->parse($_);
        if (1 == $i) {
            @info = $status ? $csv->fields() : ();
            die 'Publish date is invalid' unless @info && _date_to_epoch($info[1]);
        }

        next unless $status;

        my @row = $csv->fields();
        my $row = \@row;
        ($row->[23] and $row->[23] eq "Individual") or next;
        my $name = _process_name @{$row}[0 .. 5];

        next if $name =~ /^\s*$/;

        my $date_of_birth = $row->[7];

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

    my $count_all;
    my $count_without_dob;

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

            my $result = $ua->get($d->{url})->result;

            die "File not downloaded for $d->{url}" if $result->is_error;

            my $r = $d->{parser}->($result->body);

            $h->{$id} = $r if ($r->{updated} > 1);
        }
        catch {
            warn "$id list update failed: $@";
        }
    }

    return $h;
}

1;
