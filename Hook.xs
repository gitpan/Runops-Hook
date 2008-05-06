#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

bool (*Runops_Hook_hook)(pTHX);

static HV *Runops_Hook_op_counters;

static bool Runops_Hook_enabled = 0;
static UV Runops_Hook_threshold = 0;

int runops_hooked(pTHX)
{
	if ( !Runops_Hook_op_counters )
		Runops_Hook_op_counters = newHV();

	for (;PL_op;) {
		if (Runops_Hook_enabled) {
			if (Runops_Hook_threshold == 0) {
				if (Runops_Hook_hook(aTHX))
					continue;
			} else {
				SV **count = hv_fetch(Runops_Hook_op_counters, (char *)&PL_op, sizeof(PL_op), 1);
				UV c       = SvTRUE(*count) ? SvUV(*count) + 1 : 1;
				sv_setuv(*count, c);

				if (c >= Runops_Hook_threshold)
					if (Runops_Hook_hook(aTHX))
						continue;
			}
		}

		PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX);

		PERL_ASYNC_CHECK();
	}

	TAINT_NOT;

	return 0;
}

bool
Runops_Hook_noop (pTHX) {
	/* resume normally */
	return 0;
}

void
Runops_Hook_clear_hook () {
	Runops_Hook_hook = Runops_Hook_noop;
}

void
Runops_Hook_set_hook (bool (*hook)(pTHX)) {
	Runops_Hook_hook = hook;
}

void
Runops_Hook_enable () {
	Runops_Hook_enabled = 1;
}

void
Runops_Hook_disable () {
	Runops_Hook_enabled = 0;
}

MODULE = Runops::Hook PACKAGE = Runops::Hook

BOOT:
	Runops_Hook_clear_hook();
    PL_runops = runops_hooked;

HV *
counters()
	CODE:
{
	RETVAL = Runops_Hook_op_counters;
}
	OUTPUT:
		RETVAL

bool
enabled()
	CODE:
{
	RETVAL = Runops_Hook_enabled;
}
	OUTPUT:
		RETVAL

void
enable()
	CODE:
{
	Runops_Hook_enable();
}

void
disable()
	CODE:
{
	Runops_Hook_disable();
}

UV
get_threshold()
	CODE:
{
	RETVAL = Runops_Hook_threshold;
}
	OUTPUT:
		RETVAL

void
set_threshold(SV *a)
	  CODE:
{
	   Runops_Hook_threshold = SvUV(a);
}
