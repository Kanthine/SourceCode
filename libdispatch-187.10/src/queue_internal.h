#ifndef __DISPATCH_QUEUE_INTERNAL__
#define __DISPATCH_QUEUE_INTERNAL__

#ifndef __DISPATCH_INDIRECT__
#error "Please #include <dispatch/dispatch.h> instead of this file directly."
#include <dispatch/base.h> // for HeaderDoc
#endif

//如果 dc_vtable 小于 127，则该 object 是 continuation
//否则，object 有一个私有布局和内存管理规则。
//The first two words must align with normal objects.
#define DISPATCH_CONTINUATION_HEADER(x) \
	const void *do_vtable; \
	struct x *volatile do_next; \
	dispatch_function_t dc_func; \
	void *dc_ctxt

#define DISPATCH_OBJ_ASYNC_BIT		0x1 // 0001
#define DISPATCH_OBJ_BARRIER_BIT	0x2 // 0010
#define DISPATCH_OBJ_GROUP_BIT		0x4 // 0100
#define DISPATCH_OBJ_SYNC_SLOW_BIT	0x8 // 1000

// vtables 指针在内存中从高位到低位
#define DISPATCH_OBJ_IS_VTABLE(x) ((unsigned long)(x)->do_vtable > 127ul)

struct dispatch_continuation_s {
	DISPATCH_CONTINUATION_HEADER(dispatch_continuation_s);
	dispatch_group_t dc_group;
	void *dc_data[3];
};

typedef struct dispatch_continuation_s *dispatch_continuation_t;

struct dispatch_queue_attr_vtable_s {
	DISPATCH_VTABLE_HEADER(dispatch_queue_attr_s);
};

struct dispatch_queue_attr_s {
	DISPATCH_STRUCT_HEADER(dispatch_queue_attr_s, dispatch_queue_attr_vtable_s);
};

struct dispatch_queue_vtable_s {
	DISPATCH_VTABLE_HEADER(dispatch_queue_s);
};

#define DISPATCH_QUEUE_MIN_LABEL_SIZE 64

#ifdef __LP64__
#define DISPATCH_QUEUE_CACHELINE_PAD 32
#else
#define DISPATCH_QUEUE_CACHELINE_PAD 8
#endif

#define DISPATCH_QUEUE_HEADER \
	uint32_t volatile dq_running; \
	uint32_t dq_width; \
	struct dispatch_object_s *volatile dq_items_tail; \
	struct dispatch_object_s *volatile dq_items_head; \
	unsigned long dq_serialnum; \
	dispatch_queue_t dq_specific_q;

struct dispatch_queue_s {
	DISPATCH_STRUCT_HEADER(dispatch_queue_s, dispatch_queue_vtable_s);
	DISPATCH_QUEUE_HEADER;
	char dq_label[DISPATCH_QUEUE_MIN_LABEL_SIZE]; // 唯一标识
	char _dq_pad[DISPATCH_QUEUE_CACHELINE_PAD]; // for static queues only
};

extern struct dispatch_queue_s _dispatch_mgr_q;

void _dispatch_queue_dispose(dispatch_queue_t dq);//销毁一个队列
void _dispatch_queue_invoke(dispatch_queue_t dq);//调用一个队列
void _dispatch_queue_push_list_slow(dispatch_queue_t dq, struct dispatch_object_s *obj);

DISPATCH_ALWAYS_INLINE
static inline void
_dispatch_queue_push_list(dispatch_queue_t dq, dispatch_object_t _head, dispatch_object_t _tail){
	struct dispatch_object_s *prev, *head = _head._do, *tail = _tail._do;
	tail->do_next = NULL;
	dispatch_atomic_store_barrier();
	prev = fastpath(dispatch_atomic_xchg2o(dq, dq_items_tail, tail));
	if (prev) {
		// 如果在这里以小于 0x1000 的值崩溃，那么我们在客户端代码中遇到了一个已知的错误，
		// 请参见 _dispatch_queue_dispose 或 _dispatch_atfork_child
		prev->do_next = head;
	} else {
		_dispatch_queue_push_list_slow(dq, head);
	}
}

#define _dispatch_queue_push(x, y) _dispatch_queue_push_list((x), (y), (y))

#if DISPATCH_DEBUG
void dispatch_debug_queue(dispatch_queue_t dq, const char* str);
#else
static inline void dispatch_debug_queue(dispatch_queue_t dq DISPATCH_UNUSED,
		const char* str DISPATCH_UNUSED) {}
#endif

size_t dispatch_queue_debug(dispatch_queue_t dq, char* buf, size_t bufsiz);
size_t _dispatch_queue_debug_attr(dispatch_queue_t dq, char* buf,
		size_t bufsiz);

DISPATCH_ALWAYS_INLINE
static inline dispatch_queue_t
_dispatch_queue_get_current(void){
	return _dispatch_thread_getspecific(dispatch_queue_key);
}

#define DISPATCH_QUEUE_PRIORITY_COUNT 4
#define DISPATCH_ROOT_QUEUE_COUNT (DISPATCH_QUEUE_PRIORITY_COUNT * 2)

// 优先级 overcommit 的第 0 位值为 1
enum {
	DISPATCH_ROOT_QUEUE_IDX_LOW_PRIORITY = 0, 				//000
	DISPATCH_ROOT_QUEUE_IDX_LOW_OVERCOMMIT_PRIORITY, 		//001
	DISPATCH_ROOT_QUEUE_IDX_DEFAULT_PRIORITY,				//010
	DISPATCH_ROOT_QUEUE_IDX_DEFAULT_OVERCOMMIT_PRIORITY,	//011
	DISPATCH_ROOT_QUEUE_IDX_HIGH_PRIORITY,					//100
	DISPATCH_ROOT_QUEUE_IDX_HIGH_OVERCOMMIT_PRIORITY,		//101
	DISPATCH_ROOT_QUEUE_IDX_BACKGROUND_PRIORITY,			//110
	DISPATCH_ROOT_QUEUE_IDX_BACKGROUND_OVERCOMMIT_PRIORITY, //111
};

extern const struct dispatch_queue_attr_vtable_s dispatch_queue_attr_vtable;
extern const struct dispatch_queue_vtable_s _dispatch_queue_vtable;
extern unsigned long _dispatch_queue_serial_numbers;
extern struct dispatch_queue_s _dispatch_root_queues[];

DISPATCH_ALWAYS_INLINE DISPATCH_CONST

/** 根据优先级 priority 与 overcommit ，从队列池中取出一个队列
 * @param overcommit 每当有任务提交到该队列时，为免线程过载，系统是否新开一个线程处理。
 */
static inline dispatch_queue_t
_dispatch_get_root_queue(long priority, bool overcommit) {
	if (overcommit) switch (priority) {// flag = 2 时
		case DISPATCH_QUEUE_PRIORITY_LOW:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_LOW_OVERCOMMIT_PRIORITY];
		case DISPATCH_QUEUE_PRIORITY_DEFAULT:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_DEFAULT_OVERCOMMIT_PRIORITY];
		case DISPATCH_QUEUE_PRIORITY_HIGH:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_HIGH_OVERCOMMIT_PRIORITY];
		case DISPATCH_QUEUE_PRIORITY_BACKGROUND:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_BACKGROUND_OVERCOMMIT_PRIORITY];
	}
	
	// flag = 0 时
	switch (priority) {
		case DISPATCH_QUEUE_PRIORITY_LOW:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_LOW_PRIORITY];
		case DISPATCH_QUEUE_PRIORITY_DEFAULT:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_DEFAULT_PRIORITY];
		case DISPATCH_QUEUE_PRIORITY_HIGH:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_HIGH_PRIORITY];
		case DISPATCH_QUEUE_PRIORITY_BACKGROUND:
			return &_dispatch_root_queues[DISPATCH_ROOT_QUEUE_IDX_BACKGROUND_PRIORITY];
		default:
			return NULL;
	}
}

/* 初始化一个队列
 * 该队列的 dq_width=1，也就是默认并发数为 1 ，是个串行队列
 */
static inline void
_dispatch_queue_init(dispatch_queue_t dq){
	dq->do_vtable = &_dispatch_queue_vtable;
	dq->do_next = DISPATCH_OBJECT_LISTLESS;
	dq->do_ref_cnt = 1;
	dq->do_xref_cnt = 1;
	dq->do_targetq = _dispatch_get_root_queue(0, true);
	dq->dq_running = 0;
	dq->dq_width = 1; //默认并发数为 1
	dq->dq_serialnum = dispatch_atomic_inc(&_dispatch_queue_serial_numbers) - 1;
}

#endif
