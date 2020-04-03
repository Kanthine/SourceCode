#include "objc-private.h"
#include "NSObject.h"

#include "objc-weak.h"
#include "llvm-DenseMap.h"
#include "NSObject.h"

#include <malloc/malloc.h>
#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <libkern/OSAtomic.h>
#include <Block.h>
#include <map>
#include <execinfo.h>

@interface NSInvocation
- (SEL)selector;
@end


/***********************************************************************
 * Weak ivar support
 **********************************************************************/

static id defaultBadAllocHandler(Class cls){
    _objc_fatal("attempt to allocate object of class '%s' failed",cls->nameForLogging());
}

static id(*badAllocHandler)(Class) = &defaultBadAllocHandler;

static id callBadAllocHandler(Class cls){
    // 添加了可重入保护，以防在处理程序中分配失败
    return (*badAllocHandler)(cls);
}

void _objc_setBadAllocHandler(id(*newHandler)(Class)){
    badAllocHandler = newHandler;
}


// 匿名的命名空间
namespace{
    

/** 表示是否有弱引用指向该对象! 如果该位值为1，在对象释放的时候需要把所有指向它的弱引用指针都指向nil，避免野指针
 */
#define SIDE_TABLE_WEAKLY_REFERENCED (1UL<<0)
/** 表示对象是否正在被释放! 1 正在释放，0 没有
*/
#define SIDE_TABLE_DEALLOCATING      (1UL<<1)  // MSB-ward of 弱引用位
/** SIDE_TABLE_RC_ 部分才是对象真正的引用计数存储区。
 *  引用计数加一或者减一，实际上是对整个unsigned long加四或者减四,因为真正的计数是从2^2位开始的。
 */
#define SIDE_TABLE_RC_ONE            (1UL<<2)  // MSB-ward of 回收位
/** WORD_BITS 在32位和64位系统的时候分别等于32和64。
 *  随着对象的引用计数不断变大，如果这一位都变成 1 了，就表示引用计数已经最大了不能再增加了。
 */
#define SIDE_TABLE_RC_PINNED         (1UL<<(WORD_BITS-1)) //最高位
    
#define SIDE_TABLE_RC_SHIFT 2
#define SIDE_TABLE_FLAG_MASK (SIDE_TABLE_RC_ONE-1)
    
    //模板类 DenseMap
    //RefcountMap隐藏了它的指针，因为我们不希望 table 充当“leaks”的根。
    typedef objc::DenseMap<DisguisedPtr<objc_object>,size_t,true> RefcountMap;
    
    //模板参数
    enum HaveOld { DontHaveOld = false, DoHaveOld = true };
    enum HaveNew { DontHaveNew = false, DoHaveNew = true };
    

    /* 散列表 SideTable ：主要用于辅助管理对象的 引用计数 和 弱引用依赖
     * 在 runtime 内存空间中，SideTables 是一个 hash 数组，里面存储了 SideTable。
     * SideTables 的 hash 键值就是一个对象 obj 的地址。
     * 因此可以说，一个 obj，对应了一个 SideTable；但是一个 SideTable，会对应多个 obj。因为 SideTable 的数量有限，所以会有很多 obj 共用同一个 SideTable。
     *
     * @疑问？为什么不直接用一张SideTable，而是用 SideTables 去管理多个 SideTable？
     * SideTable里有一个自旋锁，如果把所有的类都放在同一个SideTable，有任何一个类有改动都会对整个table做操作，并且在操作一个类的同时，操作别的类会被锁住等待，这样会导致操作效率和查询效率都很低。而有多个SideTable的话，操作的都是单个Table，并不会影响其他的table，这就是分离锁。
     * 继续SideTables,来看一下散列表的数据结构（数组+链表），举个例子，我们需要把小于100的放到第1个Table，大于900的放到第6个Table：
     *
     */
    struct SideTable {
        spinlock_t slock;// 保证操作线程安全的自旋锁;
        RefcountMap refcnts;//引用计数的Map表 key-value：当isa中extra_rc不足以保存时,使用散列表保存refcnts.find(obj)
        weak_table_t weak_table; //弱引用表，使用数组存储弱引用指针
        SideTable() {//默认构造函数
            memset(&weak_table, 0, sizeof(weak_table));
        }
        ~SideTable() {//析构函数
            _objc_fatal("Do not delete SideTable.");
        }
        void lock() { slock.lock(); }
        void unlock() { slock.unlock(); }
        void forceReset() { slock.forceReset(); }
        // Address-ordered lock discipline for a pair of side tables.
        template<HaveOld, HaveNew> static void lockTwo(SideTable *lock1, SideTable *lock2);
        template<HaveOld, HaveNew> static void unlockTwo(SideTable *lock1, SideTable *lock2);
    };
    
    
    template<> void SideTable::lockTwo<DoHaveOld, DoHaveNew>(SideTable *lock1, SideTable *lock2){
        spinlock_t::lockTwo(&lock1->slock, &lock2->slock);
    }
    
    template<> void SideTable::lockTwo<DoHaveOld, DontHaveNew>(SideTable *lock1, SideTable *){
        lock1->lock();
    }
    
    template<> void SideTable::lockTwo<DontHaveOld, DoHaveNew>(SideTable *, SideTable *lock2){
        lock2->lock();
    }
    
    template<> void SideTable::unlockTwo<DoHaveOld, DoHaveNew>(SideTable *lock1, SideTable *lock2){
        spinlock_t::unlockTwo(&lock1->slock, &lock2->slock);
    }
    
    template<> void SideTable::unlockTwo<DoHaveOld, DontHaveNew>(SideTable *lock1, SideTable *){
        lock1->unlock();
    }
    
    template<> void SideTable::unlockTwo<DontHaveOld, DoHaveNew>(SideTable *, SideTable *lock2){
        lock2->unlock();
    }
    
    // 我们不能使用c++静态初始化器来初始化SideTables，因为libc在c++初始化器运行之前调用我们。由于额外的间接性，我们也不希望有一个指向此结构的全局指针。
    alignas(StripedMap<SideTable>) static uint8_t SideTableBuf[sizeof(StripedMap<SideTable>)];
    
    static void SideTableInit() {
        new (SideTableBuf) StripedMap<SideTable>();
    }
    
    static StripedMap<SideTable>& SideTables() {
        return *reinterpret_cast<StripedMap<SideTable>*>(SideTableBuf);
    }
};

void SideTableLockAll() {
    SideTables().lockAll();
}

void SideTableUnlockAll() {
    SideTables().unlockAll();
}

void SideTableForceResetAll() {
    SideTables().forceResetAll();
}

void SideTableDefineLockOrder() {
    SideTables().defineLockOrder();
}

void SideTableLocksPrecedeLock(const void *newlock) {
    SideTables().precedeLock(newlock);
}

void SideTableLocksSucceedLock(const void *oldlock) {
    SideTables().succeedLock(oldlock);
}

void SideTableLocksPrecedeLocks(StripedMap<spinlock_t>& newlocks) {
    int i = 0;
    const void *newlock;
    while ((newlock = newlocks.getLock(i++))) {
        SideTables().precedeLock(newlock);
    }
}

void SideTableLocksSucceedLocks(StripedMap<spinlock_t>& oldlocks) {
    int i = 0;
    const void *oldlock;
    while ((oldlock = oldlocks.getLock(i++))) {
        SideTables().succeedLock(oldlock);
    }
}

// -fobjc-arc 标志会导致编译器发出对 objc_{retain/release/autorelease/retain_block} 的调用
id objc_retainBlock(id x) {
    return (id)_Block_copy(x);
}

// The following SHOULD be called by the compiler directly, but the request hasn't been made yet :-)
BOOL objc_should_deallocate(id object) {
    return YES;
}

id objc_retain_autorelease(id obj){
    return objc_autorelease(objc_retain(obj));
}


void objc_storeStrong(id *location, id obj){
    id prev = *location;
    if (obj == prev) {
        return;
    }
    objc_retain(obj);
    *location = obj;
    objc_release(prev);
}


enum CrashIfDeallocating {
    DontCrashIfDeallocating = false, DoCrashIfDeallocating = true
};

/** 更新指针指向，创建对应的弱引用表
 * 该函数主要做了以下几件事：
 *   1、分别获取新、旧值的散列表指针
 *   2、如果有旧值就调用 weak_unregister_no_lock() 函数，从旧值的 weak_entry_t 数组中移出旧指针
 *   3、如果有新值就调用 weak_register_no_lock() 函数分配新值
 *
 * @template 使用 template 进行常量参数传递是为了优化性能,预判了大概率会发生的事情优先处理；
 *   初始化一个弱引用指针并赋值，该指针没有旧值 ：HaveOld=false,haveNew=true
 *   将弱引用指针指向 nil，该指针没有新值：HaveOld=true,haveNew=false
 *   将一个弱引用指针重新赋值，该指针之前指向旧值：HaveOld=true,haveNew=true
*    HaveOld 代表是否有旧的引用，如果为true，则代表有旧的引用需要释放
*    HaveNew 代表是否有新的引用，如果为true，则代表要存储新的引用
*   如果crashifdeallocate 为true，则当newObj正在释放或newObj的类不支持弱引用时，进程将停止。
*   如果crashifdeallocate 为false，则存储nil。
*/
template <HaveOld haveOld, HaveNew haveNew,CrashIfDeallocating crashIfDeallocating>
static id storeWeak(id *location, objc_object *newObj){
    assert(haveOld  ||  haveNew);//断言新值和旧值至少有一个是存在
    if (!haveNew) assert(newObj == nil);
    
    //在类没有完成 +initialized 方法之前调用 weakStore 时,作为初始化的标识
    Class previouslyInitializedClass = nil;
    id oldObj;
    SideTable *oldTable;
    SideTable *newTable;
        
retry:
    // 分别获取新旧值相关联的引用表
    if (haveOld) {
        oldObj = *location;//获取弱引用指针的旧指向
        oldTable = &SideTables()[oldObj];//获取oldObj对应的弱引用表
    } else {
        oldTable = nil;
    }
    if (haveNew) {
        newTable = &SideTables()[newObj];//获取newObj对应的弱引用表
    } else {
        newTable = nil;
    }
    SideTable::lockTwo<haveOld, haveNew>(oldTable, newTable);//上锁
    
    if (haveOld && *location != oldObj) {//如果旧值改变就重新获取旧值相关联的表
        SideTable::unlockTwo<haveOld, haveNew>(oldTable, newTable);
        goto retry;
    }
    
    // 如果有新值，判断新值所属的类是否已经初始化，如果没有初始化，则先执行初始化，防止+initialize内部调用 storeWeak() 产生死锁
    if (haveNew  &&  newObj) {
        Class cls = newObj->getIsa();
        if (cls != previouslyInitializedClass  && !((objc_class *)cls)->isInitialized()){
            SideTable::unlockTwo<haveOld, haveNew>(oldTable, newTable);
            _class_initialize(_class_getNonMetaClass(cls, (id)newObj));
            
            // 如果这个类在它自身的一个实例上调用storeWeak()进行 +initialize，那么我们可以继续，但是它将显示为正在初始化，并且还没有初始化到上面的检查中。
            previouslyInitializedClass = cls;
            goto retry;
        }
    }
    if (haveOld) {//如果旧值存在，则从旧值的 weak_entry_t 数组中移出旧指针
        weak_unregister_no_lock(&oldTable->weak_table, oldObj, location);
    }
    
    if (haveNew) {//绑定新值
        newObj = (objc_object *)weak_register_no_lock(&newTable->weak_table, (id)newObj, location,crashIfDeallocating);
        if (newObj  &&  !newObj->isTaggedPointer()) {
            newObj->setWeaklyReferenced_nolock();// 如果存储成功则设置SideTable中弱引用标志位
        }
        *location = (id)newObj;//不要在其他地方设置 *location。那会引起数据竞争。
    }else {
        // 没有新值。存储没有更改。
    }
    
    SideTable::unlockTwo<haveOld, haveNew>(oldTable, newTable);
    return (id)newObj;
}


/** 将已经被注册的弱引用指针再次指向别的变量
 * @param location 弱引用指针的内存地址
 * @param newObj 弱指针指向的新对象
 * @return 新变量
 */
id objc_storeWeak(id *location, id newObj){
    return storeWeak<DoHaveOld, DoHaveNew, DoCrashIfDeallocating>(location, (objc_object *)newObj);
}

/** 这个函数将一个新值存储到一个_weak变量中。
 *  @param location 弱引用指针的内存地址
 *  @param newObj 弱指针指向的新对象
 * 如果新对象正在释放或新对象的类不支持弱引用，则存储nil。
 */
id objc_storeWeakOrNil(id *location, id newObj){
    return storeWeak<DoHaveOld, DoHaveNew, DontCrashIfDeallocating>(location, (objc_object *)newObj);
}

/** 注册一个新的 weak 指针指向对象的地址
 * @param location 弱引用指针的内存地址
 * @param newObj 弱指针指向的新对象
 * @note 该函数不是线程安全的
 */
id objc_initWeak(id *location, id newObj){
    if (!newObj) {//判断原始引用对象是否为空
        *location = nil;
        return nil;
    }
    //调用 objc_storeWeak() 函数，更新指针指向，创建对应的弱引用表
    return storeWeak<DontHaveOld, DoHaveNew, DoCrashIfDeallocating>(location, (objc_object*)newObj);
}

id objc_initWeakOrNil(id *location, id newObj){
    if (!newObj) {
        *location = nil;
        return nil;
    }
    return storeWeak<DontHaveOld, DoHaveNew, DontCrashIfDeallocating>(location, (objc_object*)newObj);
}

/** 解除弱引用表中弱引用指针与被引用对象之间的关系
 * @param location 弱引用指针
 * 以下三种情况都会调用该函数
 *    @case_1 : __weak MyModel *weakModel;
 *    @case_2 : __weak MyModel *weakModel = nil;
 *    @case_3 : weakModel = nil;
 */
void objc_destroyWeak(id *location){
    (void)storeWeak<DoHaveOld, DontHaveNew, DontCrashIfDeallocating>(location, nil);
}

/*
 * 曾几何时，如果我们看到对象正在释放，我们会急切地清除 *location。
 这会混淆像NSPointerFunctions这样试图预先存储原始存储，并假设存储为零那么弱系统就会干扰的代码。
 这是错误的：弱系统仍然会检查并稍后清除存储
 。这可能会导致objc_weak_error投诉和崩溃。 因此，在释放完成之前，不去碰存储
 */
id objc_loadWeakRetained(id *location){
    id obj;
    id result;
    Class cls;
    
    SideTable *table;
    
retry:
    // fixme std::atomic this load
    obj = *location;
    if (!obj) return nil;
    if (obj->isTaggedPointer()) return obj;
    
    table = &SideTables()[obj];
    
    table->lock();
    if (*location != obj) {
        table->unlock();
        goto retry;
    }
    
    result = obj;
    
    cls = obj->ISA();
    if (! cls->hasCustomRR()) {
        // Fast case. We know +initialize is complete because
        // default-RR can never be set before then.
        assert(cls->isInitialized());
        if (! obj->rootTryRetain()) {
            result = nil;
        }
    }else {
        // 缓慢的情况。我们必须检查 +initialize 并在必要时在锁外部调用它，以避免死锁。
        if (cls->isInitialized() || _thisThreadIsInitializingClass(cls)) {
            BOOL (*tryRetain)(id, SEL) = (BOOL(*)(id, SEL))class_getMethodImplementation(cls, SEL_retainWeakReference);
            if ((IMP)tryRetain == _objc_msgForward) {
                result = nil;
            }else if (! (*tryRetain)(obj, SEL_retainWeakReference)) {
                result = nil;
            }
        }else {
            table->unlock();
            _class_initialize(cls);
            goto retry;
        }
    }
    table->unlock();
    return result;
}

/**
 * This loads the object referenced by a weak pointer and returns it, after
 * retaining and autoreleasing the object to ensure that it stays alive
 * long enough for the caller to use it. This function would be used
 * anywhere a __weak variable is used in an expression.
 *
 * @param location The weak pointer address
 *
 * @return The object pointed to by \e location, or \c nil if \e location is \c nil.
 */
id objc_loadWeak(id *location){
    if (!*location) return nil;
    return objc_autorelease(objc_loadWeakRetained(location));
}


/**
 * This function copies a weak pointer from one location to another,
 * when the destination doesn't already contain a weak pointer. It
 * would be used for code like:
 *
 *  __weak id src = ...;
 *  __weak id dst = src;
 *
 * This function IS NOT thread-safe with respect to concurrent
 * modifications to the destination variable. (Concurrent weak clear is safe.)
 *
 * @param dst The destination variable.
 * @param src The source variable.
 */
void objc_copyWeak(id *dst, id *src){
    id obj = objc_loadWeakRetained(src);
    objc_initWeak(dst, obj);
    objc_release(obj);
}

/**
 * Move a weak pointer from one location to another.
 * Before the move, the destination must be uninitialized.
 * After the move, the source is nil.
 *
 * This function IS NOT thread-safe with respect to concurrent
 * modifications to either weak variable. (Concurrent weak clear is safe.)
 *
 */
void objc_moveWeak(id *dst, id *src){
    objc_copyWeak(dst, src);
    objc_destroyWeak(src);
    *src = nil;
}


/** 自动释放的实现
 * 一个线程的自动释放池是一个指向 栈 的指针
 * 每个指针或者是要释放的对象，或者是POOL_BOUNDARY，后者是一个 autorelease pool boundary.
 * A pool token 是指向该池 POOL_BOUNDARY 的指针
 * 当 pool 从栈区弹出时，pool中的对象会 -released
 * The stack is divided into a doubly-linked list of pages. Pages are added and deleted as necessary.
 * 该堆栈被划分为一个双链接的页面列表。根据需要添加和删除页面。
 * Thread-local storage points to the hot page, where newly autoreleased objects are stored.
 */

// Set this to 1 to mprotect() autorelease pool contents
#define PROTECT_AUTORELEASEPOOL 0

// Set this to 1 to validate the entire autorelease pool header all the time
// (i.e. use check() instead of fastcheck() everywhere)
#define CHECK_AUTORELEASEPOOL (DEBUG)

BREAKPOINT_FUNCTION(void objc_autoreleaseNoPool(id obj));
BREAKPOINT_FUNCTION(void objc_autoreleasePoolInvalid(const void *token));

namespace {
    struct magic_t {
        static const uint32_t M0 = 0xA1A1A1A1;
#   define M1 "AUTORELEASE!"
        static const size_t M1_len = 12;
        uint32_t m[4];
        
        magic_t() {
            assert(M1_len == strlen(M1));
            assert(M1_len == 3 * sizeof(m[1]));
            m[0] = M0;
            strncpy((char *)&m[1], M1, M1_len);
        }
        
        ~magic_t() {
            m[0] = m[1] = m[2] = m[3] = 0;
        }
        
        bool check() const {
            return (m[0] == M0 && 0 == strncmp((char *)&m[1], M1, M1_len));
        }
        
        bool fastcheck() const {
#if CHECK_AUTORELEASEPOOL
            return check();
#else
            return (m[0] == M0);
#endif
        }
        
#   undef M1
    };
    
    /* 自动释放池
     * 1、自动释放池是由 AutoreleasePoolPage 以双向链表的方式实现的
     * 2、当对象调用 -autorelease 方法时，会将对象加入 AutoreleasePoolPage 的栈中
     * 3、调用 AutoreleasePoolPage::pop 方法会向栈中的对象发送 release 消息
     * 4、新建线程会第一个autorelease对象时候，新建AutoreleasePool，线程销毁AutoreleasePool释放对象且销毁
     * 5、每个AutoreleasePoolPage对象大小为4096， 对象本身信息占 56 个字节, 所以 begin() 需要排除这 56 个字节, 真正用于存储 autorelease 对象地址的内存量为 end() - begin(), 共有 4040 个字节, 可存储 505 个 autorelease 变量（一个对象8个字节）.
     */
    class AutoreleasePoolPage{
        // EMPTY_POOL_PLACEHOLDER is stored in TLS when exactly one pool is pushed and it has never contained any objects.
        // This saves memory when the top level (i.e. libdispatch) pushes and pops pools but never uses them.

#   define EMPTY_POOL_PLACEHOLDER ((id*)1)
        
#   define POOL_BOUNDARY nil
        static pthread_key_t const key = AUTORELEASE_POOL_KEY;
        static uint8_t const SCRIBBLE = 0xA3;  // 0xA3A3A3A3 after releasing
        static size_t const SIZE =
#if PROTECT_AUTORELEASEPOOL
        PAGE_MAX_SIZE;  // must be multiple of vm page size
#else
        PAGE_MAX_SIZE;  // size and alignment, power of 2
#endif
        static size_t const COUNT = SIZE / sizeof(id);
        
        magic_t const magic;//检查 AutoreleasePoolPage 的内存没有被修改的，放在第一个也就是这个原因，防止前面地址有内容溢过来。
        id *next;// 存放下一个 autorelease 对象指针
        pthread_t const thread;//自动释放池对应的线程
        
        // AutoreleasePoolPage 就是一个双向链表，毕竟一个 AutoreleasePoolPage 能存放的对象是有限的。
        AutoreleasePoolPage * const parent;// 用来保存前一个 AutoreleasePoolPage
        AutoreleasePoolPage *child;// 用来保存后一个 AutoreleasePoolPage
        uint32_t const depth;//这个链表有多深
        uint32_t hiwat;//最高有记录过多少对象
        
        // SIZE-sizeof(*this) bytes of contents follow
        
        static void * operator new(size_t size) {
            return malloc_zone_memalign(malloc_default_zone(), SIZE, SIZE);
        }
        static void operator delete(void * p) {
            return free(p);
        }
        
        inline void protect() {
#if PROTECT_AUTORELEASEPOOL
            mprotect(this, SIZE, PROT_READ);
            check();
#endif
        }
        
        inline void unprotect() {
#if PROTECT_AUTORELEASEPOOL
            check();
            mprotect(this, SIZE, PROT_READ | PROT_WRITE);
#endif
        }
        
        AutoreleasePoolPage(AutoreleasePoolPage *newParent)
        : magic(), next(begin()), thread(pthread_self()),
        parent(newParent), child(nil),
        depth(parent ? 1+parent->depth : 0),
        hiwat(parent ? parent->hiwat : 0)
        {
            if (parent) {
                parent->check();
                assert(!parent->child);
                parent->unprotect();
                parent->child = this;
                parent->protect();
            }
            protect();
        }
        
        ~AutoreleasePoolPage()
        {
            check();
            unprotect();
            assert(empty());
            
            // Not recursive: we don't want to blow out the stack
            // if a thread accumulates a stupendous amount of garbage
            assert(!child);
        }
        
        
        void busted(bool die = true)
        {
            magic_t right;
            (die ? _objc_fatal : _objc_inform)
            ("autorelease pool page %p corrupted\n"
             "  magic     0x%08x 0x%08x 0x%08x 0x%08x\n"
             "  should be 0x%08x 0x%08x 0x%08x 0x%08x\n"
             "  pthread   %p\n"
             "  should be %p\n",
             this,
             magic.m[0], magic.m[1], magic.m[2], magic.m[3],
             right.m[0], right.m[1], right.m[2], right.m[3],
             this->thread, pthread_self());
        }
        
        void check(bool die = true)
        {
            if (!magic.check() || !pthread_equal(thread, pthread_self())) {
                busted(die);
            }
        }
        
        void fastcheck(bool die = true){
#if CHECK_AUTORELEASEPOOL
            check(die);
#else
            if (! magic.fastcheck()) {
                busted(die);
            }
#endif
        }
        
        
        id * begin() {
            return (id *) ((uint8_t *)this+sizeof(*this));
        }
        
        id * end() {
            return (id *) ((uint8_t *)this+SIZE);
        }
        
        bool empty() {//链表是否为空
            return next == begin();
        }
        
        bool full() {//链表是否存储满
            return next == end();
        }
        
        bool lessThanHalfFull() {
            return (next - begin() < (end() - begin()) / 2);
        }
        
        id *add(id obj){//将 obj 存入栈
            assert(!full());
            unprotect();
            id *ret = next;  // faster than `return next-1` because of aliasing
            *next++ = obj;
            protect();
            return ret;
        }
        
        void releaseAll(){ //调用内部数组中对象的 -release 方法
            releaseUntil(begin());
        }
        
        void releaseUntil(id *stop){
            // Not recursive: we don't want to blow out the stack
            // if a thread accumulates a stupendous amount of garbage
            
            while (this->next != stop) {
                // Restart from hotPage() every time, in case -release
                // autoreleased more objects
                AutoreleasePoolPage *page = hotPage();
                
                // fixme I think this `while` can be `if`, but I can't prove it
                while (page->empty()) {
                    page = page->parent;
                    setHotPage(page);
                }
                
                page->unprotect();
                id obj = *--page->next;
                memset((void*)page->next, SCRIBBLE, sizeof(*page->next));
                page->protect();
                
                if (obj != POOL_BOUNDARY) {
                    objc_release(obj);//调用 release
                }
            }
            
            setHotPage(this);
            
#if DEBUG
            // we expect any children to be completely empty
            for (AutoreleasePoolPage *page = child; page; page = page->child) {
                assert(page->empty());
            }
#endif
        }
        
        void kill(){
            // Not recursive: we don't want to blow out the stack
            // if a thread accumulates a stupendous amount of garbage
            AutoreleasePoolPage *page = this;
            while (page->child) page = page->child;
            
            AutoreleasePoolPage *deathptr;
            do {
                deathptr = page;
                page = page->parent;
                if (page) {
                    page->unprotect();
                    page->child = nil;
                    page->protect();
                }
                delete deathptr;
            } while (deathptr != this);
        }
        
        static void tls_dealloc(void *p){
            if (p == (void*)EMPTY_POOL_PLACEHOLDER) {
                // No objects or pool pages to clean up here.
                return;
            }
            
            // reinstate TLS value while we work
            setHotPage((AutoreleasePoolPage *)p);
            
            if (AutoreleasePoolPage *page = coldPage()) {
                if (!page->empty()) pop(page->begin());  // pop all of the pools
                if (DebugMissingPools || DebugPoolAllocation) {
                    // pop() killed the pages already
                } else {
                    page->kill();  // free all of the pages
                }
            }
            
            // clear TLS value so TLS destruction doesn't loop
            setHotPage(nil);
        }
        
        static AutoreleasePoolPage *pageForPointer(const void *p){
            return pageForPointer((uintptr_t)p);
        }
        
        static AutoreleasePoolPage *pageForPointer(uintptr_t p){
            AutoreleasePoolPage *result;
            uintptr_t offset = p % SIZE;
            
            assert(offset >= sizeof(AutoreleasePoolPage));
            
            result = (AutoreleasePoolPage *)(p - offset);
            result->fastcheck();
            
            return result;
        }
        
        
        static inline bool haveEmptyPoolPlaceholder(){
            id *tls = (id *)tls_get_direct(key);
            return (tls == EMPTY_POOL_PLACEHOLDER);
        }
        
        static inline id* setEmptyPoolPlaceholder(){
            assert(tls_get_direct(key) == nil);
            tls_set_direct(key, (void *)EMPTY_POOL_PLACEHOLDER);
            return EMPTY_POOL_PLACEHOLDER;
        }
        
        static inline AutoreleasePoolPage *hotPage()
        {
            AutoreleasePoolPage *result = (AutoreleasePoolPage *)
            tls_get_direct(key);
            if ((id *)result == EMPTY_POOL_PLACEHOLDER) return nil;
            if (result) result->fastcheck();
            return result;
        }
        
        static inline void setHotPage(AutoreleasePoolPage *page){
            if (page) page->fastcheck();
            tls_set_direct(key, (void *)page);
        }
        
        static inline AutoreleasePoolPage *coldPage()
        {
            AutoreleasePoolPage *result = hotPage();
            if (result) {
                while (result->parent) {
                    result = result->parent;
                    result->fastcheck();
                }
            }
            return result;
        }
        
        
        static inline id *autoreleaseFast(id obj){
            AutoreleasePoolPage *page = hotPage();
            if (page && !page->full()) {//如果自动释放池存在且没有满
                return page->add(obj);
            } else if (page) {//如果自动释放池已满
                return autoreleaseFullPage(obj, page);
            } else {//如果自动释放池不存在
                return autoreleaseNoPage(obj);
            }
        }
        
        static __attribute__((noinline)) id *autoreleaseFullPage(id obj, AutoreleasePoolPage *page){
            // The hot page is full.
            // Step to the next non-full page, adding a new page if necessary.
            // Then add the object to that page.
            assert(page == hotPage());
            assert(page->full()  ||  DebugPoolAllocation);
            
            do {
                if (page->child) page = page->child;
                else page = new AutoreleasePoolPage(page);
            } while (page->full());
            
            setHotPage(page);
            return page->add(obj);
        }
        
        static __attribute__((noinline)) id *autoreleaseNoPage(id obj){
            /* No page 可能意味着没有 pool，或者已经推送了一个空占位 pool ，但还没有内容
             * "No page" could mean no pool has been pushed
             * or an empty placeholder pool has been pushed and has no contents yet
             */
            assert(!hotPage());
            
            bool pushExtraBoundary = false;
            if (haveEmptyPoolPlaceholder()) {
                // We are pushing a second pool over the empty placeholder pool
                // or pushing the first object into the empty placeholder pool.
                // Before doing that, push a pool boundary on behalf of the pool
                // that is currently represented by the empty placeholder.
                pushExtraBoundary = true;
            }else if (obj != POOL_BOUNDARY  &&  DebugMissingPools) {
                // We are pushing an object with no pool in place,
                // and no-pool debugging was requested by environment.
                _objc_inform("MISSING POOLS: (%p) Object %p of class %s "
                             "autoreleased with no pool in place - "
                             "just leaking - break on "
                             "objc_autoreleaseNoPool() to debug",
                             pthread_self(), (void*)obj, object_getClassName(obj));
                objc_autoreleaseNoPool(obj);
                return nil;
            }else if (obj == POOL_BOUNDARY  &&  !DebugPoolAllocation) {
                // We are pushing a pool with no pool in place,
                // and alloc-per-pool debugging was not requested.
                // Install and return the empty pool placeholder.
                return setEmptyPoolPlaceholder();
            }
            
            // We are pushing an object or a non-placeholder'd pool.
            
            // Install the first page.
            AutoreleasePoolPage *page = new AutoreleasePoolPage(nil);
            setHotPage(page);
            
            // Push a boundary on behalf of the previously-placeholder'd pool.
            if (pushExtraBoundary) {
                page->add(POOL_BOUNDARY);
            }
            
            // Push the requested object or pool.
            return page->add(obj);
        }
        
        
        static __attribute__((noinline)) id *autoreleaseNewPage(id obj){
            AutoreleasePoolPage *page = hotPage();
            if (page) return autoreleaseFullPage(obj, page);
            else return autoreleaseNoPage(obj);
        }
        
    public:
        static inline id autorelease(id obj){//相当于 NSAutoreleasePool 类的 addObject 类方法
            assert(obj);
            assert(!obj->isTaggedPointer());
            id *dest __unused = autoreleaseFast(obj);
            assert(!dest  ||  dest == EMPTY_POOL_PLACEHOLDER  ||  *dest == obj);
            return obj;
        }
        
        
        static inline void *push(){//相当于生成或持有 NSAutoreleasePool 类对象
            id *dest;
            if (DebugPoolAllocation) {
                // Each autorelease pool starts on a new pool page.
                dest = autoreleaseNewPage(POOL_BOUNDARY);
            } else {
                dest = autoreleaseFast(POOL_BOUNDARY);
            }
            assert(dest == EMPTY_POOL_PLACEHOLDER || *dest == POOL_BOUNDARY);
            return dest;
        }
        
        static void badPop(void *token)
        {
            // Error. For bincompat purposes this is not
            // fatal in executables built with old SDKs.
            
            if (DebugPoolAllocation || sdkIsAtLeast(10_12, 10_0, 10_0, 3_0, 2_0)) {
                // OBJC_DEBUG_POOL_ALLOCATION or new SDK. Bad pop is fatal.
                _objc_fatal
                ("Invalid or prematurely-freed autorelease pool %p.", token);
            }
            
            // Old SDK. Bad pop is warned once.
            static bool complained = false;
            if (!complained) {
                complained = true;
                _objc_inform_now_and_on_crash
                ("Invalid or prematurely-freed autorelease pool %p. "
                 "Set a breakpoint on objc_autoreleasePoolInvalid to debug. "
                 "Proceeding anyway because the app is old "
                 "(SDK version " SDK_FORMAT "). Memory errors are likely.",
                 token, FORMAT_SDK(sdkVersion()));
            }
            objc_autoreleasePoolInvalid(token);
        }
        
        static inline void pop(void *token){//相当于生成或持有 NSAutoreleasePool 类对象
            AutoreleasePoolPage *page;
            id *stop;
            if (token == (void*)EMPTY_POOL_PLACEHOLDER) {
                // Popping the top-level placeholder pool.
                if (hotPage()) {
                    // Pool was used. Pop its contents normally.
                    // Pool pages remain allocated for re-use as usual.
                    pop(coldPage()->begin());
                } else {
                    // Pool was never used. Clear the placeholder.
                    setHotPage(nil);
                }
                return;
            }
            
            page = pageForPointer(token);
            stop = (id *)token;
            if (*stop != POOL_BOUNDARY) {
                if (stop == page->begin()  &&  !page->parent) {
                    // Start of coldest page may correctly not be POOL_BOUNDARY:
                    // 1. top-level pool is popped, leaving the cold page in place
                    // 2. an object is autoreleased with no pool
                } else {
                    // Error. For bincompat purposes this is not
                    // fatal in executables built with old SDKs.
                    return badPop(token);
                }
            }
            
            if (PrintPoolHiwat) printHiwat();
            
            page->releaseUntil(stop);
            
            // memory: delete empty children
            if (DebugPoolAllocation  &&  page->empty()) {
                // special case: delete everything during page-per-pool debugging
                AutoreleasePoolPage *parent = page->parent;
                page->kill();
                setHotPage(parent);
            } else if (DebugMissingPools  &&  page->empty()  &&  !page->parent) {
                // special case: delete everything for pop(top)
                // when debugging missing autorelease pools
                page->kill();
                setHotPage(nil);
            }
            else if (page->child) {
                // hysteresis: keep one empty child if page is more than half full
                if (page->lessThanHalfFull()) {
                    page->child->kill();
                }
                else if (page->child->child) {
                    page->child->child->kill();
                }
            }
        }
        
        static void init()
        {
            int r __unused = pthread_key_init_np(AutoreleasePoolPage::key,
                                                 AutoreleasePoolPage::tls_dealloc);
            assert(r == 0);
        }
        
        void print()
        {
            _objc_inform("[%p]  ................  PAGE %s %s %s", this,
                         full() ? "(full)" : "",
                         this == hotPage() ? "(hot)" : "",
                         this == coldPage() ? "(cold)" : "");
            check(false);
            for (id *p = begin(); p < next; p++) {
                if (*p == POOL_BOUNDARY) {
                    _objc_inform("[%p]  ################  POOL %p", p, p);
                } else {
                    _objc_inform("[%p]  %#16lx  %s",
                                 p, (unsigned long)*p, object_getClassName(*p));
                }
            }
        }
        
        static void printAll()
        {
            _objc_inform("##############");
            _objc_inform("AUTORELEASE POOLS for thread %p", pthread_self());
            
            AutoreleasePoolPage *page;
            ptrdiff_t objects = 0;
            for (page = coldPage(); page; page = page->child) {
                objects += page->next - page->begin();
            }
            _objc_inform("%llu releases pending.", (unsigned long long)objects);
            
            if (haveEmptyPoolPlaceholder()) {
                _objc_inform("[%p]  ................  PAGE (placeholder)",
                             EMPTY_POOL_PLACEHOLDER);
                _objc_inform("[%p]  ################  POOL (placeholder)",
                             EMPTY_POOL_PLACEHOLDER);
            }
            else {
                for (page = coldPage(); page; page = page->child) {
                    page->print();
                }
            }
            
            _objc_inform("##############");
        }
        
        static void printHiwat()
        {
            // Check and propagate high water mark
            // Ignore high water marks under 256 to suppress noise.
            AutoreleasePoolPage *p = hotPage();
            uint32_t mark = p->depth*COUNT + (uint32_t)(p->next - p->begin());
            if (mark > p->hiwat  &&  mark > 256) {
                for( ; p; p = p->parent) {
                    p->unprotect();
                    p->hiwat = mark;
                    p->protect();
                }
                
                _objc_inform("POOL HIGHWATER: new high water mark of %u "
                             "pending releases for thread %p:",
                             mark, pthread_self());
                
                void *stack[128];
                int count = backtrace(stack, sizeof(stack)/sizeof(stack[0]));
                char **sym = backtrace_symbols(stack, count);
                for (int i = 0; i < count; i++) {
                    _objc_inform("POOL HIGHWATER:     %s", sym[i]);
                }
                free(sym);
            }
        }
        
#undef POOL_BOUNDARY
    };
    
    // anonymous namespace
};


/***********************************************************************
 * Slow paths for inline control
 **********************************************************************/

#if SUPPORT_NONPOINTER_ISA

NEVER_INLINE id objc_object::rootRetain_overflow(bool tryRetain){
    return rootRetain(tryRetain, true);
}


NEVER_INLINE bool objc_object::rootRelease_underflow(bool performDealloc){
    return rootRelease(performDealloc, true);
}


// Slow path of clearDeallocating()
// for objects with nonpointer isa
// that were ever weakly referenced
// or whose retain count ever overflowed to the side table.
/** 当前对象支持nonpointer时，清除弱引用指针以及引用计数:
 *      此时是否存在弱引用的标志存储在 isa 的 weakly_referenced 位域中.
 */
NEVER_INLINE void objc_object::clearDeallocating_slow(){
    assert(isa.nonpointer  &&  (isa.weakly_referenced || isa.has_sidetable_rc));
    SideTable& table = SideTables()[this];
    table.lock();//添加线程锁
    if (isa.weakly_referenced) {//清除弱引用表
        weak_clear_no_lock(&table.weak_table, (id)this);
    }
    if (isa.has_sidetable_rc) {
        table.refcnts.erase(this);//清除引用计数
    }
    table.unlock();
}

#endif

__attribute__((noinline,used)) id objc_object::rootAutorelease2(){
    assert(!isTaggedPointer());
    return AutoreleasePoolPage::autorelease((id)this);
}

BREAKPOINT_FUNCTION(void objc_overrelease_during_dealloc_error(void));


NEVER_INLINE
bool objc_object::overrelease_error(){
    _objc_inform_now_and_on_crash("%s object %p overreleased while already deallocating; break on objc_overrelease_during_dealloc_error to debug", object_getClassName((id)this), this);
    objc_overrelease_during_dealloc_error();
    return false;  // allow rootRelease() to tail-call this
}


/* 散列表的 Retain count
 */

#if DEBUG
// Used to assert that an object is not present in the side table.
bool objc_object::sidetable_present(){
    bool result = false;
    SideTable& table = SideTables()[this];
    table.lock();
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it != table.refcnts.end()) result = true;
    if (weak_is_registered_no_lock(&table.weak_table, (id)this)) result = true;
    table.unlock();
    return result;
}
#endif

#if SUPPORT_NONPOINTER_ISA

void objc_object::sidetable_lock(){
    SideTable& table = SideTables()[this];
    table.lock();
}

void objc_object::sidetable_unlock(){
    SideTable& table = SideTables()[this];
    table.unlock();
}


// Move the entire retain count to the side table,
// as well as isDeallocating and weaklyReferenced.
void objc_object::sidetable_moveExtraRC_nolock(size_t extra_rc,
                                          bool isDeallocating,
                                          bool weaklyReferenced){
    assert(!isa.nonpointer);        // should already be changed to raw pointer
    SideTable& table = SideTables()[this];
    
    size_t& refcntStorage = table.refcnts[this];
    size_t oldRefcnt = refcntStorage;
    // not deallocating - that was in the isa
    assert((oldRefcnt & SIDE_TABLE_DEALLOCATING) == 0);
    assert((oldRefcnt & SIDE_TABLE_WEAKLY_REFERENCED) == 0);
    
    uintptr_t carry;
    size_t refcnt = addc(oldRefcnt, extra_rc << SIDE_TABLE_RC_SHIFT, 0, &carry);
    if (carry) refcnt = SIDE_TABLE_RC_PINNED;
    if (isDeallocating) refcnt |= SIDE_TABLE_DEALLOCATING;
    if (weaklyReferenced) refcnt |= SIDE_TABLE_WEAKLY_REFERENCED;
    
    refcntStorage = refcnt;
}


// Move some retain counts to the side table from the isa field.
// Returns true if the object is now pinned.
bool objc_object::sidetable_addExtraRC_nolock(size_t delta_rc){
    assert(isa.nonpointer);
    SideTable& table = SideTables()[this];
    
    size_t& refcntStorage = table.refcnts[this];
    size_t oldRefcnt = refcntStorage;
    // isa-side bits should not be set here
    assert((oldRefcnt & SIDE_TABLE_DEALLOCATING) == 0);
    assert((oldRefcnt & SIDE_TABLE_WEAKLY_REFERENCED) == 0);
    
    if (oldRefcnt & SIDE_TABLE_RC_PINNED) return true;
    
    uintptr_t carry;
    size_t newRefcnt =
    addc(oldRefcnt, delta_rc << SIDE_TABLE_RC_SHIFT, 0, &carry);
    if (carry) {
        refcntStorage =
        SIDE_TABLE_RC_PINNED | (oldRefcnt & SIDE_TABLE_FLAG_MASK);
        return true;
    }
    else {
        refcntStorage = newRefcnt;
        return false;
    }
}


// Move some retain counts from the side table to the isa field.
// Returns the actual count subtracted, which may be less than the request.
size_t objc_object::sidetable_subExtraRC_nolock(size_t delta_rc){
    assert(isa.nonpointer);
    SideTable& table = SideTables()[this];
    
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it == table.refcnts.end()  ||  it->second == 0) {
        // Side table retain count is zero. Can't borrow.
        return 0;
    }
    size_t oldRefcnt = it->second;
    
    // isa-side bits should not be set here
    assert((oldRefcnt & SIDE_TABLE_DEALLOCATING) == 0);
    assert((oldRefcnt & SIDE_TABLE_WEAKLY_REFERENCED) == 0);
    
    size_t newRefcnt = oldRefcnt - (delta_rc << SIDE_TABLE_RC_SHIFT);
    assert(oldRefcnt > newRefcnt);  // shouldn't underflow
    it->second = newRefcnt;
    return delta_rc;
}


size_t objc_object::sidetable_getExtraRC_nolock(){
    assert(isa.nonpointer);
    SideTable& table = SideTables()[this];
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it == table.refcnts.end()) return 0;
    else return it->second >> SIDE_TABLE_RC_SHIFT;
}


// SUPPORT_NONPOINTER_ISA
#endif

/** 对象的引用计数 +1 操作
 * 该函数的主要功能：
 * 1、通过对象内存地址，在SideTables找到对应的SideTable
 * 2、通过对象内存地址，在refcnts中取出引用计数
 * 3、判断引用计数是否增加到最大值，如果没有，则 +4
 */
id objc_object::sidetable_retain(){
#if SUPPORT_NONPOINTER_ISA
    assert(!isa.nonpointer);
#endif
    SideTable& table = SideTables()[this];//在SideTables找到对应的SideTable
    table.lock();
    size_t& refcntStorage = table.refcnts[this];//在 RefcountMap 中取出引用计数
    if (!(refcntStorage & SIDE_TABLE_RC_PINNED)) {
        refcntStorage += SIDE_TABLE_RC_ONE;// 没有到最大值，1 则+4
    }
    table.unlock();
    return (id)this;
}


bool objc_object::sidetable_tryRetain(){
#if SUPPORT_NONPOINTER_ISA
    assert(!isa.nonpointer);
#endif
    SideTable& table = SideTables()[this];
    
    // NO SPINLOCK HERE
    // _objc_rootTryRetain() is called exclusively by _objc_loadWeak(),
    // which already acquired the lock on our behalf.
    
    // fixme can't do this efficiently with os_lock_handoff_s
    // if (table.slock == 0) {
    //     _objc_fatal("Do not call -_tryRetain.");
    // }
    
    bool result = true;
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it == table.refcnts.end()) {
        table.refcnts[this] = SIDE_TABLE_RC_ONE;
    } else if (it->second & SIDE_TABLE_DEALLOCATING) {
        result = false;
    } else if (! (it->second & SIDE_TABLE_RC_PINNED)) {
        it->second += SIDE_TABLE_RC_ONE;
    }
    
    return result;
}

/*  获取引用计数 retainCount
 */
uintptr_t objc_object::sidetable_retainCount(){
    SideTable& table = SideTables()[this];
    size_t refcnt_result = 1;
    table.lock();
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it != table.refcnts.end()) {
        // this is valid for SIDE_TABLE_RC_PINNED too
        refcnt_result += it->second >> SIDE_TABLE_RC_SHIFT;
    }
    table.unlock();
    return refcnt_result;
}


bool objc_object::sidetable_isDeallocating(){
    SideTable& table = SideTables()[this];
    
    // NO SPINLOCK HERE
    // _objc_rootIsDeallocating() is called exclusively by _objc_storeWeak(),
    // which already acquired the lock on our behalf.
    
    
    // fixme can't do this efficiently with os_lock_handoff_s
    // if (table.slock == 0) {
    //     _objc_fatal("Do not call -_isDeallocating.");
    // }
    
    RefcountMap::iterator it = table.refcnts.find(this);
    return (it != table.refcnts.end()) && (it->second & SIDE_TABLE_DEALLOCATING);
}


/*  是否是弱引用
 */
bool objc_object::sidetable_isWeaklyReferenced(){
    bool result = false;
    SideTable& table = SideTables()[this];
    table.lock();
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it != table.refcnts.end()) {
        result = it->second & SIDE_TABLE_WEAKLY_REFERENCED;
    }
    table.unlock();
    return result;
}

/* 设置弱引用
 */
void objc_object::sidetable_setWeaklyReferenced_nolock(){
#if SUPPORT_NONPOINTER_ISA
    assert(!isa.nonpointer);
#endif
    SideTable& table = SideTables()[this];
    table.refcnts[this] |= SIDE_TABLE_WEAKLY_REFERENCED;
}


/** 对象的引用计数 -1 操作
 * 该函数的主要功能：
 * 1、通过对象内存地址，在 SideTables 找到对应的SideTable
 * 2、通过对象内存地址，在refcnts中取出引用计数
 * 3、判断引用计数是否增加到最大值，如果没有，则 +4
 */
uintptr_t objc_object::sidetable_release(bool performDealloc){
#if SUPPORT_NONPOINTER_ISA
    assert(!isa.nonpointer);
#endif
    SideTable& table = SideTables()[this];//在 SideTables 找到对应的SideTable
    
    bool do_dealloc = false;
    
    table.lock();
    RefcountMap::iterator it = table.refcnts.find(this);//在refcnts中取出引用计数
    if (it == table.refcnts.end()) {
        /* table.refcnts.end()表示使用一个iterator迭代器到达了end()状态
         * end() 状态表示从头开始查找，一直找到最后都没有找到
         * 该条 if 语句表示查找到最后都没找到引用计数表 RefcountMap
         */
        do_dealloc = true;
        table.refcnts[this] = SIDE_TABLE_DEALLOCATING;//标记对象为正在释放
    } else if (it->second < SIDE_TABLE_DEALLOCATING) {
        //高位的引用计数位都是0,低位的弱引用标记位可能有弱引用为 1、也可能没有弱引用为 0
        do_dealloc = true;
        it->second |= SIDE_TABLE_DEALLOCATING; //不会影响 弱引用标记位
    } else if (! (it->second & SIDE_TABLE_RC_PINNED)) {
        it->second -= SIDE_TABLE_RC_ONE; //引用计数 -1
    }
    table.unlock();
    if (do_dealloc  &&  performDealloc) {//如果需要释放对象，则调用dealloc
        ((void(*)(objc_object *, SEL))objc_msgSend)(this, SEL_dealloc);
    }
    return do_dealloc;
}

/** 当前对象不支持 nonpointer 时，清除sidetable中的弱引用指针以及引用计数：
*      此时是否存在弱引用指针的标志存储在 RefcountMap::iterator 中的成员变量 second 中.
*
*/
void objc_object::sidetable_clearDeallocating(){
    SideTable& table = SideTables()[this];
    // clear any weak table items
    // clear extra retain count and deallocating bit
    // (fixme warn or abort if extra retain count == 0 ?)
    table.lock();//添加线程锁
    RefcountMap::iterator it = table.refcnts.find(this);
    if (it != table.refcnts.end()) {
        if (it->second & SIDE_TABLE_WEAKLY_REFERENCED) {//如果弱引用位为 1
            weak_clear_no_lock(&table.weak_table, (id)this);//在对象被销毁时处理所有弱引用指针
        }
        table.refcnts.erase(it);//从 refcnts 中删除引用计数器
    }
    table.unlock();
}

 
/** 优化 retain/release/autorelease 函数
 */
#if __OBJC2__

__attribute__((aligned(16))) id objc_retain(id obj){
    if (!obj) return obj;
    if (obj->isTaggedPointer()) return obj;
    return obj->retain();
}

__attribute__((aligned(16))) void objc_release(id obj){
    if (!obj) return;
    if (obj->isTaggedPointer()) return;
    return obj->release();
}

__attribute__((aligned(16))) id objc_autorelease(id obj){
    if (!obj) return obj;
    if (obj->isTaggedPointer()) return obj;
    return obj->autorelease();
}

// OBJC2
#else
// not OBJC2

id objc_retain(id obj) { return [obj retain]; }
void objc_release(id obj) { [obj release]; }
id objc_autorelease(id obj) { return [obj autorelease]; }

#endif


/** 根类实现的基本操作，也就是_objc_root*()
 */

bool _objc_rootTryRetain(id obj){
    assert(obj);
    return obj->rootTryRetain();
}

bool _objc_rootIsDeallocating(id obj){
    assert(obj);
    return obj->rootIsDeallocating();
}


void objc_clear_deallocating(id obj){
    assert(obj);
    if (obj->isTaggedPointer()) return;
    obj->clearDeallocating();
}


bool _objc_rootReleaseWasZero(id obj){
    assert(obj);
    return obj->rootReleaseShouldDealloc();
}


id _objc_rootAutorelease(id obj){
    assert(obj);
    return obj->rootAutorelease();
}

uintptr_t _objc_rootRetainCount(id obj){
    assert(obj);
    return obj->rootRetainCount();
}


id _objc_rootRetain(id obj){
    assert(obj);
    return obj->rootRetain();
}

void _objc_rootRelease(id obj){
    assert(obj);
    obj->rootRelease();
}

id _objc_rootAllocWithZone(Class cls, malloc_zone_t *zone){
    id obj;
#if __OBJC2__
    // allocWithZone under __OBJC2__ ignores the zone parameter
    (void)zone;
    obj = class_createInstance(cls, 0);
#else
    if (!zone) {
        obj = class_createInstance(cls, 0);
    } else {
        obj = class_createInstanceFromZone(cls, 0, zone);
    }
#endif
    if (slowpath(!obj)) obj = callBadAllocHandler(cls);
    return obj;
}

/** 调用 +alloc 或者 +allocWithZone: 方法，使用该函数
 * 该函数真实地创建实例关键在class_createInstance() 上。其他代码主要是去判断是否自定义alloc等
 * @param cls 不能为 nil ，否则返回 nil
 * @param checkNil 若为 false ，则返回 nil
 */
static ALWAYS_INLINE id
callAlloc(Class cls, bool checkNil, bool allocWithZone=false){
    if (slowpath(checkNil && !cls)) return nil;
    
#if __OBJC2__
    if (fastpath(!cls->ISA()->hasCustomAWZ())) {
        // No alloc/allocWithZone implementation. Go straight to the allocator.
        // fixme store hasCustomAWZ in the non-meta class and add it to canAllocFast's summary
        //
        if (fastpath(cls->canAllocFast())) {
            // No ctors, raw isa, etc. Go straight to the metal.
            bool dtor = cls->hasCxxDtor();
            id obj = (id)calloc(1, cls->bits.fastInstanceSize());
            if (slowpath(!obj)) return callBadAllocHandler(cls);
            obj->initInstanceIsa(cls, dtor);
            return obj;
        }else {
            // Has ctor or raw isa or something. Use the slower path.
            id obj = class_createInstance(cls, 0);
            if (slowpath(!obj)) return callBadAllocHandler(cls);
            return obj;
        }
    }
#endif
    // No shortcuts available.
    if (allocWithZone) {
        return ((id(*)(id, SEL, struct _NSZone *))objc_msgSend)(cls, @selector(allocWithZone:), nil);
    }
    return ((id(*)(id, SEL))objc_msgSend)(cls, @selector(alloc));
}

/* 基类调用 +alloc
 * @param cls 不能为 nil
 */
// Calls [cls allocWithZone:nil].
id _objc_rootAlloc(Class cls){
    return callAlloc(cls, false, true);
}

// Calls [cls alloc].
id objc_alloc(Class cls){
    return callAlloc(cls, true/*checkNil*/, false/*allocWithZone*/);
}

// Calls [cls allocWithZone:nil].
id objc_allocWithZone(Class cls){
    return callAlloc(cls, true/*checkNil*/, true/*allocWithZone*/);
}


void _objc_rootDealloc(id obj){
    assert(obj);
    obj->rootDealloc();
}

void _objc_rootFinalize(id obj __unused){
    assert(obj);
    _objc_fatal("_objc_rootFinalize called with garbage collection off");
}


id _objc_rootInit(id obj){
    // In practice, it will be hard to rely on this function.
    // Many classes do not properly chain -init calls.
    return obj;
}


malloc_zone_t * _objc_rootZone(id obj){
    (void)obj;
#if __OBJC2__
    // allocWithZone under __OBJC2__ ignores the zone parameter
    return malloc_default_zone();
#else
    malloc_zone_t *rval = malloc_zone_from_ptr(obj);
    return rval ? rval : malloc_default_zone();
#endif
}

uintptr_t _objc_rootHash(id obj){
    return (uintptr_t)obj;
}

void * objc_autoreleasePoolPush(void){
    return AutoreleasePoolPage::push();
}

void objc_autoreleasePoolPop(void *ctxt){
    AutoreleasePoolPage::pop(ctxt);
}


void * _objc_autoreleasePoolPush(void){
    return objc_autoreleasePoolPush();
}

void _objc_autoreleasePoolPop(void *ctxt){
    objc_autoreleasePoolPop(ctxt);
}

void _objc_autoreleasePoolPrint(void){
    AutoreleasePoolPage::printAll();
}


// Same as objc_release but suitable for tail-calling
// if you need the value back and don't want to push a frame before this point.
__attribute__((noinline)) static id objc_releaseAndReturn(id obj){
    objc_release(obj);
    return obj;
}

// Same as objc_retainAutorelease but suitable for tail-calling
// if you don't want to push a frame before this point.
__attribute__((noinline)) static id objc_retainAutoreleaseAndReturn(id obj){
    return objc_retainAutorelease(obj);
}


// Prepare a value at +1 for return through a +0 autoreleasing convention.
id objc_autoreleaseReturnValue(id obj){
    if (prepareOptimizedReturn(ReturnAtPlus1)) return obj;
    return objc_autorelease(obj);
}

// Prepare a value at +0 for return through a +0 autoreleasing convention.
id objc_retainAutoreleaseReturnValue(id obj){
    if (prepareOptimizedReturn(ReturnAtPlus0)) return obj;
    // not objc_autoreleaseReturnValue(objc_retain(obj))
    // because we don't need another optimization attempt
    return objc_retainAutoreleaseAndReturn(obj);
}

// Accept a value returned through a +0 autoreleasing convention for use at +1.
id objc_retainAutoreleasedReturnValue(id obj){
    if (acceptOptimizedReturn() == ReturnAtPlus1) return obj;
    return objc_retain(obj);
}

// Accept a value returned through a +0 autoreleasing convention for use at +0.
id objc_unsafeClaimAutoreleasedReturnValue(id obj){
    if (acceptOptimizedReturn() == ReturnAtPlus0) return obj;
    return objc_releaseAndReturn(obj);
}

id objc_retainAutorelease(id obj){
    return objc_autorelease(objc_retain(obj));
}

void _objc_deallocOnMainThreadHelper(void *context){
    id obj = (id)context;
    [obj dealloc];
}

// convert objc_objectptr_t to id, callee must take ownership.
id objc_retainedObject(objc_objectptr_t pointer) { return (id)pointer; }

// convert objc_objectptr_t to id, without ownership transfer.
id objc_unretainedObject(objc_objectptr_t pointer) { return (id)pointer; }

// convert id to objc_objectptr_t, no ownership transfer.
objc_objectptr_t objc_unretainedPointer(id object) { return object; }


// 初始化自动释放池与哈希表
void arr_init(void) {
    AutoreleasePoolPage::init();
    SideTableInit();
}


#if SUPPORT_TAGGED_POINTERS

// Placeholder for old debuggers. When they inspect an extended tagged pointer object they will see this isa.
@interface __NSUnrecognizedTaggedPointer : NSObject
@end

@implementation __NSUnrecognizedTaggedPointer
+(void) load { }
-(id) retain { return self; }
-(oneway void) release { }
-(id) autorelease { return self; }
@end

#endif


@implementation NSObject

+ (void)load {}

+ (void)initialize {}

+ (id)self {
    return (id)self;
}

- (id)self {
    return self;
}

+ (Class)class {
    return self;
}

- (Class)class {
    return object_getClass(self);
}

+ (Class)superclass {
    return self->superclass;
}

- (Class)superclass {
    return [self class]->superclass;
}

+ (BOOL)isMemberOfClass:(Class)cls {
    return object_getClass((id)self) == cls;
}

- (BOOL)isMemberOfClass:(Class)cls {
    return [self class] == cls;
}

+ (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = object_getClass((id)self); tcls; tcls = tcls->superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}

- (BOOL)isKindOfClass:(Class)cls {
    for (Class tcls = [self class]; tcls; tcls = tcls->superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}

+ (BOOL)isSubclassOfClass:(Class)cls {
    for (Class tcls = self; tcls; tcls = tcls->superclass) {
        if (tcls == cls) return YES;
    }
    return NO;
}

+ (BOOL)isAncestorOfObject:(NSObject *)obj {
    for (Class tcls = [obj class]; tcls; tcls = tcls->superclass) {
        if (tcls == self) return YES;
    }
    return NO;
}

+ (BOOL)instancesRespondToSelector:(SEL)sel {
    if (!sel) return NO;
    return class_respondsToSelector(self, sel);
}

+ (BOOL)respondsToSelector:(SEL)sel {
    if (!sel) return NO;
    return class_respondsToSelector_inst(object_getClass(self), sel, self);
}

- (BOOL)respondsToSelector:(SEL)sel {
    if (!sel) return NO;
    return class_respondsToSelector_inst([self class], sel, self);
}

+ (BOOL)conformsToProtocol:(Protocol *)protocol {
    if (!protocol) return NO;
    for (Class tcls = self; tcls; tcls = tcls->superclass) {
        if (class_conformsToProtocol(tcls, protocol)) return YES;
    }
    return NO;
}

- (BOOL)conformsToProtocol:(Protocol *)protocol {
    if (!protocol) return NO;
    for (Class tcls = [self class]; tcls; tcls = tcls->superclass) {
        if (class_conformsToProtocol(tcls, protocol)) return YES;
    }
    return NO;
}

+ (NSUInteger)hash {
    return _objc_rootHash(self);
}

- (NSUInteger)hash {
    return _objc_rootHash(self);
}

+ (BOOL)isEqual:(id)obj {
    return obj == (id)self;
}

- (BOOL)isEqual:(id)obj {
    return obj == self;
}

+ (BOOL)isFault {
    return NO;
}

- (BOOL)isFault {
    return NO;
}

+ (BOOL)isProxy {
    return NO;
}

- (BOOL)isProxy {
    return NO;
}

+ (IMP)instanceMethodForSelector:(SEL)sel {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return class_getMethodImplementation(self, sel);
}

+ (IMP)methodForSelector:(SEL)sel {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return object_getMethodImplementation((id)self, sel);
}

- (IMP)methodForSelector:(SEL)sel {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return object_getMethodImplementation(self, sel);
}

+ (BOOL)resolveClassMethod:(SEL)sel {
    return NO;
}

+ (BOOL)resolveInstanceMethod:(SEL)sel {
    return NO;
}

// Replaced by CF (throws an NSException)
+ (void)doesNotRecognizeSelector:(SEL)sel {
    _objc_fatal("+[%s %s]: unrecognized selector sent to instance %p",
                class_getName(self), sel_getName(sel), self);
}

// Replaced by CF (throws an NSException)
- (void)doesNotRecognizeSelector:(SEL)sel {
    _objc_fatal("-[%s %s]: unrecognized selector sent to instance %p",
                object_getClassName(self), sel_getName(sel), self);
}


+ (id)performSelector:(SEL)sel {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return ((id(*)(id, SEL))objc_msgSend)((id)self, sel);
}

+ (id)performSelector:(SEL)sel withObject:(id)obj {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return ((id(*)(id, SEL, id))objc_msgSend)((id)self, sel, obj);
}

+ (id)performSelector:(SEL)sel withObject:(id)obj1 withObject:(id)obj2 {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return ((id(*)(id, SEL, id, id))objc_msgSend)((id)self, sel, obj1, obj2);
}

- (id)performSelector:(SEL)sel {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return ((id(*)(id, SEL))objc_msgSend)(self, sel);
}

- (id)performSelector:(SEL)sel withObject:(id)obj {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return ((id(*)(id, SEL, id))objc_msgSend)(self, sel, obj);
}

- (id)performSelector:(SEL)sel withObject:(id)obj1 withObject:(id)obj2 {
    if (!sel) [self doesNotRecognizeSelector:sel];
    return ((id(*)(id, SEL, id, id))objc_msgSend)(self, sel, obj1, obj2);
}


// Replaced by CF (returns an NSMethodSignature)
+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)sel {
    _objc_fatal("+[NSObject instanceMethodSignatureForSelector:] "
                "not available without CoreFoundation");
}

// Replaced by CF (returns an NSMethodSignature)
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    _objc_fatal("+[NSObject methodSignatureForSelector:] "
                "not available without CoreFoundation");
}

// Replaced by CF (returns an NSMethodSignature)
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    _objc_fatal("-[NSObject methodSignatureForSelector:] "
                "not available without CoreFoundation");
}

+ (void)forwardInvocation:(NSInvocation *)invocation {
    [self doesNotRecognizeSelector:(invocation ? [invocation selector] : 0)];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [self doesNotRecognizeSelector:(invocation ? [invocation selector] : 0)];
}

+ (id)forwardingTargetForSelector:(SEL)sel {
    return nil;
}

- (id)forwardingTargetForSelector:(SEL)sel {
    return nil;
}


// Replaced by CF (returns an NSString)
+ (NSString *)description {
    return nil;
}

// Replaced by CF (returns an NSString)
- (NSString *)description {
    return nil;
}

+ (NSString *)debugDescription {
    return [self description];
}

- (NSString *)debugDescription {
    return [self description];
}

+ (id)new {
    return [callAlloc(self, false/*checkNil*/) init];
}

+ (id)retain {
    return (id)self;
}

// Replaced by ObjectAlloc
- (id)retain {
    return ((id)self)->rootRetain();
}


+ (BOOL)_tryRetain {
    return YES;
}

// Replaced by ObjectAlloc
- (BOOL)_tryRetain {
    return ((id)self)->rootTryRetain();
}

+ (BOOL)_isDeallocating {
    return NO;
}

- (BOOL)_isDeallocating {
    return ((id)self)->rootIsDeallocating();
}

+ (BOOL)allowsWeakReference {
    return YES;
}

+ (BOOL)retainWeakReference {
    return YES;
}

- (BOOL)allowsWeakReference {
    return ! [self _isDeallocating];
}

- (BOOL)retainWeakReference {
    return [self _tryRetain];
}

+ (oneway void)release{}

// Replaced by ObjectAlloc
- (oneway void)release {
    ((id)self)->rootRelease();
}

+ (id)autorelease {
    return (id)self;
}

// Replaced by ObjectAlloc
- (id)autorelease {
    return ((id)self)->rootAutorelease();
}

+ (NSUInteger)retainCount {
    return ULONG_MAX;
}

/* retainCount 看似有用，实则无用！
 * 因为任何时间点上的绝对保留技术都无法反映对象声明期的全貌
 * 在 ARC 下该方法作废，调用会导致编译器报错
 * @note tagged 指针就无用
 *      while([oject retainCount]){
 *          [oject release];
 *      }
 *  1、如果 oject 在自动释放池，则程序很容易崩溃
 *  2、retainCount可能永不会返回 0
 */
- (NSUInteger)retainCount {
    return ((id)self)->rootRetainCount();
}

+ (id)alloc {
    return _objc_rootAlloc(self);
}

// Replaced by ObjectAlloc
+ (id)allocWithZone:(struct _NSZone *)zone {
    return _objc_rootAllocWithZone(self, (malloc_zone_t *)zone);
}

// Replaced by CF (throws an NSException)
+ (id)init {
    return (id)self;
}

- (id)init {
    return _objc_rootInit(self);
}

// Replaced by CF (throws an NSException)
+ (void)dealloc {}

/** 使用 weak 一个最重要的特性就是在对象释放时,指向对象的所有弱引用都会被自动置为nil,从而有效防止非法访问造成的野指针问题。
 *
 *
 */
// Replaced by NSZombies
- (void)dealloc {
    _objc_rootDealloc(self);
}

// Previously used by GC. Now a placeholder for binary compatibility.
- (void) finalize {
}

+ (struct _NSZone *)zone {
    return (struct _NSZone *)_objc_rootZone(self);
}

- (struct _NSZone *)zone {
    return (struct _NSZone *)_objc_rootZone(self);
}

+ (id)copy {
    return (id)self;
}

+ (id)copyWithZone:(struct _NSZone *)zone {
    return (id)self;
}

- (id)copy {
    return [(id)self copyWithZone:nil];
}

+ (id)mutableCopy {
    return (id)self;
}

+ (id)mutableCopyWithZone:(struct _NSZone *)zone {
    return (id)self;
}

- (id)mutableCopy {
    return [(id)self mutableCopyWithZone:nil];
}

@end
