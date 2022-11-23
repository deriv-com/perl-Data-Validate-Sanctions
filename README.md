## is\_sanctioned

Checks if the input profile info matches a sanctioned entity.
The arguments are the same as those of **get\_sanctioned\_info**.

It returns 1 if a match is found, otherwise 0.

## \_match\_other\_fields

Matches fields possibly available in addition to name and date of birth.

Returns a a hash-ref reporting the matched fields if it succeeeds; otherwise returns false (undef).

## get\_sanctioned\_info

Tries to find a match a sanction entry matching the input profile args.
It takes arguments in two forms. In the new API, it takes a hashref containing the following named arguments:

- first\_name: first name
- last\_name: last name
- date\_of\_birth: (optional) date of birth as a string or epoch
- place\_of\_birth: (optional) place of birth as a country name or code
- residence: (optional) name or code of the country of residence
- nationality: (optional) name or code of the country of nationality
- citizen: (optional) name or code of the country of citizenship
- postal\_code: (optional) postal/zip code
- national\_id: (optional) national ID number
- passport\_no: (oiptonal) passort number

For backward compatibility it also supports the old API, taking the following args:

- first\_name: first name
- last\_name: last name
- date\_of\_birth: (optional) date of birth as a string or epoch

It returns a hash-ref containg the following data:

- - matched:      1 if a match was found; 0 otherwise
- - list:         the source for the matched entry,
- - matched\_args: a name-value hash-ref of the similar arguments,
- - comment:      additional comments if necessary,

## \_index\_data

Indexes data by name. Each name may have multiple matching entries.

# NAME

Data::Validate::Sanctions - Validate a name against sanctions lists

# SYNOPSIS

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

# DESCRIPTION

Data::Validate::Sanctions is a simple validitor to validate a name against sanctions lists.

The list is from:
\- [https://www.treasury.gov/ofac/downloads/sdn.csv](https://www.treasury.gov/ofac/downloads/sdn.csv),
\- [https://www.treasury.gov/ofac/downloads/consolidated/cons\_prim.csv](https://www.treasury.gov/ofac/downloads/consolidated/cons_prim.csv)
\- [https://ofsistorage.blob.core.windows.net/publishlive/ConList.csv](https://ofsistorage.blob.core.windows.net/publishlive/ConList.csv)
\- [https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList\_1\_1/content?token=$eu\_token](https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content?token=$eu_token)

run `update_sanctions_csv` to update the bundled csv.

The path of list can be set by function ["set\_sanction\_file"](#set_sanction_file) or by method ["new"](#new). If not set, then environment variable $ENV{SANCTION\_FILE} will be checked, at last
the default file in this package will be used.

# METHODS

## is\_sanctioned

    is_sanctioned($last_name, $first_name);
    is_sanctioned($first_name, $last_name);
    is_sanctioned("$last_name $first_name");

when one string is passed, please be sure last\_name is before first\_name.

or you can pass first\_name, last\_name (last\_name, first\_name), we'll check both "$last\_name $first\_name" and "$first\_name $last\_name".

retrun 1 if match is found and 0 if match is not found.

It will remove all non-alpha chars and compare with the list we have.

## get\_sanctioned\_info

    my $result =get_sanctioned_info($last_name, $first_name, $date_of_birth);
    print 'match: ', $result->{matched_args}->{name}, ' on list ', $result->{list} if $result->{matched};

return hashref with keys:
    **matched**      1 or 0, depends if name has matched
    **list**         name of list matched (present only if matched)
    **matched\_args** The list of arguments matched (name, date of birth, residence, etc.)

It will remove all non-alpha chars and compare with the list we have.

## update\_data

Fetches latest versions of sanction lists, and updates corresponding sections of stored file, if needed

## last\_updated

Returns timestamp of when the latest list was updated.
If argument is provided - return timestamp of when that list was updated.

## new

Create the object, and set sanction\_file

    my $validator = Data::Validate::Sanctions->new(sanction_file => '/var/storage/sanction.csv');

## get\_sanction\_file

get sanction\_file which is used by ["is\_sanctioned"](#is_sanctioned) (procedure-oriented)

## set\_sanction\_file

set sanction\_file which is used by ["is\_sanctioned"](#is_sanctioned) (procedure-oriented)

## \_name\_matches

Pass in the client's name and sanctioned individual's name to see if they are similar or not

## export\_data

Exports the sanction lists to a local file in YAML format.

## data

Gets the sanction list content with lazy loading.

# AUTHOR

Binary.com <fayland@binary.com>

# COPYRIGHT

Copyright 2014- Binary.com

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[Data::OFAC](https://metacpan.org/pod/Data%3A%3AOFAC)
