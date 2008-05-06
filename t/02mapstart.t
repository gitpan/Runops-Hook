#!perl

use Runops::Hook;
BEGIN { Runops::Hook::enable() }

use Test::More tests => 1;

map { pass('map works') } '';
