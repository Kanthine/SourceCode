#include "internal.h"

void dispatch_retain(dispatch_object_t dou){
	if (slowpath(dou._do->do_xref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT)) {
		return; // global object
	}
	if (slowpath((dispatch_atomic_inc2o(dou._do, do_xref_cnt) - 1) == 0)) {
		DISPATCH_CLIENT_CRASH("Resurrection of an object");
	}
}

void _dispatch_retain(dispatch_object_t dou){
	if (slowpath(dou._do->do_ref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT)) {
		return; // global object
	}
	if (slowpath((dispatch_atomic_inc2o(dou._do, do_ref_cnt) - 1) == 0)) {
		DISPATCH_CLIENT_CRASH("Resurrection of an object");
	}
}

void dispatch_release(dispatch_object_t dou){
	if (slowpath(dou._do->do_xref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT)) {
		return;
	}
	unsigned int xref_cnt = dispatch_atomic_dec2o(dou._do, do_xref_cnt) + 1;
	if (fastpath(xref_cnt > 1)) {
		return;
	}
	if (fastpath(xref_cnt == 1)) {
		if (dou._do->do_vtable == (void*)&_dispatch_source_kevent_vtable) {
			return _dispatch_source_xref_release(dou._ds);
		}
		if (slowpath(DISPATCH_OBJECT_SUSPENDED(dou._do))) {
			// Arguments for and against this assert are within 6705399
			DISPATCH_CLIENT_CRASH("Release of a suspended object");
		}
		return _dispatch_release(dou._do);
	}
	DISPATCH_CLIENT_CRASH("Over-release of an object");
}

void _dispatch_dispose(dispatch_object_t dou){
	dispatch_queue_t tq = dou._do->do_targetq;
	dispatch_function_t func = dou._do->do_finalizer;
	void *ctxt = dou._do->do_ctxt;

	dou._do->do_vtable = (void *)0x200;

	free(dou._do);

	if (func && ctxt) {
		dispatch_async_f(tq, ctxt, func);
	}
	_dispatch_release(tq);
}

void _dispatch_release(dispatch_object_t dou){
	if (slowpath(dou._do->do_ref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT)) {
		return; // global object
	}

	unsigned int ref_cnt = dispatch_atomic_dec2o(dou._do, do_ref_cnt) + 1;
	if (fastpath(ref_cnt > 1)) {
		return;
	}
	if (fastpath(ref_cnt == 1)) {
		if (slowpath(dou._do->do_next != DISPATCH_OBJECT_LISTLESS)) {
			DISPATCH_CRASH("release while enqueued");
		}
		if (slowpath(dou._do->do_xref_cnt)) {
			DISPATCH_CRASH("release while external references exist");
		}
		return dx_dispose(dou._do);
	}
	DISPATCH_CRASH("over-release");
}

void * dispatch_get_context(dispatch_object_t dou){
	return dou._do->do_ctxt;
}

void dispatch_set_context(dispatch_object_t dou, void *context){
	if (dou._do->do_ref_cnt != DISPATCH_OBJECT_GLOBAL_REFCNT) {
		dou._do->do_ctxt = context;
	}
}

void dispatch_set_finalizer_f(dispatch_object_t dou, dispatch_function_t finalizer){
	dou._do->do_finalizer = finalizer;
}

/* 挂起指定的 dispatch_object
 * @note 全局队列不受影响
 * @note 正在执行的 dispatch_block 不受影响
 */
void dispatch_suspend(dispatch_object_t dou){
	if (slowpath(dou._do->do_ref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT)) {
		return;
	}
	(void)dispatch_atomic_add2o(dou._do, do_suspend_cnt,DISPATCH_OBJECT_SUSPEND_INTERVAL);
	_dispatch_retain(dou._do);
}

DISPATCH_NOINLINE
static void _dispatch_resume_slow(dispatch_object_t dou){
	_dispatch_wakeup(dou._do);
	// Balancing the retain() done in suspend() for rdar://8181908
	_dispatch_release(dou._do);
}

/* 恢复指定的 dispatch_object
* @note 全局队列不受影响
* @note 正在执行的 dispatch_block 不受影响
*/
void dispatch_resume(dispatch_object_t dou){
	/* 全局对象不能被挂起或恢复。
	 * 这还具有使对象的挂起计数饱和并防止由于溢出而恢复的副作用。
	 */
	if (slowpath(dou._do->do_ref_cnt == DISPATCH_OBJECT_GLOBAL_REFCNT)) {
		return;
	}
	
	/* 检查 suspend_cnt 的前一个值。如果前一个值是单个挂起间隔，则应该恢复该对象。
	 * 如果之前的值小于挂起间隔，则该对象已被过度恢复。
	 */
	unsigned int suspend_cnt = dispatch_atomic_sub2o(dou._do, do_suspend_cnt,
			DISPATCH_OBJECT_SUSPEND_INTERVAL) +
			DISPATCH_OBJECT_SUSPEND_INTERVAL;
	if (fastpath(suspend_cnt > DISPATCH_OBJECT_SUSPEND_INTERVAL)) {
		return _dispatch_release(dou._do);
	}
	if (fastpath(suspend_cnt == DISPATCH_OBJECT_SUSPEND_INTERVAL)) {
		return _dispatch_resume_slow(dou);
	}
	DISPATCH_CLIENT_CRASH("Over-resume of an object");
}

size_t _dispatch_object_debug_attr(dispatch_object_t dou, char* buf, size_t bufsiz){
	return snprintf(buf, bufsiz, "xrefcnt = 0x%x, refcnt = 0x%x, "
			"suspend_cnt = 0x%x, locked = %d, ", dou._do->do_xref_cnt,
			dou._do->do_ref_cnt,
			dou._do->do_suspend_cnt / DISPATCH_OBJECT_SUSPEND_INTERVAL,
			dou._do->do_suspend_cnt & 1);
}
