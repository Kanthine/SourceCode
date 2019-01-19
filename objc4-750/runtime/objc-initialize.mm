/*
 * Copyright (c) 1999-2007 Apple Inc.  All Rights Reserved.
 * 
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/***********************************************************************
* objc-initialize.m
* +initialize support
**********************************************************************/

/* 类初始化期间的线程安全 (GrP 2001-9-24)
 *
 * 初始状态  :清除 CLS_INITIALIZING 和 CLS_INITIALIZED
 * 初始化期间:设置 CLS_INITIALIZING
 * 初始化之后:清除 CLS_INITIALIZING 和 设置 CLS_INITIALIZED
 * CLS_INITIALIZING 和 CLS_INITIALIZED 永远不会同时设置。
 * CLS_INITIALIZED 设置后永远不会被清除。
 *
 * 只允许一个线程实际初始化一个类并发送 +initialize。只允许一个线程设置 CLS_INITIALIZING。
 *
 * 此外，试图向类发送消息的线程必须等待 +initialize 完成。在初始化类期间，该类的方法缓存保持为空。objc_msgSend() 将恢复到class_lookupMethodAndLoadCache，后者在消息传递之前检查 CLS_INITIALIZED。如果CLS_INITIALIZED是清除的，但是设置了CLS_INITIALIZING，那么线程必须阻塞，除非它是首先开始初始化类的线程。
 *
 * 每个线程都有一个正在初始化的类的列表。
 * 全局classInitLock用于同步对CLS_INITIALIZED和CLS_INITIALIZING的更改:到CLS_INITIALIZING的转换必须是相对于自身的原子测试和设置，以及到CLS_INITIALIZED的转换。
 *
 * 全局classInitWaitCond用于阻塞等待初始化完成的线程。classInitLock同步条件检查和条件变量。
 */

/* +initialize 死锁情况，当一个类被标记为初始化，而它的超类被初始化。通过在开始初始化类之前完全初始化超类来解决。
 *
 *
 *  OmniWeb 类层次结构:
 *                 OBObject 
 *                     |    ` OBPostLoader
 *                 OFObject
 *                 /     \
 *      OWAddressEntry  OWController
 *                        | 
 *                      OWConsoleController
 *
 *  Thread 1 (错误的线程测试 ):
 *    initialize OWAddressEntry
 *    super init OFObject
 *    super init OBObject		     
 *    [OBObject initialize] runs OBPostLoader, which inits lots of classes...
 *    initialize OWConsoleController
 *    super init OWController - wait for Thread 2 to finish OWController init
 *
 *  Thread 2 (normal OmniWeb thread):
 *    initialize OWController
 *    super init OFObject - wait for Thread 1 to finish OFObject init
 *
 *  deadlock!
 *
 * 解决方案:在开始初始化子类之前完全初始化父类。然后类层次结构的初始化 +initialized 部分将是一个从根开始的连续子树，因此其他线程不能跳到两个初始化类之间的中间，也不会在超类等待它的子类等待超类时卡住。
 */

#include "objc-private.h"
#include "message.h"
#include "objc-initialize.h"

/* classInitLock 保护 CLS_INITIALIZED 和 CLS_INITIALIZING，并且在任何类完成初始化时发出信号。
 * 正在等待类完成初始化的线程在此等待。
 */
monitor_t classInitLock;


/* 当前由该线程初始化的类的每个线程列表。
 * 在初始化期间，允许该线程向该类发送消息，但其他线程必须等待。
 * 列表是一个简单的元类数组(元类存储初始化状态)。
 */
typedef struct _objc_initializing_classes {
    int classesAllocated;
    Class *metaclasses;
} _objc_initializing_classes;


/* 获取由该线程初始化的类的列表。
 * If create == YES, 当这个线程没有初始化任何类时，创建这个列表。
 * If create ==  NO, 当这个线程没有初始化任何类时，返回nil。
 */
static _objc_initializing_classes *_fetchInitializingClassList(bool create){
    _objc_pthread_data *data;
    _objc_initializing_classes *list;
    Class *classes;

    data = _objc_fetch_pthread_data(create);
    if (data == nil) return nil;

    list = data->initializingClasses;
    if (list == nil) {
        if (!create) {
            return nil;
        } else {
            list = (_objc_initializing_classes *)
                calloc(1, sizeof(_objc_initializing_classes));
            data->initializingClasses = list;
        }
    }

    classes = list->metaclasses;
    if (classes == nil) {
        // 如果 _objc_initializing_classes 存在，分配元类数组，即使create == NO。
        // 在realloc之前，在此线程上允许4个类同时inits。
        list->classesAllocated = 4;
        classes = (Class *)
            calloc(list->classesAllocated, sizeof(Class));
        list->metaclasses = classes;
    }
    return list;
}


/* 释放指定初始化列表使用的内存。
 * 列表的任何部分都可以是nil。
 * 从 _objc_pthread_destroyspecific() 函数调用.
 */
void _destroyInitializingClassList(struct _objc_initializing_classes *list)
{
    if (list != nil) {
        if (list->metaclasses != nil) {
            free(list->metaclasses);
        }
        free(list);
    }
}


/* 判断当前线程是否正在初始化指定的类
 */
bool _thisThreadIsInitializingClass(Class cls)
{
    int i;

    _objc_initializing_classes *list = _fetchInitializingClassList(NO);
    if (list) {
        cls = cls->getMeta();
        for (i = 0; i < list->classesAllocated; i++) {
            if (cls == list->metaclasses[i]) return YES;
        }
    }

    // 列表中没有或没有找到列表
    return NO;
}


/* 记录该线程当前正在初始化指定的类。
 * 这个线程将被允许向类发送消息，但是其他线程必须等待。
 */
static void _setThisThreadIsInitializingClass(Class cls)
{
    int i;
    _objc_initializing_classes *list = _fetchInitializingClassList(YES);
    cls = cls->getMeta();
  
    // paranoia: explicitly disallow duplicates
    for (i = 0; i < list->classesAllocated; i++) {
        if (cls == list->metaclasses[i]) {
            _objc_fatal("thread is already initializing this class!");
            return; // 已经初始化
        }
    }
  
    for (i = 0; i < list->classesAllocated; i++) {
        if (! list->metaclasses[i]) {
            list->metaclasses[i] = cls;
            return;
        }
    }

    // 类列表已满 - 重新分配
    list->classesAllocated = list->classesAllocated * 2 + 1;
    list->metaclasses = (Class *) 
        realloc(list->metaclasses,
                          list->classesAllocated * sizeof(Class));
    // 把新元素置为 nil
    list->metaclasses[i++] = cls;
    for ( ; i < list->classesAllocated; i++) {
        list->metaclasses[i] = nil;
    }
}


/* 记录这个线程不再初始化指定的类。
 */
static void _setThisThreadIsNotInitializingClass(Class cls)
{
    int i;

    _objc_initializing_classes *list = _fetchInitializingClassList(NO);
    if (list) {
        cls = cls->getMeta();
        for (i = 0; i < list->classesAllocated; i++) {
            if (cls == list->metaclasses[i]) {
                list->metaclasses[i] = nil;
                return;
            }
        }
    }

    //列表中没有或没有找到列表
    _objc_fatal("thread is not initializing this class!");  
}


typedef struct PendingInitialize {
    Class subclass;
    struct PendingInitialize *next;
} PendingInitialize;

static NXMapTable *pendingInitializeMap;

/*cls 已经完成了它的 +initialize 方法，它的超类也完成了。
 * 将 cls 标记为 initialized，然后标记任何已经完成了自己的 +initialize 方法的 cls 子类。
 */
static void _finishInitializing(Class cls, Class supercls)
{
    PendingInitialize *pending;

    classInitLock.assertLocked();
    assert(!supercls  ||  supercls->isInitialized());

    if (PrintInitializing) {
        _objc_inform("INITIALIZE: thread %p: %s is fully +initialized",
                     pthread_self(), cls->nameForLogging());
    }

    // 将这个类标记为完全+initialized
    cls->setInitialized();
    classInitLock.notifyAll();
    _setThisThreadIsNotInitializingClass(cls);
    
    // 标记任何仅仅等待这个类的子类
    if (!pendingInitializeMap) return;
    pending = (PendingInitialize *)NXMapGet(pendingInitializeMap, cls);
    if (!pending) return;

    NXMapRemove(pendingInitializeMap, cls);
    
    // 如果挂起表现在为空，则销毁它，以节省内存。
    if (NXCountMapTable(pendingInitializeMap) == 0) {
        NXFreeMapTable(pendingInitializeMap);
        pendingInitializeMap = nil;
    }

    while (pending) {
        PendingInitialize *next = pending->next;
        if (pending->subclass) _finishInitializing(pending->subclass, cls);
        free(pending);
        pending = next;
    }
}


/* cls已经完成了它的 +initialize 方法，但是它的超类还没有。
 * 在将 cls 标记为 initialized 之前，等待supercls完成。
 */
static void _finishInitializingAfter(Class cls, Class supercls)
{
    PendingInitialize *pending;

    classInitLock.assertLocked();

    if (PrintInitializing) {
        _objc_inform("INITIALIZE: thread %p: class %s will be marked as fully "
                     "+initialized after superclass +[%s initialize] completes",
                     pthread_self(), cls->nameForLogging(),
                     supercls->nameForLogging());
    }

    if (!pendingInitializeMap) {
        pendingInitializeMap = 
            NXCreateMapTable(NXPtrValueMapPrototype, 10);
        // 为 CF/NSObject +initialize 预先调整此表的大小
    }

    pending = (PendingInitialize *)malloc(sizeof(*pending));
    pending->subclass = cls;
    pending->next = (PendingInitialize *)
        NXMapGet(pendingInitializeMap, supercls);
    NXMapInsert(pendingInitializeMap, supercls, pending);
}

// 在堆栈跟踪中提供有用的消息。
OBJC_EXTERN __attribute__((noinline, used, visibility("hidden")))
void waitForInitializeToComplete(Class cls)
    asm("_WAITING_FOR_ANOTHER_THREAD_TO_FINISH_CALLING_+initialize");
OBJC_EXTERN __attribute__((noinline, used, visibility("hidden")))
void callInitialize(Class cls)
    asm("_CALLING_SOME_+initialize_METHOD");


void waitForInitializeToComplete(Class cls)
{
    if (PrintInitializing) {
        _objc_inform("INITIALIZE: thread %p: blocking until +[%s initialize] "
                     "completes", pthread_self(), cls->nameForLogging());
    }

    monitor_locker_t lock(classInitLock);
    while (!cls->isInitialized()) {
        classInitLock.wait();
    }
    asm("");
}


void callInitialize(Class cls)
{
    ((void(*)(Class, SEL))objc_msgSend)(cls, SEL_initialize);
    asm("");
}


/* 类的初始化很简单 ?
 *
 * 如果类没有 +initialize 实现，或者类的 +initialize 实现看起来为空，则返回true。
 * 任何根类  +initialize 实现都被认为是简单的。
 */
static bool classHasTrivialInitialize(Class cls)
{
    if (cls->isRootClass() || cls->isRootMetaclass()) return true;

    Class rootCls = cls->ISA()->ISA()->superclass;
    
    IMP rootImp = lookUpImpOrNil(rootCls->ISA(), SEL_initialize, rootCls, 
                             NO/*initialize*/, YES/*cache*/, NO/*resolver*/);
    IMP imp = lookUpImpOrNil(cls->ISA(), SEL_initialize, cls,
                             NO/*initialize*/, YES/*cache*/, NO/*resolver*/);
    return (imp == nil  ||  imp == (IMP)&objc_noop_imp  ||  imp == rootImp);
}


/*
 * 将一个类标记为已完成初始化，并通知等待者或稍后排队。
 * 如果超类也完成了初始化，那么更新信息位并通知等待的线程。
 * 如果没有，稍后更新它们。(如果这个 +initialize 本身是在超类 +initialize 中触发的，就会发生这种情况。)
 */
static void lockAndFinishInitializing(Class cls, Class supercls)
{
    monitor_locker_t lock(classInitLock);
    if (!supercls  ||  supercls->isInitialized()) {
        _finishInitializing(cls, supercls);
    } else {
        _finishInitializingAfter(cls, supercls);
    }
}


/*
 * fork() 之后 +initialize 是有问题的。fork 子进程可以调用一些 +initialize，这会在父进程中等待另一个 +initialize 导致死锁。
 * 我们不知道它在其中取得了多少进展，所以我们不能像 +initialize 完成那样操作，也不能从头开始 +initialize。
 *
 * 相反，我们会进行内省。 如果有一些 +initialize实现的类，我们就会停止。如果该类没有自己的+initialize实现，我们继续。如果根类 + initialize存在，则假定它是空的。
 *
 * 即使子类的 +initialize 没有被任何东西阻塞，我们也会应用这个规则。这可以防止 +initialize 死锁很少触发的竞争。相反，即使我们“赢了”数据竞争，我们也不允许这样做。
 *
 * 异常:当fork()被调用时，单线程进程对子进程中的+initialize没有任何限制。示例:sshd和httpd。
* 希望实现+initialize 并在 fork() 之后可调用的类必须使用 atfork() 处理程序在fork prepare中触发+initialize。
 */

// 当 fork() 之后不能调用某些+initialize方法时，在停止之前调用。
BREAKPOINT_FUNCTION(
    void objc_initializeAfterForkError(Class cls)
);

void performForkChildInitialize(Class cls, Class supercls)
{
    if (classHasTrivialInitialize(cls)) {
        if (PrintInitializing) {
            _objc_inform("INITIALIZE: thread %p: skipping trivial +[%s "
                         "initialize] in fork() child process",
                         pthread_self(), cls->nameForLogging());
        }
        lockAndFinishInitializing(cls, supercls);
    }
    else {
        if (PrintInitializing) {
            _objc_inform("INITIALIZE: thread %p: refusing to call +[%s "
                         "initialize] in fork() child process because "
                         "it may have been in progress when fork() was called",
                         pthread_self(), cls->nameForLogging());
        }
        _objc_inform_now_and_on_crash
            ("+[%s initialize] may have been in progress in another thread "
             "when fork() was called.",
             cls->nameForLogging());
        objc_initializeAfterForkError(cls);
        _objc_fatal
            ("+[%s initialize] may have been in progress in another thread "
             "when fork() was called. We cannot safely call it or "
             "ignore it in the fork() child process. Crashing instead. "
             "Set a breakpoint on objc_initializeAfterForkError to debug.",
             cls->nameForLogging());
    }
}


/* 按需向任何未初始化的类发送“+initialize”消息。首先强制超类的初始化。
 */
void _class_initialize(Class cls)
{
    assert(!cls->isMetaClass());

    Class supercls;
    bool reallyInitialize = NO;

    // 确保在开始初始化cls之前已经完成了super的初始化。
    //参见上面关于死锁的说明。
    supercls = cls->superclass;
    if (supercls  &&  !supercls->isInitialized()) {
        _class_initialize(supercls);
    }
    
    // 尝试以原子方式设置 CLS_INITIALIZING
    {
        monitor_locker_t lock(classInitLock);
        if (!cls->isInitialized() && !cls->isInitializing()) {
            cls->setInitializing();
            reallyInitialize = YES;
        }
    }
    
    if (reallyInitialize) {
        // 成功地设置了 CLS_INITIALIZING 位。初始化类。
        
        // 记录我们正在初始化这个类，这样我们就可以给它发送消息。
        _setThisThreadIsInitializingClass(cls);

        if (MultithreadedForkChild) {
            // LOL JK 我们不会在fork()之后调用+initialize方法。
            performForkChildInitialize(cls, supercls);
            return;
        }
        
        // 发送 +initialize 消息。
        // 注意，如果这个类没有实现 +initialize，则 +initialize(再次)被发送到超类。2157218
        if (PrintInitializing) {
            _objc_inform("INITIALIZE: thread %p: calling +[%s initialize]",
                         pthread_self(), cls->nameForLogging());
        }

        // 异常:抛出异常的 +initialize 调用被视为完整且成功的+initialize。
        // 只有 __OBJC2__ 添加这些处理程序。__OBJC2__与CF的调用相比有一个启动问题
        // objc_exception_set_functions().
#if __OBJC2__
        @try
#endif
        {
            callInitialize(cls);

            if (PrintInitializing) {
                _objc_inform("INITIALIZE: thread %p: finished +[%s initialize]",
                             pthread_self(), cls->nameForLogging());
            }
        }
#if __OBJC2__
        @catch (...) {
            if (PrintInitializing) {
                _objc_inform("INITIALIZE: thread %p: +[%s initialize] "
                             "threw an exception",
                             pthread_self(), cls->nameForLogging());
            }
            @throw;
        }
        @finally
#endif
        {
            // 初始化完成。
            lockAndFinishInitializing(cls, supercls);
        }
        return;
    }
    
    else if (cls->isInitializing()) {
        // 我们无法设置 INITIALIZING，因为 INITIALIZING 已经设置好了。
        // 如果该线程在前面设置，则正常继续。
        // 如果其他线程设置了它，则阻塞，直到完成初始化。
        // 如果在这里 INITIALIZING 更改为 INITIALIZED，这是可以的，因为在阻塞之前，我们会在锁中安全地检查 INITIALIZED。
        if (_thisThreadIsInitializingClass(cls)) {
            return;
        } else if (!MultithreadedForkChild) {
            waitForInitializeToComplete(cls);
            return;
        } else {
            // 我们在fork()的子端，面对一个在调用fork()时由其他线程初始化的类。
            _setThisThreadIsInitializingClass(cls);
            performForkChildInitialize(cls, supercls);
        }
    }
    
    else if (cls->isInitialized()) {
        // 设置 CLS_INITIALIZING 失败，因为已经有人初始化了这个类。继续正常。
        // 注意，此检查必须在 ISINITIALIZING 用例之后进行。
        // 否则:另一个线程正在初始化这个类。ISINITIALIZED是错误的。跳过这一条件。然后另一个线程完成初始化并设置 INITIALIZING=NO 和INITIALIZED=YES 。跳过ISINITIALIZING 子句。Die horribly.
        return;
    }
    
    else {
        //我们不应该在这里。
        _objc_fatal("thread-safe class init in objc runtime is buggy!");
    }
}
