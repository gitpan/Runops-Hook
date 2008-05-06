#!perl

use Test::More tests => 4;

use_ok('Runops::Hook');
Runops::Hook::enable();

pass('and it continues to work');
eval  { pass('... in eval {}') };
eval q{ pass('... in eval STRING') };
