[![Build Status](https://travis-ci.org/binary-com/perl-Data-Validate-Terrorist.svg?branch=master)](https://travis-ci.org/binary-com/perl-Data-Validate-Terrorist)
[![Coverage Status](https://coveralls.io/repos/binary-com/perl-Data-Validate-Terrorist/badge.png?branch=master)](https://coveralls.io/r/binary-com/perl-Data-Validate-Terrorist?branch=master)

# NAME

Data::Validate::Terrorist - Validate a name against terrorist lists

# SYNOPSIS

    # as exported function
    use Data::Validate::Terrorist qw/is_terrorist/;

    print 'BAD' if is_terrorist($name);

    # as OO
    use Data::Validate::Terrorist;

    my $validator = Data::Validate::Terrorist->new;
    print 'BAD' if $validator->is_terrorist($name);

# DESCRIPTION

Data::Validate::Terrorist is a simple validitor to validate a name against terrorist lists.

The list is from [http://www.treasury.gov/ofac/downloads/sdn.csv](http://www.treasury.gov/ofac/downloads/sdn.csv), [http://www.treasury.gov/resource-center/sanctions/Terrorism-Proliferation-Narcotics/Documents/plc_prim.csv](http://www.treasury.gov/resource-center/sanctions/Terrorism-Proliferation-Narcotics/Documents/plc_prim.csv), [http://www.treasury.gov/ofac/downloads/fse/fse_prim.csv](http://www.treasury.gov/ofac/downloads/fse/fse_prim.csv)

run [update_terrorist_csv](https://metacpan.org/pod/update_terrorist_csv) to update the bundled csv.

# METHODS

## is\_terrorist

only accept $name. return 1 for yes, 0 for no.

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
