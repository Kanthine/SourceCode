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


typedef struct __CFRunLoop * CFRunLoopRef;/// 每个线程对应唯一的 RunLoop
typedef struct __CFRunLoopSource * CFRunLoopSourceRef;/// RunLoop 处理的事件
typedef struct __CFRunLoopObserver * CFRunLoopObserverRef; /// 状态监测者
typedef struct CF_BRIDGED_MUTABLE_TYPE(NSTimer) __CFRunLoopTimer * CFRunLoopTimerRef; /// 基于时间的触发器

/* RunLoop 运行状态 */
enum {
    kCFRunLoopRunFinished = 1,     //完成
    kCFRunLoopRunStopped = 2,      //停止
    kCFRunLoopRunTimedOut = 3,     //超时
    kCFRunLoopRunHandledSource = 4 //处理事件
};

/* CFRunLoopObserverRef 主要作用就是监视 RunLoop 的生命周期和活动变化: 创建 -> 运行 -> 挂起 -> 唤醒 -> .... -> 死亡
 * RunLoop 在每次运行循环中把自己的状态变化通过注册回调指针告诉对应的 Observer；然后 Observer 根据状态进行相关的处理。
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

/** Mode类型都多个,系统暴露在外的就两个，
 * 一个 RunLoop 包含若干的Mode,常用的有 NSDefaultRunLoopMode,UITrackingRunLoopMode；
*/
CF_EXPORT const CFStringRef kCFRunLoopDefaultMode; /// 默认 Mode，主线程在该模式下运行
CF_EXPORT const CFStringRef kCFRunLoopCommonModes;

CF_EXPORT CFTypeID CFRunLoopGetTypeID(void);

CF_EXPORT CFRunLoopRef CFRunLoopGetCurrent(void); ///获取当前线程对应的 RunLoop
CF_EXPORT CFRunLoopRef CFRunLoopGetMain(void);    ///获取主线程对应的 RunLoop

CF_EXPORT CFStringRef CFRunLoopCopyCurrentMode(CFRunLoopRef rl);

CF_EXPORT CFArrayRef CFRunLoopCopyAllModes(CFRunLoopRef rl);

CF_EXPORT void CFRunLoopAddCommonMode(CFRunLoopRef rl, CFStringRef mode);

CF_EXPORT CFAbsoluteTime CFRunLoopGetNextTimerFireDate(CFRunLoopRef rl, CFStringRef mode);



/*************** RunLoop 的状态改变  ****************/

/** 程序启动时指定的 RunLoop
 * 默认使用 DefaultMode 启动
 */
CF_EXPORT void CFRunLoopRun(void);

/** 用指定的Mode启动，允许设置RunLoop超时时间
 * @param mode 指定的模式
 * @param seconds 超时时间
 * @param returnAfterSourceHandled
 */
CF_EXPORT SInt32 CFRunLoopRunInMode(CFStringRef mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled);

CF_EXPORT Boolean CFRunLoopIsWaiting(CFRunLoopRef rl); ///RunLoop 是否休眠
CF_EXPORT void CFRunLoopWakeUp(CFRunLoopRef rl); /// 唤醒休眠的 RunLoop
CF_EXPORT void CFRunLoopStop(CFRunLoopRef rl); ///停止RunLoop

#if __BLOCKS__
CF_EXPORT void CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^block)(void)) CF_AVAILABLE(10_6, 4_0); 
#endif

/***************** Mode 暴露的管理 mode item 的接口 ****************/
CF_EXPORT Boolean CFRunLoopContainsSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode);///是否包含某个事件
CF_EXPORT void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode);///添加事件
CF_EXPORT void CFRunLoopRemoveSource(CFRunLoopRef rl, CFRunLoopSourceRef source, CFStringRef mode);///移除事件

///是否包含某个监测者
CF_EXPORT Boolean CFRunLoopContainsObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFStringRef mode);
CF_EXPORT void CFRunLoopAddObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFStringRef mode); ///添加监测者
CF_EXPORT void CFRunLoopRemoveObserver(CFRunLoopRef rl, CFRunLoopObserverRef observer, CFStringRef mode);///移除监测者

CF_EXPORT Boolean CFRunLoopContainsTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFStringRef mode);
CF_EXPORT void CFRunLoopAddTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFStringRef mode);
CF_EXPORT void CFRunLoopRemoveTimer(CFRunLoopRef rl, CFRunLoopTimerRef timer, CFStringRef mode);

#pragma mark - 事件 Source

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

///创建一个事件
CF_EXPORT CFRunLoopSourceRef CFRunLoopSourceCreate(CFAllocatorRef allocator, CFIndex order, CFRunLoopSourceContext *context);

CF_EXPORT CFIndex CFRunLoopSourceGetOrder(CFRunLoopSourceRef source);
CF_EXPORT void CFRunLoopSourceInvalidate(CFRunLoopSourceRef source);///使事件无效
CF_EXPORT Boolean CFRunLoopSourceIsValid(CFRunLoopSourceRef source);///判断事件是否有效
CF_EXPORT void CFRunLoopSourceGetContext(CFRunLoopSourceRef source, CFRunLoopSourceContext *context);
CF_EXPORT void CFRunLoopSourceSignal(CFRunLoopSourceRef source);


#pragma mark - 监测者 Observer


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


#pragma mark - 计时器 Timer

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



