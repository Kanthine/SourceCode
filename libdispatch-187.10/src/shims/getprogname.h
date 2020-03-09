#ifndef __DISPATCH_SHIMS_GETPROGNAME__
#define __DISPATCH_SHIMS_GETPROGNAME__

#if !HAVE_GETPROGNAME
static inline char *
getprogname(void)
{
# if HAVE_DECL_PROGRAM_INVOCATION_SHORT_NAME
	return program_invocation_short_name;
# else
#   error getprogname(3) is not available on this platform
# endif
}
#endif /* HAVE_GETPROGNAME */

#endif /* __DISPATCH_SHIMS_GETPROGNAME__ */
