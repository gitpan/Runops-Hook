#!perl

use strict;
use warnings;
use Runops::Hook;
BEGIN { Runops::Hook::enable() }

use Test::More tests => 1;

# this segfaults when loading PerlIO::scalar
open my $tmp, '>', \my $out;
print $tmp "foo";
is($out, "foo", "print to PerlIO::scalar works");
