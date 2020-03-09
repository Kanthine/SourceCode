#ifndef __DISPATCH_SHIMS_PERFMON__
#define __DISPATCH_SHIMS_PERFMON__

#if DISPATCH_PERF_MON

#if defined (USE_APPLE_TSD_OPTIMIZATIONS) && defined(SIMULATE_5491082) && \
		(defined(__i386__) || defined(__x86_64__))
#ifdef __LP64__
#define _dispatch_workitem_inc() asm("incq %%gs:%0" : "+m" \
		(*(void **)(dispatch_bcounter_key * sizeof(void *) + \
		_PTHREAD_TSD_OFFSET)) :: "cc")
#define _dispatch_workitem_dec() asm("decq %%gs:%0" : "+m" \
		(*(void **)(dispatch_bcounter_key * sizeof(void *) + \
		_PTHREAD_TSD_OFFSET)) :: "cc")
#else
#define _dispatch_workitem_inc() asm("incl %%gs:%0" : "+m" \
		(*(void **)(dispatch_bcounter_key * sizeof(void *) + \
		_PTHREAD_TSD_OFFSET)) :: "cc")
#define _dispatch_workitem_dec() asm("decl %%gs:%0" : "+m" \
		(*(void **)(dispatch_bcounter_key * sizeof(void *) + \
		_PTHREAD_TSD_OFFSET)) :: "cc")
#endif
#else /* !USE_APPLE_TSD_OPTIMIZATIONS */
static inline void
_dispatch_workitem_inc(void)
{
	unsigned long cnt;
	cnt = (unsigned long)_dispatch_thread_getspecific(dispatch_bcounter_key);
	_dispatch_thread_setspecific(dispatch_bcounter_key, (void *)++cnt);
}
static inline void
_dispatch_workitem_dec(void)
{
	unsigned long cnt;
	cnt = (unsigned long)_dispatch_thread_getspecific(dispatch_bcounter_key);
	_dispatch_thread_setspecific(dispatch_bcounter_key, (void *)--cnt);
}
#endif /* USE_APPLE_TSD_OPTIMIZATIONS */

// C99 doesn't define flsll() or ffsll()
#ifdef __LP64__
#define flsll(x) flsl(x)
#else
static inline unsigned int
flsll(uint64_t val)
{
	union {
		struct {
#ifdef __BIG_ENDIAN__
			unsigned int hi, low;
#else
			unsigned int low, hi;
#endif
		} words;
		uint64_t word;
	} _bucket = {
		.word = val,
	};
	if (_bucket.words.hi) {
		return fls(_bucket.words.hi) + 32;
	}
	return fls(_bucket.words.low);
}
#endif

#else
#define _dispatch_workitem_inc()
#define _dispatch_workitem_dec()
#endif // DISPATCH_PERF_MON

#endif
