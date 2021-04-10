package Data::TableData::Lookup;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(table_vlookup);

our %SPEC;

$SPEC{table_vlookup} = {
    v => 1.1,
    summary => 'Look up value in a table row by row',
    description => <<'_',

This routine looks up value in a table row by row. It is similar to the
spreadsheet function VLOOKUP, hence the same name being used. It is basically a
glorified map()+grep() that returns a single value (or you can also say it's a
glorified map+L<List::Util>::first()).

Given a table, which is either an array-of-arrayrefs (aoa) or array-of-hashrefs
(aoh), this routine will run through it row by row until it finds the value that
you want. Once found, the value will be returned. Otherwise, undef is returned.

**Exact matching**

The table is expected to be sorted in ascending order by the lookup field. You
specify a lookup value, which will be looked up in the lookup field. Once the
value is found, the result field of the correspending row is returned and lookup
is completed. When the lookup field already exceeds the lookup value, the
routine also concludes that the value is not found, and the lookup is completed.

Example:

    table => [
      {min_income=>      0, tax_rate=>0.13},
      {min_income=>  8_000, tax_rate=>0.18},
      {min_income=> 15_000, tax_rate=>0.22},
      {min_income=> 35_000, tax_rate=>0.30},
      {min_income=> 85_000, tax_rate=>0.39},
      {min_income=>140_000, tax_rate=>0.45},
    ],
    lookup_field => 'min_income',
    lookup_value => 35_000,
    result_field => 'tax_rate',

will result in:

    0.30

while if the lookup_value is 40_000, undef will be returned since it is not
found in any row of the table.

**Approximate matching**

If `approx` option is set to true, once the lookup field in a row exceeds the
lookup value, the result field of the previous row will be returned (if any).
For example, if lookup value is 40_000 then 0.30 will be returned (the row where
`min_income` is 35_000) since the next row has `min_income` of 85_000 which
already exceeds 40_000.

**Interpolation of result**

If, additionally, `interpolate` option is also set to true in addition to
`approx` option being set to true, a linear interpolation will be done when an
exact match fails. In the previous example, when lookup value is 40_000, 0.309
will be returned, which is calculated with:

    0.3 + (40_000 - 35_000)/(85_000 - 35_000)*(0.39 - 0.30)

In the case of there is no next row after `min_income` of 35_000, 0.30 will
still be returned.


_
    args => {
        table => {
            schema => 'array*',
            req => 1,
        },
        lookup_value => {
            summary => 'The value that you want to look up in the lookup field',
            description => <<'_',

Instead of `lookup_value` and `lookup_field`, you can also specify `lookup_code`
instead.

_
            schema => 'any*',
        },

        lookup_field => {
            summary => 'Where to look up the lookup value in',
            description => <<'_',

Either an integer array index (for aoa table) or a string hash key (for aoh
table).

Instead of `lookup_value` and `lookup_field`, you can also specify `lookup_code`
instead.

_
            schema => 'str*',
        },

        lookup_code => {
            summary => 'Supply code to match a row',
            description => <<'_',

Unless what you want to match is custom, you usually specify `lookup_value` and
`lookup_field` instead.

The code will be passed the row (which is an arrayref or a hashref) and
optionally the lookup value too as the second argument if the lookup value is
specified. It is expected to return either -1, 0, 1 like the Perl's `cmp` or
`<=>` operator. -1 means the lookup field is less than the lookup value, 0 means
equal, and 1 means greater than.

With `approx` option not set to true, lookup will succeed once 0 is returned.
With `approx` set to true, lookup will succeed once 0 or 1 is returned.

_
            schema => 'code*',
        },

        result_field => {
            summary => 'Where to get the result from',
            schema => 'str*',
            description => <<'_',

Either an integer array index (for aoa table) or a string hash key (for aoh
table).

_
            req => 1,
        },

        # XXX result_code (instead of result_field)

        approx => {
            summary => 'Whether to do an approximate instead of an exact match',
            schema => 'bool*',
            description => <<'_',

See example in the function description.

_
        },
        interpolate => {
            summary => 'Do a linear interpolation',
            schema => 'bool*',
            description => <<'_',

When this option is set to true, will do a linear interpolation of result when
an exact match is not found. This will only be performed if `approx` is also set
to true.

See example in the function description.

Currently, you cannot use `interpolate` with `lookup_code`.

_
        },
    },
    args_rels => [
        'choose_all&' => [
            [qw/lookup_field lookup_value/],
        ],
        'req_one&' => [
            [qw/lookup_field lookup_code/],
        ],
        'dep_any&' => [
            ['interpolate' => ['approx']],
        ],
    ],
    result_naked => 1,
};
sub table_vlookup {
    my %args = @_;

    my $table        = $args{table};
    my $approx       = $args{approx};
    my $interpolate  = $args{interpolate};
    my $lookup_value = $args{lookup_value};
    my $lookup_field = $args{lookup_field};
    my $lookup_code  = $args{lookup_code};
    my $lookup_value_specified = exists $args{lookup_code};
    my $result_field = $args{result_field};

    my $ref_row;
    my ($matching_row, $prev_row);
    my $result;
  ROW:
    for my $row (@$table) {
        $ref_row = ref $row;

        my $cmp;
        if ($lookup_code) {
            my @lcargs = ($row);
            push @lcargs, $lookup_value if $lookup_value_specified;
            $cmp = $lookup_code->(@lcargs);
        } else {
            if ($ref_row eq 'ARRAY') {
                $cmp = $row->[$lookup_field] <=> $lookup_value;
            } else {
                $cmp = $row->{$lookup_field} <=> $lookup_value;
            }
        }
        if ($cmp == 0) {
            # an exact match
            $matching_row = $row;
            goto GET_EXACT_RESULT;
        } elsif ($cmp == 1) {
            # lookup field has exceeded lookup value
            if ($approx && $prev_row) {
                if ($interpolate) {
                    $matching_row = $row;
                    goto GET_INTERPOLATED_RESULT;
                } else {
                    $matching_row = $prev_row;
                    goto GET_EXACT_RESULT;
                }
            } else {
                # no exact match, not found
                goto RETURN_RESULT;
            }
        } elsif ($cmp == -1) {
            # lookup value has not exceeded lookup value, continue to the next
            # row
        } else {
            die "Something's wrong, cmp is not -1|0|1 ($cmp)";
        }
        $prev_row = $row;
    }

    if ($approx && $prev_row) {
        $matching_row = $prev_row;
        goto GET_EXACT_RESULT;
    } else {
        # not found
        goto RETURN_RESULT;
    }

  GET_EXACT_RESULT: {
        last unless $matching_row; # sanity check
        if ($ref_row eq 'ARRAY') {
            $result = $matching_row->[$result_field];
        } else {
            $result = $matching_row->{$result_field};
        }
        goto RETURN_RESULT;
    }

  GET_INTERPOLATED_RESULT: {
        last unless $matching_row && $prev_row; # sanity check
        my ($x1, $x2, $y1, $y2);
        if ($ref_row eq 'ARRAY') {
            $x1 = $prev_row    ->[$lookup_field];
            $x2 = $matching_row->[$lookup_field];
            $y1 = $prev_row    ->[$result_field];
            $y2 = $matching_row->[$result_field];
        } else {
            $x1 = $prev_row    ->{$lookup_field};
            $x2 = $matching_row->{$lookup_field};
            $y1 = $prev_row    ->{$result_field};
            $y2 = $matching_row->{$result_field};
        }
        $result = $y1 + ($lookup_value - $x1)/($x2-$x1)*($y2-$y1);
    }

  RETURN_RESULT:
    $result;
}

1;
# ABSTRACT: Lookup value in a table data structure

=head1 SYNOPSIS

 use Data::TableData::Lookup qw(
     table_vlookup
 );

 # exact matching
 table_vlookup(
   table => [
     {min_income=>      0, tax_rate=>0.13},
     {min_income=>  8_000, tax_rate=>0.18},
     {min_income=> 15_000, tax_rate=>0.22},
     {min_income=> 35_000, tax_rate=>0.30},
     {min_income=> 85_000, tax_rate=>0.39},
     {min_income=>140_000, tax_rate=>0.45},
   ],
   lookup_field => 'min_income',
   lookup_value => 35_000,
   result_field => 'tax_rate',
 ); # => 0.30

 # exact matching, not found
 table_vlookup(
   table => [
     {min_income=>      0, tax_rate=>0.13},
     {min_income=>  8_000, tax_rate=>0.18},
     {min_income=> 15_000, tax_rate=>0.22},
     {min_income=> 35_000, tax_rate=>0.30},
     {min_income=> 85_000, tax_rate=>0.39},
     {min_income=>140_000, tax_rate=>0.45},
   ],
   lookup_field => 'min_income',
   lookup_value => 40_000,
   result_field => 'tax_rate',
 ); # => undef

 # approximate matching
 table_vlookup(
   table => [
     {min_income=>      0, tax_rate=>0.13},
     {min_income=>  8_000, tax_rate=>0.18},
     {min_income=> 15_000, tax_rate=>0.22},
     {min_income=> 35_000, tax_rate=>0.30},
     {min_income=> 85_000, tax_rate=>0.39},
     {min_income=>140_000, tax_rate=>0.45},
   ],
   lookup_field => 'min_income',
   lookup_value => 40_000,
   result_field => 'tax_rate',
   approx => 1,
 ); # => 0.30

 # approximate matching & interpolated result
 table_vlookup(
   table => [
     {min_income=>      0, tax_rate=>0.13},
     {min_income=>  8_000, tax_rate=>0.18},
     {min_income=> 15_000, tax_rate=>0.22},
     {min_income=> 35_000, tax_rate=>0.30},
     {min_income=> 85_000, tax_rate=>0.39},
     {min_income=>140_000, tax_rate=>0.45},
   ],
   lookup_field => 'min_income',
   lookup_value => 40_000,
   result_field => 'tax_rate',
   approx => 1,
   interpolate => 1,
 ); # => 0.309


=head1 SEE ALSO
