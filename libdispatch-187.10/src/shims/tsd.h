#ifndef __DISPATCH_SHIMS_TSD__
#define __DISPATCH_SHIMS_TSD__

#if HAVE_PTHREAD_MACHDEP_H
#include <pthread_machdep.h>
#endif

#define DISPATCH_TSD_INLINE DISPATCH_ALWAYS_INLINE_NDEBUG

#if USE_APPLE_TSD_OPTIMIZATIONS && HAVE_PTHREAD_KEY_INIT_NP && \
	!defined(DISPATCH_USE_DIRECT_TSD)
#define DISPATCH_USE_DIRECT_TSD 1
#endif

//在 GCD 中定义了六个 key :
#if DISPATCH_USE_DIRECT_TSD
static const unsigned long dispatch_queue_key		= __PTK_LIBDISPATCH_KEY0;//队列
static const unsigned long dispatch_sema4_key		= __PTK_LIBDISPATCH_KEY1;
static const unsigned long dispatch_cache_key		= __PTK_LIBDISPATCH_KEY2;//缓存
static const unsigned long dispatch_io_key			= __PTK_LIBDISPATCH_KEY3;
static const unsigned long dispatch_apply_key		= __PTK_LIBDISPATCH_KEY4;
static const unsigned long dispatch_bcounter_key	= __PTK_LIBDISPATCH_KEY5;
//__PTK_LIBDISPATCH_KEY5

DISPATCH_TSD_INLINE
static inline void
_dispatch_thread_key_create(const unsigned long *k, void (*d)(void *)){
	dispatch_assert_zero(pthread_key_init_np((int)*k, d));
}
#else
pthread_key_t dispatch_queue_key;
pthread_key_t dispatch_sema4_key;
pthread_key_t dispatch_cache_key;
pthread_key_t dispatch_io_key;
pthread_key_t dispatch_apply_key;
pthread_key_t dispatch_bcounter_key;

DISPATCH_TSD_INLINE


/************ 在同一个线程中不同函数间共享数据 *************/


/* 创建一个同一线程中不同函数间共享的 key，
 * 在线程退出时会将 key 对应的 destr_function 函数清除内存
 */
static inline void
_dispatch_thread_key_create(pthread_key_t *k, void (*d)(void *)){
	dispatch_assert_zero(pthread_key_create(k, d));
}

#endif


#if DISPATCH_USE_TSD_BASE && !DISPATCH_DEBUG
#else // DISPATCH_USE_TSD_BASE
DISPATCH_TSD_INLINE

/* 设置同一线程中不同函数间共享的 key 对应的 value
 */
static inline void
_dispatch_thread_setspecific(pthread_key_t k, void *v){
#if DISPATCH_USE_DIRECT_TSD
	if (_pthread_has_direct_tsd()) {
		(void)_pthread_setspecific_direct(k, v);
		return;
	}
#endif
	dispatch_assert_zero(pthread_setspecific(k, v));
}

DISPATCH_TSD_INLINE

/** 获取同一线程中不同函数间共享的 key 对应的 value
 */
static inline void *
_dispatch_thread_getspecific(pthread_key_t k){
#if DISPATCH_USE_DIRECT_TSD
	if (_pthread_has_direct_tsd()) {//模拟器返回 0 ，否则返回 1
		return _pthread_getspecific_direct(k);
	}
#endif
	return pthread_getspecific(k);
}
#endif // DISPATCH_USE_TSD_BASE

#define _dispatch_thread_self (uintptr_t)pthread_self

#undef DISPATCH_TSD_INLINE

#endif
