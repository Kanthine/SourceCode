#include "internal.h"

#undef dispatch_once
#undef dispatch_once_f

/** 每次进来一个线程,都会创建一个下述的结构体
 *
 */
struct _dispatch_once_waiter_s {
	volatile struct _dispatch_once_waiter_s *volatile dow_next; /// 指向了下一个结构体变量
	_dispatch_thread_semaphore_t dow_sema; /// 存储当前线程的信号量
};

#define DISPATCH_ONCE_DONE ((struct _dispatch_once_waiter_s *)~0l)

#ifdef __BLOCKS__
void dispatch_once(dispatch_once_t *val, dispatch_block_t block){
	struct Block_basic *bb = (void *)block;
	dispatch_once_f(val, block, (void *)bb->Block_invoke);
}
#endif


/** 1、dispatch_once不是只执行一次那么简单。内部还是很复杂的。
 *		onceToken 在第一次执行 block 之前，它的值由 NULL 变为指向第一个调用者的指针(&dow)
 *  2、dispatch_once 是可以接受多次请求的，内部会构造一个链表来维护。
 *  	如果在block完成之前，有其它的调用者进来，则会把这些调用者放到一个waiter链表中（在else分支中的代码）。
 *  3、waiter链表中的每个调用者会等待一个信号量(dow.dow_sema)。
 * 		在block执行完了后，除了将onceToken置为DISPATCH_ONCE_DONE外，
 * 		还会去遍历waiter链中的所有waiter，抛出相应的信号量，以告知waiter们调用已经结束了。
 */

DISPATCH_NOINLINE
void dispatch_once_f(dispatch_once_t *val, void *ctxt, dispatch_function_t func){
	struct _dispatch_once_waiter_s * volatile *vval = (struct _dispatch_once_waiter_s**)val;
	struct _dispatch_once_waiter_s dow = { NULL, 0 };
	struct _dispatch_once_waiter_s *tail, *tmp;
	_dispatch_thread_semaphore_t sema;//局部变量，用于在遍历链表过程中获取每一个在链表上的更改请求的信号量
	
	// Compare and Swap（用于首次更改请求）
	if (dispatch_atomic_cmpxchg(vval, NULL, &dow)) {
		dispatch_atomic_acquire_barrier();
		_dispatch_client_callout(ctxt, func);

		// The next barrier must be long and strong.
		//
		// The scenario: SMP systems with weakly ordered memory models and aggressive out-of-order instruction execution.
		//
		// The problem:
		//
		// The dispatch_once*() wrapper macro causes the callee's
		// instruction stream to look like this (pseudo-RISC):
		//
		//      load r5, pred-addr
		//      cmpi r5, -1
		//      beq  1f
		//      call dispatch_once*()
		//      1f:
		//      load r6, data-addr
		//
		// May be re-ordered like so:
		//
		//      load r6, data-addr
		//      load r5, pred-addr
		//      cmpi r5, -1
		//      beq  1f
		//      call dispatch_once*()
		//      1f:
		//
		// Normally, a barrier on the read side is used to workaround
		// the weakly ordered memory model. But barriers are expensive
		// and we only need to synchronize once! After func(ctxt)
		// completes, the predicate will be marked as "done" and the
		// branch predictor will correctly skip the call to
		// dispatch_once*().
		//
		// A far faster alternative solution: Defeat the speculative
		// read-ahead of peer CPUs.
		//
		// Modern architectures will throw away speculative results
		// once a branch mis-prediction occurs. Therefore, if we can
		// ensure that the predicate is not marked as being complete
		// until long after the last store by func(ctxt), then we have
		// defeated the read-ahead of peer CPUs.
		//
		// In other words, the last "store" by func(ctxt) must complete
		// and then N cycles must elapse before ~0l is stored to *val.
		// The value of N is whatever is sufficient to defeat the
		// read-ahead mechanism of peer CPUs.
		//
		// On some CPUs, the most fully synchronizing instruction might
		// need to be issued.

		dispatch_atomic_maximally_synchronizing_barrier();
		//dispatch_atomic_release_barrier(); // assumed contained in above
		
		//更改请求成为DISPATCH_ONCE_DONE(原子性的操作)
		tmp = dispatch_atomic_xchg(vval, DISPATCH_ONCE_DONE);
		tail = &dow;
		
		//发现还有更改请求，继续遍历
		while (tail != tmp) {
			// 如果这个时候tmp的next指针还没更新完毕，等一会
			while (!tmp->dow_next) {
				_dispatch_hardware_pause();
			}
			//取出当前的信号量，告诉等待者，我这次更改请求完成了，轮到下一个了
			sema = tmp->dow_sema;
			tmp = (struct _dispatch_once_waiter_s*)tmp->dow_next;
			_dispatch_thread_semaphore_signal(sema);
		}
	} else {
		//非首次请求，进入这块逻辑块
		dow.dow_sema = _dispatch_get_thread_semaphore();
		for (;;) {
			
			//遍历每一个后续请求，如果状态已经是Done，直接进行下一个
			// 同时该状态检测还用于避免在后续wait之前，信号量已经发出(signal)造成的死锁
			tmp = *vval;
			if (tmp == DISPATCH_ONCE_DONE) {
				break;
			}
			dispatch_atomic_store_barrier();
			
			//如果当前dispatch_once执行的block没有结束，那么就将这些后续请求添加到链表当中
			if (dispatch_atomic_cmpxchg(vval, tmp, &dow)) {
				dow.dow_next = tmp;
				_dispatch_thread_semaphore_wait(dow.dow_sema);
			}
		}
		_dispatch_put_thread_semaphore(dow.dow_sema);
	}
}
