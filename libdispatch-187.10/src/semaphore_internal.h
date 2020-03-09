#ifndef __DISPATCH_SEMAPHORE_INTERNAL__
#define __DISPATCH_SEMAPHORE_INTERNAL__

struct dispatch_sema_notify_s {
	struct dispatch_sema_notify_s *volatile dsn_next;
	dispatch_queue_t dsn_queue;
	void *dsn_ctxt;
	void (*dsn_func)(void *);
};

struct dispatch_semaphore_s {
	DISPATCH_STRUCT_HEADER(dispatch_semaphore_s, dispatch_semaphore_vtable_s);
	long dsema_value;
	long dsema_orig;
	size_t dsema_sent_ksignals;
#if USE_MACH_SEM && USE_POSIX_SEM
#error "Too many supported semaphore types"
#elif USE_MACH_SEM
	semaphore_t dsema_port;
	semaphore_t dsema_waiter_port;
#elif USE_POSIX_SEM
	sem_t dsema_sem;
#else
#error "No supported semaphore type"
#endif
	size_t dsema_group_waiters;
	struct dispatch_sema_notify_s *dsema_notify_head;
	struct dispatch_sema_notify_s *dsema_notify_tail;
};

extern const struct dispatch_semaphore_vtable_s _dispatch_semaphore_vtable;

typedef uintptr_t _dispatch_thread_semaphore_t;
_dispatch_thread_semaphore_t _dispatch_get_thread_semaphore(void);
void _dispatch_put_thread_semaphore(_dispatch_thread_semaphore_t);
void _dispatch_thread_semaphore_wait(_dispatch_thread_semaphore_t);
void _dispatch_thread_semaphore_signal(_dispatch_thread_semaphore_t);
void _dispatch_thread_semaphore_dispose(_dispatch_thread_semaphore_t);

#endif
