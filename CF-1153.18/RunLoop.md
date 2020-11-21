# Runloop


Runloop本质：通过 mach_msg() 函数接收、发送消息
它的本质是调用函数 mach_msg_trap()，相当于是一个系统调用，会触发内核状态切换。当你在用户态调用 mach_msg_trap() 时会触发陷阱机制，切换到内核态；内核态中内核实现的 mach_msg() 函数会完成实际的工作。


RunLoop 只处理两种源：输入源、时间源：
* 时间源 CFRunLoopTimerRef：基于时间的触发器，在预设时间点唤醒RunLoop执行回调；上层对应 NSTimer；
*       属于端口事件源，所有的 Timer 共用一个端口(Timer Port)；
*       由于RunLoop只负责分发源的消息，因此它不是实时的；如果线程当前正在处理繁重的任务，有可能导致Timer本次延时，或者少执行一次。
 *
 * 输入源：CFRunLoopSourceRef 分为三类:
 *    1、基于端口的事件源：也称为source1事件，通过内核和其他线程通信，每个Source1都有不同的对应端口；
 *                     由 mach_port 驱动：如CFMachPort、CFMessagePort、NSSocketPort；
 *                     接收到事件后包装为source0事件后分发给其他线程处理。
 *    2、自定义事件源：使用CFRunLoopSourceCreate()函数来创建自定义输入源,一般用不到
 *    3、performSelector 事件源：用户自定义调用诸如 -perfromSelector:onThread: 方法产生的 source0 事件
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






RunLoop 的几个关键类：
* 1、CFRunLoopRef: 每个线程对应唯一的 RunLoop
* 2、CFRunLoopModeRef 每个RunLoop中有多个 Mode，负责RunLoop的运行 ；每个 Mode 都包含事件源 Source，时间 Timer ，监听者 Observer
* 3、CFRunLoopSourceRef RunLoop对应的事件
* 4、CFRunLoopTimerRef  基于时间的触发器
* 5、CFRunLoopObserverRef RunLoop状态监测者




小说阅读器的文本展示：使用 CoreText 将文本分页展示！

![文字分页、图文混排、点击事件](https://upload-images.jianshu.io/upload_images/7112462-9ff34d8d0f439531.gif?imageMogr2/auto-orient/strip)


----

参考文章

[第一篇 CoreText的简单了解](https://www.jianshu.com/p/934c32fcdd93)

[第二篇 CoreText 排版与布局](https://www.jianshu.com/p/24c68eb1a892)

[第三篇 CTLineRef 的函数库及使用](https://www.jianshu.com/p/f59e07f95ae9)

[第四篇 图文混排的关键 CTRunRef 与 CTRunDelegate](https://www.jianshu.com/p/d73756d39499)
