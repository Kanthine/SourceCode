/** Runloop本质：通过mach_msg()函数接收、发送消息
  * 它的本质是调用函数mach_msg_trap()，相当于是一个系统调用，会触发内核状态切换。当你在用户态调用 mach_msg_trap() 时会触发陷阱机制，切换到内核态；内核态中内核实现的 mach_msg() 函数会完成实际的工作。
 */

/** RunLoop 只处理两种源：输入源、时间源
 * 时间源 CFRunLoopTimerRef：基于时间的触发器，在预设时间点唤醒RunLoop执行回调；上层对应NSTimer；
 *       属于端口事件源，所有的Timer 共用一个端口(Timer Port)；
 *       由于RunLoop只负责分发源的消息，因此它不是实时的；如果线程当前正在处理繁重的任务，有可能导致Timer本次延时，或者少执行一次。
 *
 * 输入源：CFRunLoopSourceRef 分为三类:
 *    1、基于端口的事件源：也称为source1事件，通过内核和其他线程通信，每个Source1都有不同的对应端口；
 *                     由 mach_port 驱动：如CFMachPort、CFMessagePort、NSSocketPort；
 *                     接收到事件后包装为source0事件后分发给其他线程处理。
 *    2、自定义事件源：使用CFRunLoopSourceCreate()函数来创建自定义输入源,一般用不到
 *    3、performSelector 事件源：用户自定义调用诸如 -perfromSelector:onThread: 方法产生的source0事件
 *
 * CFRunLoopSourceRef 按照调用栈分为 Source0 和 Source1：
 *  source0：不基于端口的，负责App内部事件，由App负责管理触发，例如UIEvent、UITouch事件。只包含了一个用于回调的函数指针，不能主动触发事件。
 *      使用时，首先调用CFRunLoopSourceSignal()将这个Source标记为待处理，然后调用CFRunLoopWakeUp(runloop)唤醒RunLoop处理这个事件。
 *  source1：基于端口，包含一个 mach_port 和一个回调，可监听系统端口和通过内核和其他线程发送的消息，能主动唤醒RunLoop，接收分发系统事件。
 *
 *
 * @note Mach port 是一个轻量级的进程间通讯通道，
 *       假如同时有几个进程都挂在这个通道上，那么其它进程向这个通道发送消息后，这些挂在这个通道上的进程都可以收到相应的消息。
 *       Mach port是RunLoop与系统内核进行消息通讯的窗口，是RunLoop休眠和被唤醒的关键。
 */


/** CFRunLoopObserverRef 观察者，通过回调接收RunLoop状态变化。它不属于RunLoop的事件源。
*/

/** CFRunLoopModeRef 每次启动RunLoop时，只能指定其中一个Mode，这个就是CurrentMode。要切换 Mode，只能退出 Loop，再重新指定一个 Mode 进入。
 * RunLoopMode 只能添加不能删除；
 *
 * 系统默认提供了五种 RunLoopMode:
 *   kCFRunLoopDefaultMode 默认运行模式
 *   UITrackingRunLoopMode 只有当用户滑动屏幕时才会执行该模式；
 *           此时，不在该模式内的Source/Timer/Observer都不会得到执行，专注于滑动时产生的各种事件保证滑动时不受其他事件处理的影响，保证丝滑；
 *           通过这样的方式就可以保证用户在滑动页面时的流畅性，这也是分不同Mode的优点。
 * UIInitializationRunLoopMode 启动应用时的运行模式，应用启动完成后就不会再使用
 * GSEventReceiveRunLoopMode  事件接收运行模式
 * kCFRunLoopCommonModes 即 NSRunLoopCommonModes，是一种标记的模式而非真正意义上的mode，还需要上述四种模式的支持
 *
 * 一个RunLoopMode可以使用CFRunLoopAddCommonMode()函数标记为common属性，然后它就会保存在_commonModes。
 * 主线程已有的两个kCFRunLoopDefaultMode 和 UITrackingRunLoopMode 都已经是CommonModes了。
*/

#if !defined(__COREFOUNDATION_CFRUNLOOP__)
#define __COREFOUNDATION_CFRUNLOOP__ 1

#include <CoreFoundation/CFBase.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFDate.h>
#include <CoreFoundation/CFString.h>
#if (TARGET_OS_MAC && !(TARGET_OS_EMBEDDED || TARGET_OS_IPHONE)) || (TARGET_OS_EMBEDDED || TARGET_OS_IPHONE)
#include <mach/port.h>
#endif

CF_IMPLICIT_BRIDGING_ENABLED
CF_EXTERN_C_BEGIN

/** RunLoop 的几个关键类：
 * 1、CFRunLoopRef: 每个线程对应唯一的 RunLoop
 * 2、CFRunLoopModeRef 每个RunLoop中有多个 Mode，负责RunLoop的运行 ；每个 Mode 都包含事件源 Source，时间 Timer ，监听者 Observer
 * 3、CFRunLoopSourceRef RunLoop对应的事件
 * 4、CFRunLoopTimerRef  基于时间的触发器
 * 5、CFRunLoopObserverRef RunLoop状态监测者
 */
typedef struct __CFRunLoop * CFRunLoopRef;
typedef struct __CFRunLoopSource * CFRunLoopSourceRef;
typedef struct __CFRunLoopObserver * CFRunLoopObserverRef;
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSTimer) __CFRunLoopTimer * CFRunLoopTimerRef;

/* Reasons for CFRunLoopRunInMode() to Return */
enum {
    kCFRunLoopRunFinished = 1,
    kCFRunLoopRunStopped = 2,
    kCFRunLoopRunTimedOut = 3,
    kCFRunLoopRunHandledSource = 4
};

/* CFRunLoopObserverRef 主要作用就是监视 RunLoop 的生命周期和活动变化,
 * RunLoop的创建 -> 运行 -> 挂起 -> 唤醒 -> .... -> 死亡。
 * RunLoop 在每次运行循环中把自己的状态变化通过注册回调指针告诉对应的 observer,
 * 这样它的每一次状态变化时,observer 都能通过回调指针获取它对应的状态,进行相关的处理。
 * 以下枚举是runLoop的活动变化，观察的时间点。
*/
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0),           // 即将进入Loop
    kCFRunLoopBeforeTimers = (1UL << 1),    // 即将处理 Timer
    kCFRunLoopBeforeSources = (1UL << 2),   // 即将处理 Source
    kCFRunLoopBeforeWaiting = (1UL << 5),   // 即将进入休眠
    kCFRunLoopAfterWaiting = (1UL << 6),    // 刚从休眠中唤醒
    kCFRunLoopExit = (1UL << 7),            // 即将退出Loop
    kCFRunLoopAllActivities = 0x0FFFFFFFU   //监听RunLoop的全部状态
};

/** 一个 RunLoop 包含若干的Mode,常用的有 NSDefaultRunLoopMode,UITrackingRunLoopMode；
*/
CF_EXPORT const CFStringRef kCFRunLoopDefaultMode;
CF_EXPORT const CFStringRef kCFRunLoopCommonModes;

CF_EXPORT CFTypeID CFRunLoopGetTypeID(void);

CF_EXPORT CFRunLoopRef CFRunLoopGetCurrent(void);//获取当前线程对应的 RunLoop
CF_EXPORT CFRunLoopRef CFRunLoopGetMain(void);//获取主线程对应的 RunLoop

CF_EXPORT CFStringRef CFRunLoopCopyCurrentMode(CFRunLoopRef rl);

CF_EXPORT CFArrayRef CFRunLoopCopyAllModes(CFRunLoopRef rl);

CF_EXPORT void CFRunLoopAddCommonMode(CFRunLoopRef rl, CFStringRef mode);

CF_EXPORT CFAbsoluteTime CFRunLoopGetNextTimerFireDate(CFRunLoopRef rl, CFStringRef mode);

/** 程序启动时指定的 RunLoop ，方法内部用 DefaultMode 启动
 */
CF_EXPORT void CFRunLoopRun(void);

/** 用指定的Mode启动，允许设置RunLoop超时时间
 */
CF_EXPORT SInt32 CFRunLoopRunInMode(CFStringRef mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled);

/** RunLoop 是否休眠
*/
CF_EXPORT Boolean CFRunLoopIsWaiting(CFRunLoopRef rl);

/** 唤醒RunLoop
 */
CF_EXPORT void CFRunLoopWakeUp(CFRunLoopRef rl);

/** 停止RunLoop
 */
CF_EXPORT void CFRunLoopStop(CFRunLoopRef rl);

#if __BLOCKS__
CF_EXPORT void CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^block)(void)) CF_AVAILABLE(10_6, 4_0); 
#endif

/***************** Mode 暴露的管理 mode item 的接口 ****************/
CF_EXPORT Boolean CFRunLoopContainsSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode);
CF_EXPORT void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode);
CF_EXPORT void CFRunLoopRemoveSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode);

CF_EXPORT Boolean CFRunLoopContainsObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFStringRef mode);
CF_EXPORT void CFRunLoopAddObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFStringRef mode);
CF_EXPORT void CFRunLoopRemoveObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFStringRef mode);

CF_EXPORT Boolean CFRunLoopContainsTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFStringRef mode);
CF_EXPORT void CFRunLoopAddTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFStringRef mode);
CF_EXPORT void CFRunLoopRemoveTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFStringRef mode);


typedef struct {
    CFIndex	version;
    void *	info;
    const void *(*retain)(const void *info);
    void	(*release)(const void *info);
    CFStringRef	(*copyDescription)(const void *info);
    Boolean	(*equal)(const void *info1, const void *info2);
    CFHashCode	(*hash)(const void *info);
    void	(*schedule)(void *info, CFRunLoopRef rl, CFStringRef mode);
    void	(*cancel)(void *info, CFRunLoopRef rl, CFStringRef mode);
    void	(*perform)(void *info);
} CFRunLoopSourceContext;

typedef struct {
    CFIndex	version;
    void *	info;
    const void *(*retain)(const void *info);
    void	(*release)(const void *info);
    CFStringRef	(*copyDescription)(const void *info);
    Boolean	(*equal)(const void *info1, const void *info2);
    CFHashCode	(*hash)(const void *info);
#if (TARGET_OS_MAC && !(TARGET_OS_EMBEDDED || TARGET_OS_IPHONE)) || (TARGET_OS_EMBEDDED || TARGET_OS_IPHONE)
    mach_port_t	(*getPort)(void *info);
    void *	(*perform)(void *msg, CFIndex size, CFAllocatorRef allocator, void *info);
#else
    void *	(*getPort)(void *info);
    void	(*perform)(void *info);
#endif
} CFRunLoopSourceContext1;

CF_EXPORT CFTypeID CFRunLoopSourceGetTypeID(void);

CF_EXPORT CFRunLoopSourceRef CFRunLoopSourceCreate(CFAllocatorRef allocator, CFIndex order, CFRunLoopSourceContext *context);

CF_EXPORT CFIndex CFRunLoopSourceGetOrder(CFRunLoopSourceRef source);
CF_EXPORT void CFRunLoopSourceInvalidate(CFRunLoopSourceRef source);
CF_EXPORT Boolean CFRunLoopSourceIsValid(CFRunLoopSourceRef source);
CF_EXPORT void CFRunLoopSourceGetContext(CFRunLoopSourceRef source, CFRunLoopSourceContext *context);
CF_EXPORT void CFRunLoopSourceSignal(CFRunLoopSourceRef source);

typedef struct {
    CFIndex	version;
    void *	info;
    const void *(*retain)(const void *info);
    void	(*release)(const void *info);
    CFStringRef	(*copyDescription)(const void *info);
} CFRunLoopObserverContext;

typedef void (*CFRunLoopObserverCallBack)(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info);

CF_EXPORT CFTypeID CFRunLoopObserverGetTypeID(void);

CF_EXPORT CFRunLoopObserverRef CFRunLoopObserverCreate(CFAllocatorRef allocator, CFOptionFlags activities, Boolean repeats, CFIndex order, CFRunLoopObserverCallBack callout, CFRunLoopObserverContext *context);
#if __BLOCKS__
CF_EXPORT CFRunLoopObserverRef CFRunLoopObserverCreateWithHandler(CFAllocatorRef allocator, CFOptionFlags activities, Boolean repeats, CFIndex order, void (^block) (CFRunLoopObserverRef observer, CFRunLoopActivity activity)) CF_AVAILABLE(10_7, 5_0);
#endif

CF_EXPORT CFOptionFlags CFRunLoopObserverGetActivities(CFRunLoopObserverRef observer);
CF_EXPORT Boolean CFRunLoopObserverDoesRepeat(CFRunLoopObserverRef observer);
CF_EXPORT CFIndex CFRunLoopObserverGetOrder(CFRunLoopObserverRef observer);
CF_EXPORT void CFRunLoopObserverInvalidate(CFRunLoopObserverRef observer);
CF_EXPORT Boolean CFRunLoopObserverIsValid(CFRunLoopObserverRef observer);
CF_EXPORT void CFRunLoopObserverGetContext(CFRunLoopObserverRef observer, CFRunLoopObserverContext *context);

typedef struct {
    CFIndex	version;
    void *	info;
    const void *(*retain)(const void *info);
    void	(*release)(const void *info);
    CFStringRef	(*copyDescription)(const void *info);
} CFRunLoopTimerContext;

typedef void (*CFRunLoopTimerCallBack)(CFRunLoopTimerRef timer, void *info);

CF_EXPORT CFTypeID CFRunLoopTimerGetTypeID(void);

CF_EXPORT CFRunLoopTimerRef CFRunLoopTimerCreate(CFAllocatorRef allocator, CFAbsoluteTime fireDate, CFTimeInterval interval, CFOptionFlags flags, CFIndex order, CFRunLoopTimerCallBack callout, CFRunLoopTimerContext *context);
#if __BLOCKS__
CF_EXPORT CFRunLoopTimerRef CFRunLoopTimerCreateWithHandler(CFAllocatorRef allocator, CFAbsoluteTime fireDate, CFTimeInterval interval, CFOptionFlags flags, CFIndex order, void (^block) (CFRunLoopTimerRef timer)) CF_AVAILABLE(10_7, 5_0);
#endif

CF_EXPORT CFAbsoluteTime CFRunLoopTimerGetNextFireDate(CFRunLoopTimerRef timer);
CF_EXPORT void CFRunLoopTimerSetNextFireDate(CFRunLoopTimerRef timer, CFAbsoluteTime fireDate);
CF_EXPORT CFTimeInterval CFRunLoopTimerGetInterval(CFRunLoopTimerRef timer);
CF_EXPORT Boolean CFRunLoopTimerDoesRepeat(CFRunLoopTimerRef timer);
CF_EXPORT CFIndex CFRunLoopTimerGetOrder(CFRunLoopTimerRef timer);
CF_EXPORT void CFRunLoopTimerInvalidate(CFRunLoopTimerRef timer);
CF_EXPORT Boolean CFRunLoopTimerIsValid(CFRunLoopTimerRef timer);
CF_EXPORT void CFRunLoopTimerGetContext(CFRunLoopTimerRef timer, CFRunLoopTimerContext *context);

// Setting a tolerance for a timer allows it to fire later than the scheduled fire date, improving the ability of the system to optimize for increased power savings and responsiveness. The timer may fire at any time between its scheduled fire date and the scheduled fire date plus the tolerance. The timer will not fire before the scheduled fire date. For repeating timers, the next fire date is calculated from the original fire date regardless of tolerance applied at individual fire times, to avoid drift. The default value is zero, which means no additional tolerance is applied. The system reserves the right to apply a small amount of tolerance to certain timers regardless of the value of this property.
// As the user of the timer, you will have the best idea of what an appropriate tolerance for a timer may be. A general rule of thumb, though, is to set the tolerance to at least 10% of the interval, for a repeating timer. Even a small amount of tolerance will have a significant positive impact on the power usage of your application. The system may put a maximum value of the tolerance.
CF_EXPORT CFTimeInterval CFRunLoopTimerGetTolerance(CFRunLoopTimerRef timer) CF_AVAILABLE(10_9, 7_0);
CF_EXPORT void CFRunLoopTimerSetTolerance(CFRunLoopTimerRef timer, CFTimeInterval tolerance) CF_AVAILABLE(10_9, 7_0);

CF_EXTERN_C_END
CF_IMPLICIT_BRIDGING_DISABLED

#endif /* ! __COREFOUNDATION_CFRUNLOOP__ */

