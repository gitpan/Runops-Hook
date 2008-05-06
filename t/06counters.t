#!perl

use strict;
use warnings;

use Runops::Hook;
use Test::More 'no_plan';

ok( !Runops::Hook::enabled(), "disabled" );

is_deeply( Runops::Hook::counters(), {}, "no counters yet" );

Runops::Hook::enable();
ok( Runops::Hook::enabled(), "enabled" );

Runops::Hook::set_threshold(3);

my $i;
for ( 1 .. 10 ) {
	$i++;
}

is( $i, 10, "loop ran correctly" );

ok( scalar(keys %{ Runops::Hook::counters() }), "counted something now" );
