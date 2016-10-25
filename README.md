[![Build Status](https://travis-ci.org/binary-com/perl-Data-Validate-Sanctions.svg?branch=master)](https://travis-ci.org/binary-com/perl-Data-Validate-Sanctions)
[![codecov](https://codecov.io/gh/binary-com/perl-Data-Validate-Sanctions/branch/master/graph/badge.svg)](https://codecov.io/gh/binary-com/perl-Data-Validate-Sanctions)

# NAME

Data::Validate::Sanctions - Validate a name against sanctions lists

# SYNOPSIS

    # as exported function
    use Data::Validate::Sanctions qw/is_sanctioned/;

    print 'BAD' if is_sanctioned($first_name, $last_name);

    # as OO
    use Data::Validate::Sanctions;

    my $validator = Data::Validate::Sanctions->new;
    print 'BAD' if $validator->is_sanctioned("$last_name $first_name");

# DESCRIPTION

Data::Validate::Sanctions is a simple validitor to validate a name against sanctions lists.

The list is from [http://www.treasury.gov/ofac/downloads/sdn.csv](http://www.treasury.gov/ofac/downloads/sdn.csv), [http://www.treasury.gov/resource-center/sanctions/Terrorism-Proliferation-Narcotics/Documents/plc_prim.csv](http://www.treasury.gov/resource-center/sanctions/Terrorism-Proliferation-Narcotics/Documents/plc_prim.csv), [http://www.treasury.gov/ofac/downloads/fse/fse_prim.csv](http://www.treasury.gov/ofac/downloads/fse/fse_prim.csv)

run [update_sanctions_csv](https://metacpan.org/pod/update_sanctions_csv) to update the bundled csv.

# METHODS

## is\_sanctioned

    is_sanctioned($last_name, $first_name);
    is_sanctioned($first_name, $last_name);
    is_sanctioned("$last_name $first_name");

when one string is passed, please be sure last\_name is before first\_name.

or you can pass first\_name, last\_name (last\_name, first\_name), we'll check both "$last\_name $first\_name" and "$first\_name $last\_name".

return 1 for yes, 0 for no.

it will remove all non-alpha chars and compare with the list we have.

# AUTHOR

Binary.com <fayland@binary.com>

# COPYRIGHT

Copyright 2014- Binary.com

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[Data::OFAC](https://metacpan.org/pod/Data::OFAC)
