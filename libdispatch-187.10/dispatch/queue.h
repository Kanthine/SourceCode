#ifndef __DISPATCH_QUEUE__
#define __DISPATCH_QUEUE__

#ifndef __DISPATCH_INDIRECT__
#error "Please #include <dispatch/dispatch.h> instead of this file directly."
#include <dispatch/base.h> // for HeaderDoc
#endif

/*!
 * @header
 *
 * Dispatch is an abstract model for expressing concurrency via simple but powerful API.
 *
 * At the core, dispatch provides serial FIFO queues to which blocks may be
 * submitted. Blocks submitted to these dispatch queues are invoked on a pool
 * of threads fully managed by the system. No guarantee is made regarding
 * which thread a block will be invoked on; however, it is guaranteed that only
 * one block submitted to the FIFO dispatch queue will be invoked at a time.
 *
 * When multiple queues have blocks to be processed, the system is free to
 * allocate additional threads to invoke the blocks concurrently. When the
 * queues become empty, these threads are automatically released.
 */

/*!
 * @typedef dispatch_queue_t
 *
 * @abstract
 * Dispatch queues invoke blocks submitted to them serially in FIFO order. A
 * queue will only invoke one block at a time, but independent queues may each
 * invoke their blocks concurrently with respect to each other.
 *
 * @discussion
 * Dispatch queues are lightweight objects to which blocks may be submitted.
 * The system manages a pool of threads which process dispatch queues and
 * invoke blocks submitted to them.
 *
 * Conceptually a dispatch queue may have its own thread of execution, and
 * interaction between queues is highly asynchronous.
 *
 * Dispatch queues are reference counted via calls to dispatch_retain() and
 * dispatch_release(). Pending blocks submitted to a queue also hold a
 * reference to the queue until they have finished. Once all references to a
 * queue have been released, the queue will be deallocated by the system.
 */

//#define DISPATCH_DECL(name) typedef struct name##_s *name##_t

DISPATCH_DECL(dispatch_queue);
// typedef struct dispatch_queue_s *dispatch_queue_t;
//这行代码定义了一个 dispatch_queue_t 类型的指针，指向一个 dispatch_queue_s 类型的结构体。


/*!
 * @typedef dispatch_queue_attr_t
 *
 * @abstract
 * Attribute for dispatch queues.
 */
DISPATCH_DECL(dispatch_queue_attr);

/*!
 * @typedef dispatch_block_t
 *
 * @abstract
 * The prototype of blocks submitted to dispatch queues, which take no
 * arguments and have no return value.
 *
 * @discussion
 * The declaration of a block allocates storage on the stack. Therefore, this
 * is an invalid construct:
 *
 * dispatch_block_t block;
 *
 * if (x) {
 *     block = ^{ printf("true\n"); };
 * } else {
 *     block = ^{ printf("false\n"); };
 * }
 * block(); // unsafe!!!
 *
 * What is happening behind the scenes:
 *
 * if (x) {
 *     struct Block __tmp_1 = ...; // setup details
 *     block = &__tmp_1;
 * } else {
 *     struct Block __tmp_2 = ...; // setup details
 *     block = &__tmp_2;
 * }
 *
 * As the example demonstrates, the address of a stack variable is escaping the
 * scope in which it is allocated. That is a classic C bug.
 */
#ifdef __BLOCKS__
typedef void (^dispatch_block_t)(void);
#endif

__BEGIN_DECLS

/*!
 * @function dispatch_async
 *
 * @abstract
 * Submits a block for asynchronous execution on a dispatch queue.
 *
 * @discussion
 * The dispatch_async() function is the fundamental mechanism for submitting
 * blocks to a dispatch queue.
 *
 * Calls to dispatch_async() always return immediately after the block has
 * been submitted, and never wait for the block to be invoked.
 *
 * The target queue determines whether the block will be invoked serially or
 * concurrently with respect to other blocks submitted to that same queue.
 * Serial queues are processed concurrently with respect to each other.
 *
 * @param queue
 * The target dispatch queue to which the block is submitted.
 * The system will hold a reference on the target queue until the block
 * has finished.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block to submit to the target dispatch queue. This function performs
 * Block_copy() and Block_release() on behalf of callers.
 * The result of passing NULL in this parameter is undefined.
 */
#ifdef __BLOCKS__
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_NOTHROW
void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);
#endif

/*!
 * @function dispatch_async_f
 *
 * @abstract
 * Submits a function for asynchronous execution on a dispatch queue.
 *
 * @discussion
 * See dispatch_async() for details.
 *
 * @param queue
 * The target dispatch queue to which the function is submitted.
 * The system will hold a reference on the target queue until the function
 * has returned.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param context
 * The application-defined context parameter to pass to the function.
 *
 * @param work
 * The application-defined function to invoke on the target queue. The first
 * parameter passed to this function is the context provided to
 * dispatch_async_f().
 * The result of passing NULL in this parameter is undefined.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL1 DISPATCH_NONNULL3 DISPATCH_NOTHROW
void dispatch_async_f(dispatch_queue_t queue,void *context,dispatch_function_t work);

/*!
 * @function dispatch_sync
 *
 * @abstract
 * Submits a block for synchronous execution on a dispatch queue.
 *
 * @discussion
 * Submits a block to a dispatch queue like dispatch_async(), however
 * dispatch_sync() will not return until the block has finished.
 *
 * Calls to dispatch_sync() targeting the current queue will result
 * in dead-lock. Use of dispatch_sync() is also subject to the same
 * multi-party dead-lock problems that may result from the use of a mutex.
 * Use of dispatch_async() is preferred.
 *
 * Unlike dispatch_async(), no retain is performed on the target queue. Because
 * calls to this function are synchronous, the dispatch_sync() "borrows" the
 * reference of the caller.
 *
 * As an optimization, dispatch_sync() invokes the block on the current
 * thread when possible.
 *
 * @param queue
 * The target dispatch queue to which the block is submitted.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block to be invoked on the target dispatch queue.
 * The result of passing NULL in this parameter is undefined.
 */
#ifdef __BLOCKS__
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_NOTHROW
void dispatch_sync(dispatch_queue_t queue, dispatch_block_t block);
#endif

/*!
 * @function dispatch_sync_f
 *
 * @abstract
 * Submits a function for synchronous execution on a dispatch queue.
 *
 * @discussion
 * See dispatch_sync() for details.
 *
 * @param queue
 * The target dispatch queue to which the function is submitted.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param context
 * The application-defined context parameter to pass to the function.
 *
 * @param work
 * The application-defined function to invoke on the target queue. The first
 * parameter passed to this function is the context provided to
 * dispatch_sync_f().
 * The result of passing NULL in this parameter is undefined.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL1 DISPATCH_NONNULL3 DISPATCH_NOTHROW
void dispatch_sync_f(dispatch_queue_t queue,void *context,dispatch_function_t work);

/*!
 * @function dispatch_apply
 *
 * @abstract
 * Submits a block to a dispatch queue for multiple invocations.
 *
 * @discussion
 * Submits a block to a dispatch queue for multiple invocations. This function
 * waits for the task block to complete before returning. If the target queue
 * is concurrent, the block may be invoked concurrently, and it must therefore
 * be reentrant safe.
 *
 * Each invocation of the block will be passed the current index of iteration.
 *
 * @param iterations
 * The number of iterations to perform.
 *
 * @param queue
 * The target dispatch queue to which the block is submitted.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block to be invoked the specified number of iterations.
 * The result of passing NULL in this parameter is undefined.
 */
#ifdef __BLOCKS__
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_NOTHROW
void dispatch_apply(size_t iterations, dispatch_queue_t queue,void (^block)(size_t));
#endif

/*!
 * @function dispatch_apply_f
 *
 * @abstract
 * Submits a function to a dispatch queue for multiple invocations.
 *
 * @discussion
 * See dispatch_apply() for details.
 *
 * @param iterations
 * The number of iterations to perform.
 *
 * @param queue
 * The target dispatch queue to which the function is submitted.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param context
 * The application-defined context parameter to pass to the function.
 *
 * @param work
 * The application-defined function to invoke on the target queue. The first
 * parameter passed to this function is the context provided to
 * dispatch_apply_f(). The second parameter passed to this function is the
 * current index of iteration.
 * The result of passing NULL in this parameter is undefined.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL2 DISPATCH_NONNULL4 DISPATCH_NOTHROW
void dispatch_apply_f(size_t iterations, dispatch_queue_t queue,void *context,void (*work)(void *, size_t));

/*! 获取当前正在运行的队列
 *
 * @abstract
 * dispatch_queue 是按照层级结构来组织的，无论是串行还是并发队列，只要有targetq，都会一层层地向上追溯，直到线程池。 所以无法单用某个队列对象来描述 “当前队列” 这一概念的！
 *
 *
 * @discussion 在 Block 之外调用 dispatch_get_current_queue() 时，默认返回全局并发队列
 *
 * @note 在 iOS 6 之后被废弃：无法返回期望的队列，可能造成死锁
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_PURE DISPATCH_WARN_RESULT DISPATCH_NOTHROW
dispatch_queue_t dispatch_get_current_queue(void);

/*!
 * @function dispatch_get_main_queue
 *
 * @abstract
 * Returns the default queue that is bound to the main thread.
 *
 * @discussion
 * In order to invoke blocks submitted to the main queue, the application must
 * call dispatch_main(), NSApplicationMain(), or use a CFRunLoop on the main
 * thread.
 *
 * @result
 * Returns the main queue. This queue is created automatically on behalf of
 * the main thread before main() is called.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT struct dispatch_queue_s _dispatch_main_q;
#define dispatch_get_main_queue() (&_dispatch_main_q)

/*!
 * @typedef dispatch_queue 队列优先级
 * 数据类型为 dispatch_queue_priority ，即 long 类型
 *
 * @constant DISPATCH_QUEUE_PRIORITY_HIGH    最高优先级，该队列将在任何比它优先级低的队列之前调度执行；
 * @constant DISPATCH_QUEUE_PRIORITY_DEFAULT 默认优先级
 * @constant DISPATCH_QUEUE_PRIORITY_LOW     低优先级，队列将在所有默认优先级和高优先级队列被调度之后调度执行。
 * @constant DISPATCH_QUEUE_PRIORITY_BACKGROUND 后台优先级，优先级被设置为最低
 */
#define DISPATCH_QUEUE_PRIORITY_HIGH 2
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
#define DISPATCH_QUEUE_PRIORITY_LOW (-2)
#define DISPATCH_QUEUE_PRIORITY_BACKGROUND INT16_MIN

typedef long dispatch_queue_priority_t;

/** 获取全局队列
* @param priority 优先级
* @param flags 是否创建线程
* @discussion 不能修改全局并发队列。调用dispatch_suspend()、dispatch_resume()、dispatch_set_context()等函数对全局队列没有影响。
*/
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_CONST DISPATCH_WARN_RESULT DISPATCH_NOTHROW
dispatch_queue_t dispatch_get_global_queue(dispatch_queue_priority_t priority,unsigned long flags);

/*!
 * @const DISPATCH_QUEUE_SERIAL
 * @discussion 串行队列，队列中的任务按先进先出的顺序连续执行
 */
#define DISPATCH_QUEUE_SERIAL NULL

/*!
 * @const DISPATCH_QUEUE_CONCURRENT
 * @discussion 并发队列；虽然它们同时执行任务，但可以使用 dispatch_barrier() 在队列中创建同步点
 */
#define DISPATCH_QUEUE_CONCURRENT (&_dispatch_queue_attr_concurrent)
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_4_3)
DISPATCH_EXPORT
struct dispatch_queue_attr_s _dispatch_queue_attr_concurrent;


/** 创建一个调度队列，默认优先级DISPATCH_QUEUE_PRIORITY_DEFAULT
 * @param label 队列的标识，可以为 NULL
 * @param attr DISPATCH_QUEUE_SERIAL or DISPATCH_QUEUE_CONCURRENT.
 *
 * @abstract 该函数主要执行了三个功能：
 * 			 1、配置唯一标识，并拷贝至新队列；
 * 			 2、分配内存并初始化队列，该队列是串行队列；
 * 		     3、对于并发队列，需要额外设置 dq_width 、do_targetq ；
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_MALLOC DISPATCH_WARN_RESULT DISPATCH_NOTHROW
dispatch_queue_t dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);

/** 获取队列的标识，可能为 NULL
 * @param queue 指定的队列
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_PURE DISPATCH_WARN_RESULT
DISPATCH_NOTHROW const char * dispatch_queue_get_label(dispatch_queue_t queue);

/*! 传递给dispatch_set_target_queue()和dispatch_source_create()函数的常量，以指示应该使用给定对象类型的默认目标队列。
 */
#define DISPATCH_TARGET_QUEUE_DEFAULT NULL

/*!
 * dispatch_queue_t 的优先级从其目标队列继承；
 *
 * 提交到目标队列是另一个串行队列的串行队列的块不会与提交到目标队列或具有相同目标队列的任何其他队列的块并发调用。
 *
 * 在目标队列的层次结构中引入循环的结果是未定义的。
 *
 * 分派源的目标队列指定将在何处提交其事件处理程序和取消处理程序块。
 *
 * Blocks submitted to a serial queue whose target queue is another serial queue will not be invoked concurrently with blocks submitted to the target queue or to any other queue with that same target queue.
 *
 * The result of introducing a cycle into the hierarchy of target queues is undefined.
 *
 * A dispatch source's target queue specifies where its event handler and cancellation handler blocks will be submitted.
 *
 * A dispatch I/O channel's target queue specifies where where its I/O
 * operations are executed.
 *
 * For all other dispatch object types, the only function of the target queue
 * is to determine where an object's finalizer function is invoked.
 *
 * @param object
 * The object to modify.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param queue
 * The new target queue for the object. The queue is retained, and the
 * previous target queue, if any, is released.
 * If queue is DISPATCH_TARGET_QUEUE_DEFAULT, set the object's target queue
 * to the default target queue for the given object type.
 */
/** 设置指定对象的目标队列 -> 更改队列优先级
 * @param object 要修改的对象,不能为空；
 * @param queue 对象的新目标队列，不能为空。
 * @note 该函数不仅可以设置优先级，还能够创建队列的层次体系；
 *       当我们需要不同队列中的任务同步执行时，可以创建一个串行队列 queue_A ，然后将这些队列的 do_targetq 指向 queue_A
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NOTHROW // DISPATCH_NONNULL1
void dispatch_set_target_queue(dispatch_object_t object, dispatch_queue_t queue);

/*!
 * @function dispatch_main
 *
 * @abstract
 * Execute blocks submitted to the main queue.
 *
 * @discussion
 * This function "parks" the main thread and waits for blocks to be submitted
 * to the main queue. This function never returns.
 *
 * Applications that call NSApplicationMain() or CFRunLoopRun() on the
 * main thread do not need to call dispatch_main().
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NOTHROW DISPATCH_NORETURN
void dispatch_main(void);

/*!
 * @function dispatch_after
 *
 * @abstract
 * Schedule a block for execution on a given queue at a specified time.
 *
 * @discussion
 * Passing DISPATCH_TIME_NOW as the "when" parameter is supported, but not as
 * optimal as calling dispatch_async() instead. Passing DISPATCH_TIME_FOREVER
 * is undefined.
 *
 * @param when
 * A temporal milestone returned by dispatch_time() or dispatch_walltime().
 *
 * @param queue
 * A queue to which the given block will be submitted at the specified time.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block of code to execute.
 * The result of passing NULL in this parameter is undefined.
 */
/** 在指定的时间执行任务；不会堵塞当前线程的执行
 * @param when 将任务添加到队列中的时间（不是在指定时间之后开始处理任务）
 *        这个时间并不精准，只是大致延迟
 * @param queue 处理任务的队列，不能为空
 * @param block 要处理的任务，不能为空
 */
#ifdef __BLOCKS__
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL2 DISPATCH_NONNULL3 DISPATCH_NOTHROW
void dispatch_after(dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t block);
#endif

/*!
 * @function dispatch_after_f
 *
 * @abstract
 * Schedule a function for execution on a given queue at a specified time.
 *
 * @discussion
 * See dispatch_after() for details.
 *
 * @param when
 * A temporal milestone returned by dispatch_time() or dispatch_walltime().
 *
 * @param queue
 * A queue to which the given function will be submitted at the specified time.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param context
 * The application-defined context parameter to pass to the function.
 *
 * @param work
 * The application-defined function to invoke on the target queue. The first
 * parameter passed to this function is the context provided to
 * dispatch_after_f().
 * The result of passing NULL in this parameter is undefined.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_6,__IPHONE_4_0)
DISPATCH_EXPORT DISPATCH_NONNULL2 DISPATCH_NONNULL4 DISPATCH_NOTHROW
void dispatch_after_f(dispatch_time_t when,dispatch_queue_t queue,void *context,dispatch_function_t work);

/*!
 * @functiongroup Dispatch Barrier API
 * The dispatch barrier API is a mechanism for submitting barrier blocks to a
 * dispatch queue, analogous to the dispatch_async()/dispatch_sync() API.
 * It enables the implementation of efficient reader/writer schemes.
 * Barrier blocks only behave specially when submitted to queues created with
 * the DISPATCH_QUEUE_CONCURRENT attribute; on such a queue, a barrier block
 * will not run until all blocks submitted to the queue earlier have completed,
 * and any blocks submitted to the queue after a barrier block will not run
 * until the barrier block has completed.
 * When submitted to a a global queue or to a queue not created with the
 * DISPATCH_QUEUE_CONCURRENT attribute, barrier blocks behave identically to
 * blocks submitted with the dispatch_async()/dispatch_sync() API.
 */

/*!
 * @function dispatch_barrier_async
 *
 * @abstract
 * Submits a barrier block for asynchronous execution on a dispatch queue.
 *
 * @discussion
 * Submits a block to a dispatch queue like dispatch_async(), but marks that block as a barrier (relevant only on DISPATCH_QUEUE_CONCURRENT queues).
 * 类似 dispatch_async() 向 queue 提交一个 block，但将 block 标记为一个界线
 * 仅仅与 DISPATCH_QUEUE_CONCURRENT 队列相关
 *
 * See dispatch_async() for details.
 *
 * @param queue
 * The target dispatch queue to which the block is submitted.
 * The system will hold a reference on the target queue until the block has finished.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block to submit to the target dispatch queue. This function performs
 * Block_copy() and Block_release() on behalf of callers.
 * The result of passing NULL in this parameter is undefined.
 */
/** 设置 barrier：就好比在一条直线上添加了一个间隔点
 *    针对队列 queue 的任务，系统会先执行 barrier 之前所有的任务；
 *          执行完毕之后，执行 barrier 点的 代码块
 *          barrier 点的代码块执行完毕，执行 barrier 点之后的任务
 * 设置 barrier 的两种方式：
 *    同步设置 barrier：  会堵塞当前线程；barrier 代码块在当前线程执行；
 *    异步设置 barrier：不会堵塞当前线程；barrier 代码块开辟新线程执行；
 * @param queue 设置 barrier 的队列
 * @param block barrier 点需要执行的代码
 */
#ifdef __BLOCKS__
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_4_3)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_NOTHROW
void dispatch_barrier_async(dispatch_queue_t queue, dispatch_block_t block);
#endif

/*!
 * @function dispatch_barrier_async_f
 *
 * @abstract
 * Submits a barrier function for asynchronous execution on a dispatch queue.
 *
 * @discussion
 * Submits a function to a dispatch queue like dispatch_async_f(), but marks
 * that function as a barrier (relevant only on DISPATCH_QUEUE_CONCURRENT
 * queues).
 *
 * See dispatch_async_f() for details.
 *
 * @param queue
 * The target dispatch queue to which the function is submitted.
 * The system will hold a reference on the target queue until the function
 * has returned.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param context
 * The application-defined context parameter to pass to the function.
 *
 * @param work
 * The application-defined function to invoke on the target queue. The first
 * parameter passed to this function is the context provided to
 * dispatch_barrier_async_f().
 * The result of passing NULL in this parameter is undefined.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_4_3)
DISPATCH_EXPORT DISPATCH_NONNULL1 DISPATCH_NONNULL3 DISPATCH_NOTHROW
void
dispatch_barrier_async_f(dispatch_queue_t queue,
	void *context,
	dispatch_function_t work);

/*!
 * @function dispatch_barrier_sync
 *
 * @abstract
 * Submits a barrier block for synchronous execution on a dispatch queue.
 *
 * @discussion
 * Submits a block to a dispatch queue like dispatch_sync(), but marks that
 * block as a barrier (relevant only on DISPATCH_QUEUE_CONCURRENT queues).
 *
 * See dispatch_sync() for details.
 *
 * @param queue
 * The target dispatch queue to which the block is submitted.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param block
 * The block to be invoked on the target dispatch queue.
 * The result of passing NULL in this parameter is undefined.
 */
#ifdef __BLOCKS__
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_4_3)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_NOTHROW
void
dispatch_barrier_sync(dispatch_queue_t queue, dispatch_block_t block);
#endif

/*!
 * @function dispatch_barrier_sync_f
 *
 * @abstract
 * Submits a barrier function for synchronous execution on a dispatch queue.
 *
 * @discussion
 * Submits a function to a dispatch queue like dispatch_sync_f(), but marks that
 * fuction as a barrier (relevant only on DISPATCH_QUEUE_CONCURRENT queues).
 *
 * See dispatch_sync_f() for details.
 *
 * @param queue
 * The target dispatch queue to which the function is submitted.
 * The result of passing NULL in this parameter is undefined.
 *
 * @param context
 * The application-defined context parameter to pass to the function.
 *
 * @param work
 * The application-defined function to invoke on the target queue. The first
 * parameter passed to this function is the context provided to
 * dispatch_barrier_sync_f().
 * The result of passing NULL in this parameter is undefined.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_4_3)
DISPATCH_EXPORT DISPATCH_NONNULL1 DISPATCH_NONNULL3 DISPATCH_NOTHROW
void
dispatch_barrier_sync_f(dispatch_queue_t queue,
	void *context,
	dispatch_function_t work);

/*! 怎么判断当前队列是指定队列？
 * @functiongroup Dispatch queue-specific contexts
 * 这个API允许不同的子系统将上下文关联到一个共享队列，而不存在冲突风险，并且可以从在该队列上执行的块或目标队列层次结构中的任何子队列中检索该上下文。
 * This API allows different subsystems to associate context to a shared queue without risk of collision and to retrieve that context from blocks executing on that queue or any of its child queues in the target queue hierarchy.
 */

/*! 向指定队列里面设置一个标识
 * @function dispatch_queue_set_specific
 *
 * @abstract 将任意数据以键值对的形式关联到队列中；
 * 通过键值对，就可以判断当前执行的任务是否包含在某个队列中，因为系统会根据给定的键，沿着队列的层级体系（即父队列）进行查找键所对应的值，如果到根队列还没找到，就说明当前任务不包含在你要判断的队列中，进而可以避免（1）中描述的死锁问题
 * 简单理解就是：给某个队列加个标记，找到这个标记就说明包含在这个队列中
 *
 * @param queue 待设置标记的调度队列；不能传递 NULL
 * @param key 标记的键；通常是一个静态变量的指针
 * @param context 标记的值，可能为 NULL。注意，这里键和值是指针，即地址，故context中可以放任何数据，但必须手动管理context的内存；
 * @param destructor 析构函数，可能为 NULL！所在队列内存被回收，或者context值改变时，会被调用；
 */
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_5_0)
DISPATCH_EXPORT DISPATCH_NONNULL1 DISPATCH_NONNULL2 DISPATCH_NOTHROW
void dispatch_queue_set_specific(dispatch_queue_t queue, const void *key,void *context, dispatch_function_t destructor);

/*! 获取指定调度队列的键/值数据
 *
 * @param queue 要查询的调度队列；不能传递 NULL 。
 * @param key 指定的键；
 * @result 指定键的值，如果没有找到则为NULL。
 */
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_5_0)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_PURE DISPATCH_WARN_RESULT
DISPATCH_NOTHROW
void *dispatch_queue_get_specific(dispatch_queue_t queue, const void *key);

/*! 获取当前调度队列的键/值数据
 * @param key 指定的键；
 *
 * @discussion 如果当前队列是主队列、或者全局并发队列 ，则返回NULL；
 * @abstract 从当前队列开始，沿着目标队列 do_targetq 向上回溯，直到找到对应键的值；
 * 			 如果找到主队列、或者全局并发队列，也没有找到对应键的值，则返回  NULL；
 * 			 因为主队列、或者全局并发队列 的 do_targetq 为 NULL；
 */
__OSX_AVAILABLE_STARTING(__MAC_10_7,__IPHONE_5_0)
DISPATCH_EXPORT DISPATCH_NONNULL_ALL DISPATCH_PURE DISPATCH_WARN_RESULT
DISPATCH_NOTHROW
void *dispatch_get_specific(const void *key);

__END_DECLS

#endif
