#!perl

use strict;
use warnings;

use Test::More qw(no_plan);
use Runops::Hook;

use B::Concise;

B::Concise::compile("fact")->();
B::Concise::compile(-exec => "fact")->();

sub fact {
	my $n = $_[0];

	if ( $n <= 1 ) {
		return $n;
	} else {
		return ( $n * fact($n - 1) );
	}
}

Runops::Hook::set_hook(sub {
	my ( $self, $op, $arity, @args ) = @_;

	#warn "op name: ", $op->name, "($$op) arity: ", $arity, " args: ", \@args;
	#use Devel::Peek;
	#Dump($_) for @args;
});

Runops::Hook::enable();

my $f = fact(3);

Runops::Hook::disable();

is( $f, 6 );
