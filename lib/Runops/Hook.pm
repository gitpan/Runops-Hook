package Runops::Hook;

use strict;
use warnings;

our $VERSION = '0.01';

use DynaLoader ();
our @ISA = qw(DynaLoader);
__PACKAGE__->bootstrap;

1;

__END__

=pod

=head1 NAME

Runops::Hook - C level hooking of the runloop

=head1 SYNOPSIS

	# in MyHook.xs
	bool
	my_hook (pTHX) {
		/* you can play with PL_op here */

		/* returning a true value will skip the pp_addr call,
		 * letting the hook override the whole runloop */

		return 0; /* resume the loop normally */
	}

	MODULE = MyHook PACKAGE MyHook
	BOOT:
		Runops_Hook_set_hook(my_hook);
		Runops_Hook_enable();

=head1 HOOKS

The runloop has a global boolean, C<Runops_Hook_enabled>. When unset, the
runloop works like the normal Perl run loop.

When the flag is enabled and C<Runops_Hook_threshold> is 0 (the default) then
the hook will be called on every loop iteration.

If C<Runops_Hook_threshold> is set to a non zero value then the hook will only
be called when an op counter C<PL_op> has reached the threshold.

=head1 AUTHOR

Chia-Liang Kao E<lt>clkao@clkao.orgE<gt>

Yuval Kogman E<lt>nothingmuch@woobling.orgE<gt>

=head1 COPYRIGHT

	Copyright (c) 2008 Chia-Liang Kao, Yuval Kogman. All rights
	reserved. This program is free software; you can redistribute
	it and/or modify it under the same terms as Perl itself.

=cut
