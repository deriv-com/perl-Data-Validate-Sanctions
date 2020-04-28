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
    my %args               = @_;
    my $eu_sanctions_token = $args{eu_sanctions_token} // $ENV{EU_SANCTIONS_TOKEN};
    my $eu_url   = $args{eu_url} // $ENV{EU_SANCTIONS_URL};

    if ($eu_sanctions_token) {
        $eu_url //=
            "https://webgate.ec.europa.eu/europeaid/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=$eu_sanctions_token";
    }
warn $args{ofac_sdn_url};
    return {
        'OFAC-SDN' => {
            description => 'TREASURY.GOV: Specially Designated Nationals List with a.k.a included',
            url    => $args{ofac_sdn_url} // 'https://www.treasury.gov/ofac/downloads/sdn_xml.zip',    #let's be polite and use zippped version of this 7mb+ file
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

my $circa = 0;
my $month_year = 0;
my $span = 0;
my $failure = 0;
sub _date_to_epoch {
    my $date = shift;
    
    $circa += 1 if $date =~ m/circa/;
    return if $date =~ m/circa/;
    $month_year += 1 if $date =~  m/^[A-Za-z]{1,4}-\d{4}$/;
    return if $date =~ m/^[A-Za-z]{1,4}-\d{4}$/;
    $span += 1 if $date =~ m/-to-/;
    return if $date =~ m/-to-/;
    
    
    
    $date = "$3-$2-$1" if $date =~ m/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/;

    try{
        return Date::Utility->new($date)->epoch;
    }
    catch {
        warn "CVBNDGHGFDGHGDFGHGFDG DATE $date";
    };
    
    warn "INVALID DATE $date";
    warn $date;
    $failure += 1;
}

sub _ofac_xml {
    my $content = shift;

    my @names;
    my $ref = xml2hash($content, array => ['aka'])->{sdnList};
    my $ofac_ref = {};

    foreach my $entry (@{$ref->{sdnEntry}}) {
        next unless $entry->{sdnType} eq 'Individual';

        push @names, _process_name($_->{firstName} // '', $_->{lastName} // '') for ($entry, @{$entry->{akaList}{aka} // []});

        my $dob = $entry->{dateOfBirthList}{dateOfBirthItem};

        # In one of the xml files, some of the clients have more than one date of birth
        # Hence, $dob can be either an array or a hashref
        my @dob_epoch_list;
        my @dob_year_list;

        foreach my $dob (map { $_->{dateOfBirth} || () } (ref($dob) eq 'ARRAY' ? @$dob : $dob)) {
            $dob =~ s/[ \/]/-/g;
            #dobs with month = day = 0 are converted to year.
            $dob = "$1" if $dob =~ m/^0{1,2}-0{1,2}-(\d{4})$/;
            #dobs with missing day of month is converted to year.
            $dob = "$1" if $dob =~ m/^[A-Z][a-z]{2}-(\d{4})$/;

            # Some of the values are only years (ex. '1946')
            # We we save them in a separate list
            if ($dob =~ m/^\d{4}$/) {
                push @dob_year_list, $dob;
            } else {
                my $epoch = _date_to_epoch($dob);
                push @dob_epoch_list, $epoch if defined $epoch;
            }
        }

        for my $name (@names) {
            $ofac_ref->{$name}->{dob_epoch} //= [] if @dob_epoch_list;
            $ofac_ref->{$name}->{dob_year}  //= [] if @dob_year_list;
            push(@{$ofac_ref->{$name}->{dob_epoch}}, $_) for @dob_epoch_list;
            push(@{$ofac_ref->{$name}->{dob_year}},  $_) for @dob_year_list;
        }
    }

    $ref->{publshInformation}{Publish_Date} =~ m/(\d{1,2})\/(\d{1,2})\/(\d{4})/;
    my $publish_epoch = _date_to_epoch("$3-$1-$2");
    die 'Publication date is invalid' unless defined $publish_epoch;

    return {
        updated    => $publish_epoch,
        names_list => $ofac_ref,
    };
}
my $zero_date = 0;
my $empty_dates = 0;
my $total = 0;
sub _hmt_csv {
    my $content = shift;
    my $hmt_ref = {};

    my $csv = Text::CSV->new({binary => 1}) or die "Cannot use CSV: " . Text::CSV->error_diag();

    my @lines = split("\n", $content);
    my @info;
    my $i = 0;
    foreach (@lines) {
        $i++;
        chop;
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
        my $date = $date_of_birth;
        $date_of_birth =~ tr/\//-/;
        my $dob = $date_of_birth;
        if ($date_of_birth =~ m/^(\d{4})-0{1,2}-0{1,2}$/) { $zero_date += 1; $dob = "$1";};
        if ($date_of_birth =~ m/^0{1,2}-0{1,2}-(\d{4})$/){ $zero_date += 1; $dob = "$1";};;
        unless ($date_of_birth) { $empty_dates += 1; };
        $total += 1;
        
        $hmt_ref->{$name}->{dob_epoch} ||= [];
        
        if ($date_of_birth and $date_of_birth !~ m/^(\d{4})-{1,2}-0{1,2}$/ and $date_of_birth !~ m/^0{1,2}-\d{1,2}-(\d{4})$/) {
        # Some DOBs are invalid (Ex. 0-0-1968)
        my $dob_epoch = _date_to_epoch($date_of_birth);
        push @{$hmt_ref->{$name}->{dob_epoch}}, $dob_epoch if defined $dob_epoch;
        }
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

        my @dob_epoch_list;
        my @dob_year_list;

        foreach my $dob ($entry->{birthdate}->@*) {
            my $dob_epoch;
            _date_to_epoch($dob->{'-birthdate'}) if $dob->{'-birthdate'};

            if (defined $dob_epoch) {
                push @dob_epoch_list, $dob_epoch;
            } elsif ($dob->{'-year'}) {
                push @dob_year_list, {year => $dob->{'-year'}};
            }
        }

        foreach my $name (@names) {
            $eu_ref->{$name}->{dob_epoch} //= [] if @dob_epoch_list;
            $eu_ref->{$name}->{dob_year}  //= [] if @dob_year_list;
            push(@{$eu_ref->{$name}->{dob_epoch}}, $_) for @dob_epoch_list;
            push(@{$eu_ref->{$name}->{dob_year}},  $_) for @dob_year_list;
        }

        $count_all += 1;
        $count_without_dob += 1 unless (@dob_epoch_list or @dob_year_list);
    }
    
    my @date_parts = split('T', $ref->{'-generationDate'});
    my $publish_epoch = _date_to_epoch($date_parts[0]);
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
    $args{excluded_sources} //= [];

    my $h  = {};
    my $ua = Mojo::UserAgent->new;
    $ua->connect_timeout(15);

    my @excluded_sources = $args{excluded_sources}->@*;
    my $config           = config(%args);

    foreach my $id (sort keys %$config) {
        next if any { $id eq $_ } @excluded_sources;
        my $d = $config->{$id};
        try {
            die "Url is empty for $id" unless $d->{url};

            my $content;

            if ($d->{url} =~ m/^file:\/\/(.*)$/) {

                open my $fh, '<', "$1" or die "Can't open file $d->{url} $!";
                $content = do { local $/; <$fh> };
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
        
        warn "circa $circa month_year $month_year span $span failures $failure zero dates $zero_date/$total empty_dates $empty_dates";
        $month_year = $span = $failure = $zero_date = $total = $empty_dates = 0;
    }
    
    return $h;
}

1;
