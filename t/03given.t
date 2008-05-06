#!perl

use strict;
use warnings;

use Runops::Hook;
BEGIN { Runops::Hook::enable() }

use Test::More;

BEGIN {
    if ($] < 5.010) {
        plan skip_all => "Requires 5.10";
        exit(0);
    }
    else {
        plan tests => 2;
    }
}

use feature 'switch';

given (42) {
    pass("given works");
    when (42) { pass("when works"); }
}
