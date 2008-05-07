#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "embed.h"
#include "XSUB.h"

#define XPUSHREF(x) XPUSHs(sv_2mortal(newRV_inc(x)))

bool (*Runops_Hook_hook)(pTHX);

static HV *Runops_Hook_op_counters;

static bool Runops_Hook_enabled;
static UV Runops_Hook_threshold = 0;

static SV *Runops_Hook_perl_hook;
static bool Runops_Hook_perl_ignore_ret = 1;

static bool Runops_Hook_loaded_B;
static GV *Runops_Hook_B_UNOP_stash;
static UNOP Runops_Hook_fakeop;
static SV *Runops_Hook_fakeop_sv;

#define ARITY_NULL 0
#define ARITY_UNARY 1
#define ARITY_BINARY 1 << 1
#define ARITY_LIST 1 << 2
#define ARITY_LIST_BINARY (ARITY_LIST|ARITY_BINARY)
#define ARITY_LIST_UNARY (ARITY_LIST|ARITY_UNARY)
#define ARITY_UNKNOWN 1 << 3

/* this is the modified runloop */
int runops_hooked(pTHX)
{
	if ( !Runops_Hook_op_counters )
		Runops_Hook_op_counters = newHV();

	for (;PL_op;) {
		/* global flag controls all hooking behavior */
		if (Runops_Hook_enabled) {
			if (Runops_Hook_threshold == 0) {
				/* no threshold set means simple hooking */
				if (Runops_Hook_hook(aTHX))
					continue;
			} else {
				/* having a threshold means that only ops that are hit enough
				 * times get hooked, the idea is that this can be used for
				 * trace caching */

				/* unfortunately we need to keep the counters in a hash */
				SV **count = hv_fetch(Runops_Hook_op_counters, (char *)PL_op, sizeof(PL_op), 1);
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

void
Runops_Hook_enable () {
	Runops_Hook_enabled = 1;
}

void
Runops_Hook_disable () {
	Runops_Hook_enabled = 0;
}

/* this is the default hook that does nothing */
bool
Runops_Hook_noop (pTHX) {
	/* resume normally */
	return 0;
}

SV *
Runops_Hook_op_to_BOP (pTHX_ OP *op) {
	dSP;
	/* this assumes Runops_Hook_load_B() has already been called */

	/* we fake B::UNOP object (fakeop_sv) that points to our static fakeop.
	 * then we set first_op to the op we want to make an object out of, and
	 * trampoline into B::UNOP->first so that it creates the B::OP of the
	 * correct class for us.
	 * B should really have a way to create an op from a pointer via some
	 * external API. This sucks monkey balls on olympic levels */

	Runops_Hook_fakeop.op_first = op;

	PUSHMARK(SP);
	XPUSHs(Runops_Hook_fakeop_sv);
	PUTBACK;

	call_pv("B::UNOP::first", G_SCALAR);

	SPAGAIN;

	return POPs;
}

IV
Runops_Hook_op_arity (pTHX_ OP *o) {
	switch (o->op_type) {
		case OP_SASSIGN:
			/* wtf? */
			return ((o->op_private & OPpASSIGN_BACKWARDS) ? ARITY_UNARY : ARITY_BINARY);

		case OP_ENTERSUB:
			return ARITY_LIST_UNARY;

		case OP_REFGEN:
			return ARITY_LIST;
	}

	switch (PL_opargs[o->op_type] & OA_CLASS_MASK) {
		case OA_COP:
		case OA_SVOP:
		case OA_PADOP:
		case OA_BASEOP:
		case OA_FILESTATOP:
		case OA_LOOPEXOP:
			return ARITY_NULL;

		case OA_BASEOP_OR_UNOP:
			return (o->op_flags & OPf_KIDS) ? ARITY_UNARY : ARITY_NULL;

		case OA_LOGOP:
		case OA_UNOP:
			return ARITY_UNARY;

		case OA_LISTOP:
			return ARITY_LIST;

		case OA_BINOP:
			if ( o->op_type == OP_AASSIGN ) {
				return ARITY_LIST_BINARY;
			} else {
				return ARITY_BINARY;
			}
		default:
			printf("%s is a %d\n", PL_op_name[o->op_type], PL_opargs[o->op_type] >> OASHIFT);
			return ARITY_UNKNOWN;
	}
}

static AV *
av_make_with_refs(pTHX_ SV**from, SV**to) {
	SV **i;
	AV *av = newAV();

	av_extend(av, (to - from) / sizeof(SV **));

	for (i = from; i <= to; i++) {
		av_push(av, newRV_inc(*i));
	}

	return av;
}

/* this is a hook that calls to a perl code ref */
bool
Runops_Hook_perl (pTHX) {
	dSP;

	register SV **orig_sp = SP;
	register SV **list_mark;

	SV *sv_ret;
	SV *PL_op_object;
	bool ret;
	IV arity;

	/* don't want to hook the hook */
	Runops_Hook_disable();

	ENTER;
	SAVETMPS;

	PL_op_object = Runops_Hook_op_to_BOP(aTHX_ PL_op);
	arity = Runops_Hook_op_arity(aTHX_ PL_op);


	PUSHMARK(SP);
	XPUSHs(Runops_Hook_perl_hook);
	XPUSHs(PL_op_object);
	XPUSHs(sv_2mortal(newSViv(arity)));

	switch (arity) {
		case ARITY_LIST_UNARY:
			/* ENTERSUB's unary arg (the cv) is the last thing on the stack, but it has args too */
			XPUSHREF(*orig_sp--);
		case ARITY_LIST:
			/* repeat stack from the op's mark to SP just before we started pushing */
			for (list_mark = PL_stack_base + *(PL_markstack_ptr-1) + 1; list_mark <= orig_sp; list_mark++) {
				XPUSHREF(*list_mark);
			}

			break;


		case ARITY_BINARY:
			XPUSHREF(*(orig_sp-1));
		case ARITY_UNARY:
			XPUSHREF(*orig_sp);
			break;


		case ARITY_LIST_BINARY:
			{
				SV **mark = SP; dORIGMARK;

				SV **lastlelem = orig_sp;
				SV **lastrelem = PL_stack_base + *(PL_markstack_ptr-1);
				SV **firstrelem = PL_stack_base + *(PL_markstack_ptr-2) + 1;
				SV **firstlelem = lastrelem + 1;

				SV *lav = (SV *)av_make_with_refs(aTHX_ firstlelem, lastlelem);
				SV *rav = (SV *)av_make_with_refs(aTHX_ firstrelem, lastrelem);

				SP = ORIGMARK;

				XPUSHREF(lav);
				XPUSHREF(rav);
			}

			break;

		case ARITY_NULL:
			break;


		default:
			warn("Unknown arity for %s (%p)", PL_op_name[PL_op->op_type], PL_op);
			break;
	}


	PUTBACK;

	call_sv(Runops_Hook_perl_hook, (Runops_Hook_perl_ignore_ret ? G_DISCARD : G_SCALAR));

	SPAGAIN;

	/* we coerce it here so that SvTRUE is evaluated without hooking, and
	 * Runops_Hook_enable() is the last thing in this hook */

	if (!Runops_Hook_perl_ignore_ret) {
		sv_ret = POPs;
		ret = SvTRUE(sv_ret);
	} else {
		ret = 0;
	}


	PUTBACK;
	FREETMPS;
	LEAVE;

	Runops_Hook_enable();

	return ret;
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
Runops_Hook_clear_perl_hook(pTHX) {
	if (Runops_Hook_perl_hook) {
		SvREFCNT_dec(Runops_Hook_perl_hook);
		Runops_Hook_perl_hook = NULL;
	}
}

void
Runops_Hook_set_perl_hook (pTHX_ SV *hook) {
	Runops_Hook_clear_perl_hook(aTHX);

	Runops_Hook_perl_hook = hook;
	SvREFCNT_inc(Runops_Hook_perl_hook);

	Runops_Hook_set_hook(Runops_Hook_perl);
}

UV
Runops_Hook_get_threshold () {
	return Runops_Hook_threshold;
}

void
Runops_Hook_set_threshold (UV t) {
	Runops_Hook_threshold = t;
}

void
Runops_Hook_load_B (pTHX) {
	if (!Runops_Hook_loaded_B) {
		load_module( PERL_LOADMOD_NOIMPORT, newSVpv("B", 0), newSViv(0) );
		Runops_Hook_fakeop_sv = sv_bless(newRV_noinc(newSVuv((UV)&Runops_Hook_fakeop)), gv_stashpv("B::UNOP", 0));
		Runops_Hook_loaded_B = 1;
	}
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
	RETVAL = Runops_Hook_get_threshold();
}
	OUTPUT:
		RETVAL

void
set_threshold(SV *a)
	  CODE:
{
	   Runops_Hook_set_threshold(SvUV(a));
}

void
set_hook(SV *hook)
	CODE:
{
	Runops_Hook_load_B(aTHX);
	Runops_Hook_set_perl_hook(aTHX_ hook);
}

void
clear_hook()
	CODE:
{
	Runops_Hook_clear_perl_hook(aTHX);
	Runops_Hook_clear_hook();
}

void
ignore_hook_ret()
	CODE:
{
	Runops_Hook_perl_ignore_ret = 1;
}

void
unignore_hook_ret()
	CODE:
{
	Runops_Hook_perl_ignore_ret = 0;
}

