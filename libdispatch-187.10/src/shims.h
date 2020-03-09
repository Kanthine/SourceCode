#ifndef __DISPATCH_OS_SHIMS__
#define __DISPATCH_OS_SHIMS__

#include <pthread.h>
#if HAVE_PTHREAD_WORKQUEUES
#include <pthread_workqueue.h>
#endif
#if HAVE_PTHREAD_NP_H
#include <pthread_np.h>
#endif

#if !HAVE_DECL_FD_COPY
#define FD_COPY(f, t) (void)(*(t) = *(f))
#endif

#if !HAVE_NORETURN_BUILTIN_TRAP
/*
 * XXXRW: Work-around for possible clang bug in which __builtin_trap() is not
 * marked noreturn, leading to a build error as dispatch_main() *is* marked
 * noreturn. Mask by marking __builtin_trap() as noreturn locally.
 */
DISPATCH_NORETURN
void __builtin_trap(void);
#endif

#include "shims/atomic.h"
#include "shims/tsd.h"
#include "shims/hw_config.h"
#include "shims/perfmon.h"

#include "shims/getprogname.h"
#include "shims/malloc_zone.h"
#include "shims/time.h"

#ifdef __APPLE__
// Clear the stack before calling long-running thread-handler functions that
// never return (and don't take arguments), to facilitate leak detection and
// provide cleaner backtraces. <rdar://problem/9050566>
#define _dispatch_clear_stack(s) do { \
		void *a[(s)/sizeof(void*) ? (s)/sizeof(void*) : 1]; \
		a[0] = pthread_get_stackaddr_np(pthread_self()); \
		bzero((void*)&a[1], a[0] - (void*)&a[1]); \
	} while (0)
#else
#define _dispatch_clear_stack(s)
#endif

#endif
