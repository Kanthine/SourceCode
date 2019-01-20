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
 * 每个线程都有一个正在初始化类的列表。
 * 全局classInitLock用于同步对CLS_INITIALIZED和CLS_INITIALIZING的更改 : 到CLS_INITIALIZING的转换必须是相对于自身的原子测试和设置，以及到CLS_INITIALIZED的转换。
 *
 * 全局 classInitWaitCond 用于阻塞等待初始化完成的线程。classInitLock同步条件检查和条件变量。
 */

/* +initialize 死锁情况，当一个类被标记为 CLS_INITIALIZING ，而它的超类为 CLS_INITIALIZED。通过在开始初始化类之前完全初始化超类来解决。
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
 *    super init OWController - 等待 Thread 2 完成 OWController init
 *
 *  Thread 2 (normal OmniWeb thread):
 *    initialize OWController
 *    super init OFObject - 等待 Thread 1 完成 OFObject init
 *
 *  deadlock!
 *
 * 解决方案：在开始初始化子类之前完全初始化父类。然后类层次结构的初始化 +initialized 部分将是一个从根开始的连续子树，因此其他线程不能跳到两个初始化类之间的中间，也不会在超类等待它的子类等待超类时卡住。
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
    int classesAllocated;//在该线程允许同时类分配的最大数量
    Class *metaclasses;// 元类数组：分配的内存大小为 (classesAllocated * sizeof(Class)) 字节
} _objc_initializing_classes;


/* 获取该线程中正在初始化的类列表。
 * @param create 当前线程没有初始化任何类时，是否需要创建一个列表；
 *               入参为 YES 时，创建一个列表；否则返回 nil
 */
static _objc_initializing_classes *_fetchInitializingClassList(bool create){
    _objc_pthread_data *data;//线程存储的数据
    _objc_initializing_classes *list;
    Class *classes;
    
    data = _objc_fetch_pthread_data(create);//获取线程存储数据
    if (data == nil) return nil;
    
    list = data->initializingClasses;
    if (list == nil) {
        if (!create) {
            return nil;
        } else {
            list = (_objc_initializing_classes *)calloc(1, sizeof(_objc_initializing_classes));
            data->initializingClasses = list;
        }
    }
    
    classes = list->metaclasses;
    if (classes == nil) {//如果元类数组不存在，分配元类数组
        list->classesAllocated = 4;// 在 realloc() 之前，在此线程上允许4个类同时inits。
        
        /* void* calloc(size_t count, size_t size) 函数
         * 在内存的动态存储区中分配 count 个长度为 size 的连续空间，
         * 函数返回一个指向分配起始地址的指针；
         * 如果分配不成功，返回NULL。
         * calloc() 函数在动态分配完内存后，自动初始化该内存空间为零；而malloc()不初始化，里边数据是随机的垃圾数据。
         */
        classes = (Class *)calloc(list->classesAllocated, sizeof(Class));
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
bool _thisThreadIsInitializingClass(Class cls){
    int i;
    _objc_initializing_classes *list = _fetchInitializingClassList(NO);//获取该线程中正在初始化的类列表
    
    //遍历正在初始化的类列表，匹配指定的类
    if (list) {
        cls = cls->getMeta();
        for (i = 0; i < list->classesAllocated; i++) {
            if (cls == list->metaclasses[i]) return YES;
        }
    }
    // 列表中没有或没有找到列表
    return NO;
}


/* 将指定的类存储到 正在初始化的类列表
 * @param cls 指定的类
 * @note 如果该类已经在该类表，则终止程序
 * @note 如果列表已满，需要扩展列表并初始化新内存空间
 * @note 这个线程将被允许向类发送消息，但是其他线程必须等待。
 */
static void _setThisThreadIsInitializingClass(Class cls){
    int i;
    _objc_initializing_classes *list = _fetchInitializingClassList(YES);//获取该线程中正在初始化的类列表
    cls = cls->getMeta();
    
    //遍历正在初始化的类列表，如果找到该类，则证明该类正在初始化，为了防止重复初始化需要终止程序
    for (i = 0; i < list->classesAllocated; i++) {
        if (cls == list->metaclasses[i]) {
            _objc_fatal("thread is already initializing this class!");
            return; // 已经初始化
        }
    }
    
    //遍历正在初始化的类列表，如果该类表有空余内存，则将 cls 分配到该内存
    for (i = 0; i < list->classesAllocated; i++) {
        if (! list->metaclasses[i]) {
            list->metaclasses[i] = cls;
            return;
        }
    }
    
    // 正在初始化的类列表已满（内存大小被限制） ： 需要保存原数据并扩展内存
    list->classesAllocated = list->classesAllocated * 2 + 1;
    list->metaclasses = (Class *)realloc(list->metaclasses, list->classesAllocated * sizeof(Class));
    list->metaclasses[i++] = cls;
    
    // 注意：由于 realloc() 函数新分配的内存空间不会被初始化，此时需要遍历新分配的没有用到的内存空间，把新元素置为 nil
    for ( ; i < list->classesAllocated; i++) {
        list->metaclasses[i] = nil;
    }
}


/* 将指定的类 从 正在初始化的类列表 移除
 * @note 如果该类不在列表，则终止程序
 */
static void _setThisThreadIsNotInitializingClass(Class cls){
    int i;
    _objc_initializing_classes *list = _fetchInitializingClassList(NO);//获取该线程中正在初始化的类列表
    
    //遍历正在初始化的类列表，匹配到指定的类然后将其置为 nil
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
    Class subclass;//挂起的子类
    struct PendingInitialize *next;//指向下一个挂起的子类
} PendingInitialize;//指定类class 挂起子类的链表

//哈希表：存储 class-> PendingInitialize 映射关系
static NXMapTable *pendingInitializeMap;

/* 标记一个类的状态为完成初始化： class_rw_t -> flags = RW_INITIALIZED
 * @param supercls 要标记类的父类；父类必须已被标记完成，否则断言失败程序终止；
 * 标记完成后，通知所有等待的队列；
 * 遍历挂起的子类，将这些子类全部标记为已完成
 */
static void _finishInitializing(Class cls, Class supercls){
    PendingInitialize *pending;//挂起的子类的链表
    
    classInitLock.assertLocked();
    assert(!supercls  ||  supercls->isInitialized());
    
    if (PrintInitializing) {
        _objc_inform("INITIALIZE: thread %p: %s is fully +initialized",pthread_self(), cls->nameForLogging());
    }
    
    // 将这个类标记为完全+initialized
    cls->setInitialized();
    classInitLock.notifyAll();//根据加入等待队列中的先后顺序依次唤醒他们
    _setThisThreadIsNotInitializingClass(cls);// 将指定的类 从 正在初始化的类列表 移除
    
    // 标记任何仅仅等待这个类的子类
    if (!pendingInitializeMap) return;
    pending = (PendingInitialize *)NXMapGet(pendingInitializeMap, cls);
    if (!pending) return;//没有挂起
    
    NXMapRemove(pendingInitializeMap, cls);//从哈希表移除正在挂起的类
    
    // 如果哈希表 pendingInitializeMap 中没有数据，则销毁它，以节省内存
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


/* cls 已经完成了它的 +initialize 方法，但是它的超类还没有；
 * 此时不能将 cls 标记为 RW_INITIALIZED ，必须等待 supercls 完成。
 * 那么父类完成后，如何知道有些子类在苦苦等待呢？通过哈希表 pendingInitializeMap
 * 哈希表 pendingInitializeMap 映射 class-> PendingInitialize 关系
 * class 是要等待完成的父类，PendingInitialize 是一个链表：存储着一个个等等 supercls 完成的子类
 */
static void _finishInitializingAfter(Class cls, Class supercls)
{
    PendingInitialize *pending;//指定类 class 挂起子类的链表
    
    classInitLock.assertLocked();
    
    if (PrintInitializing) {
        _objc_inform("INITIALIZE: thread %p: class %s will be marked as fully +initialized after superclass +[%s initialize] completes",
                     pthread_self(), cls->nameForLogging(),
                     supercls->nameForLogging());
    }
    
    if (!pendingInitializeMap) {
        //如果哈希表为空，先创建一个哈希表
        pendingInitializeMap = NXCreateMapTable(NXPtrValueMapPrototype, 10);
    }
    
    //先插入的节点位于最前面：哈希表的映射关系存储当前节点，将 next 指向上一个插入的节点
    pending = (PendingInitialize *)malloc(sizeof(*pending));
    pending->subclass = cls;//设置挂起的子类
    pending->next = (PendingInitialize *)NXMapGet(pendingInitializeMap, supercls);
    NXMapInsert(pendingInitializeMap, supercls, pending);
}

// 在堆栈跟踪中提供有用的消息。
OBJC_EXTERN __attribute__((noinline, used, visibility("hidden")))
void waitForInitializeToComplete(Class cls)
asm("_WAITING_FOR_ANOTHER_THREAD_TO_FINISH_CALLING_+initialize");
OBJC_EXTERN __attribute__((noinline, used, visibility("hidden")))
void callInitialize(Class cls)
asm("_CALLING_SOME_+initialize_METHOD");

//没有完成初始化，则执行等待
void waitForInitializeToComplete(Class cls){
    if (PrintInitializing) {
        _objc_inform("INITIALIZE: thread %p: blocking until +[%s initialize] "
                     "completes", pthread_self(), cls->nameForLogging());
    }
    
    monitor_locker_t lock(classInitLock);
    while (!cls->isInitialized()) {//没有完成初始化
        classInitLock.wait();//执行等待
    }
    asm("");
}


void callInitialize(Class cls){
    ((void(*)(Class, SEL))objc_msgSend)(cls, SEL_initialize);
    asm("");
}

#pragma mark - 疑惑？
/* 判断是否重写了 +initialize 方法 （ 该说法正确嘛？）
 * @return 如果没有重写，则返回 YES；否则返回 NO
 * @note 任何根类或者根元类，Runtime 认为它没有重写 +initialize 方法
 */
static bool classHasTrivialInitialize(Class cls){
    //如果是根类或者根元类，则肯定没有重写 +initialize 方法
    if (cls->isRootClass() || cls->isRootMetaclass()) return true;
    
    Class rootCls = cls->ISA()->ISA()->superclass;//拿到根类
    
    //获取根类 +initialize 方法的 IMP
    IMP rootImp = lookUpImpOrNil(rootCls->ISA(), SEL_initialize, rootCls, NO, YES, NO);
    
    //如果该类或者它的父类重写了 +initialize，则 imp 一定不为 nil
    IMP imp = lookUpImpOrNil(cls->ISA(), SEL_initialize, cls ,NO, YES, NO);
    
    return (imp == nil  ||  imp == (IMP)&objc_noop_imp  ||  imp == rootImp);
}


/*
 * 将一个类标记为已完成初始化，并通知等待者或稍后排队。
 * 如果超类也完成了初始化，那么更新信息位并通知等待的线程。
 * 如果没有，稍后更新它们。(如果这个 +initialize 本身是在超类 +initialize 中触发的，就会发生这种情况。)
 */
static void lockAndFinishInitializing(Class cls, Class supercls){
    monitor_locker_t lock(classInitLock);
    if (!supercls  ||  supercls->isInitialized()) {//如果父类为空，或者父类完成初始化
        _finishInitializing(cls, supercls);
    } else {
        _finishInitializingAfter(cls, supercls);//挂起该类，等待父类完成
    }
}


/* fork() 函数 : 创建一个新的进程
 * fork() 函数之后 +initialize 是有问题的：fork() 函数创建的子进程可以调用一些 +initialize，这会在父进程中等待另一个 +initialize 导致死锁。
 * 我们不知道它在其中取得了多少进展，所以我们不能像 +initialize 完成那样操作，也不能从头开始 +initialize。
 *
 * 相反，我们会进行内省。 如果有一些 +initialize实现的类，我们就会停止。如果该类没有自己的+initialize实现，我们继续。如果根类 + initialize存在，则假定它是空的。
 *
 * 即使子类的 +initialize 没有被任何东西阻塞，我们也会应用这个规则。这可以防止 +initialize 死锁很少触发的竞争。相反，即使我们“赢了”数据竞争，我们也不允许这样做。
 *
 * 异常:当fork()被调用时，单线程进程对子进程中的+initialize没有任何限制。示例:sshd和httpd。
 * 希望实现 +initialize 并在 fork() 之后可调用的类必须使用 atfork() 处理程序在fork prepare中触发+initialize。
 */

//调用fork()函数子进程之后不能调用某些+initialize方法时，在停止之前调用。
BREAKPOINT_FUNCTION(
                    void objc_initializeAfterForkError(Class cls)
                    );

/* 执行 fork() 子进程初始化
 *
 */
void performForkChildInitialize(Class cls, Class supercls){
    if (classHasTrivialInitialize(cls)) {//没有重写 +initialize 方法
        if (PrintInitializing) {
            _objc_inform("INITIALIZE: thread %p: skipping trivial +[%s initialize] in fork() child process",
                         pthread_self(), cls->nameForLogging());
        }
        lockAndFinishInitializing(cls, supercls);
    }
    else {//如果重写 +initialize 方法
        if (PrintInitializing) {
            _objc_inform("INITIALIZE: thread %p: refusing to call +[%s initialize] in fork() child process because it may have been in progress when fork() was called",pthread_self(), cls->nameForLogging());
        }
        _objc_inform_now_and_on_crash
        ("+[%s initialize] may have been in progress in another thread when fork() was called.",
         cls->nameForLogging());
        objc_initializeAfterForkError(cls);
        _objc_fatal
        ("+[%s initialize] may have been in progress in another thread when fork() was called. We cannot safely call it or ignore it in the fork() child process. Crashing instead.Set a breakpoint on objc_initializeAfterForkError to debug.",
         cls->nameForLogging());
    }
}


/* 向指定的未初始化的类发送“+initialize”消息。首先强制超类的初始化。
 * @param cls 需要调用 +initialize 方法的类；该类不能是 元类
 * @note 如果其父类没有调用 +initialize，则父类首先调用 +initialize
 */
void _class_initialize(Class cls){
    assert(!cls->isMetaClass());//不能是元类
    
    Class supercls;
    bool reallyInitialize = NO;
    
    // 确保在开始初始化cls之前已经完成了其父类的初始化。
    //参见上面关于死锁的说明。
    supercls = cls->superclass;
    if (supercls  &&  !supercls->isInitialized()) {
        _class_initialize(supercls);
    }
    
    // 尝试以原子方式设置 CLS_INITIALIZING
    {
        monitor_locker_t lock(classInitLock);//设置原子锁用于同步
        if (!cls->isInitialized() && !cls->isInitializing()) {//该类没有初始化，而且不是正在初始化
            cls->setInitializing();//class_rw_t -> flags = RW_INITIALIZING
            reallyInitialize = YES;
        }
    }
    
    if (reallyInitialize) {//进入 RW_INITIALIZING 状态
        
        // 记录我们正在初始化这个类，这样我们就可以给它发送消息。
        _setThisThreadIsInitializingClass(cls);// 将指定的类存储到 正在初始化的类列表
        
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
    else if (cls->isInitializing()) {// 正在初始化
        
        /* 此时无法设置 INITIALIZING，因为 INITIALIZING 已经设置好了。
         * 如果该线程在前面设置，则正常继续
         * 如果其他线程设置了它，则阻塞，直到完成初始化
         * 如果在这里 INITIALIZING 更改为 INITIALIZED，这是可以的，因为在阻塞之前，我们会在锁中安全地检查 INITIALIZED。
         */
        if (_thisThreadIsInitializingClass(cls)) {// 判断当前线程是否正在初始化指定的类
            return;
        } else if (!MultithreadedForkChild) {
            //MultithreadedForkChild 为 NO ，允许在 fork() 创建子进程安全检查 +initialize
            waitForInitializeToComplete(cls);
            return;
        } else {
            // 我们在fork()的子端，面对一个在调用fork()时由其他线程初始化的类。
            _setThisThreadIsInitializingClass(cls);// 将指定的类存储到 正在初始化的类列表
            performForkChildInitialize(cls, supercls);
        }
    }
    else if (cls->isInitialized()) {//完成初始化
        /* 设置 CLS_INITIALIZING 失败，因为已经完成初始化；继续正常。
         * 注意，此检查必须在 ISINITIALIZING 用例之后进行。
         * 否则: 另一个线程正在初始化这个类。ISINITIALIZED是错误的。跳过这一条件。然后另一个线程完成初始化并设置 INITIALIZING=NO 和INITIALIZED=YES 。跳过ISINITIALIZING 子句。Die horribly.
         */
        return;
    }
    else {
        //一般而言，程序不能执行到此，除非程序异常，终止程序
        _objc_fatal("thread-safe class init in objc runtime is buggy!");
    }
}

