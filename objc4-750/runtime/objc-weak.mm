#include "objc-private.h"
#include "objc-weak.h"
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
#include <libkern/OSAtomic.h>

#define TABLE_SIZE(entry) (entry->mask ? entry->mask + 1 : 0)

static void append_referrer(weak_entry_t *entry, objc_object **new_referrer);

BREAKPOINT_FUNCTION(
    void objc_weak_error(void)
);

static void bad_weak_table(weak_entry_t *entries){
    _objc_fatal("bad weak table at %p. This may be a runtime bug or a "
                "memory error somewhere else.", entries);
}

/**  唯一的哈希函数对象指针。
 * Unique hash function for object pointers only.
 * 
 * @param key The object pointer
 * 
 * @return 大小不受限制的哈希指针
 */
static inline uintptr_t hash_pointer(objc_object *key) {
    return ptr_hash((uintptr_t)key);
}

/**  唯一的哈希函数弱对象指针。
 * @return 大小不受限制的哈希指针。
 */
static inline uintptr_t w_hash_pointer(objc_object **key) {
    return ptr_hash((uintptr_t)key);
}

/** 扩容并增加新的弱引用指针,最终的存储还是依靠append_referrer() 函数完成
 */
__attribute__((noinline, used)) static void grow_refs_and_insert(weak_entry_t *entry,objc_object **new_referrer){
    assert(entry->out_of_line());
    size_t old_size = TABLE_SIZE(entry);//获取当前的entry容量
    size_t new_size = old_size ? old_size * 2 : 8;//如果当前容量为0则置 new_size = 8;否则new_size=2*old_size;
    
    size_t num_refs = entry->num_refs;
    weak_referrer_t *old_refs = entry->referrers;
    entry->mask = new_size - 1;//重置entry->mask
    
    entry->referrers = (weak_referrer_t *)calloc(TABLE_SIZE(entry), sizeof(weak_referrer_t));//开辟新的空间指针进行扩容
    entry->num_refs = 0;
    entry->max_hash_displacement = 0;
    
    for (size_t i = 0; i < old_size && num_refs > 0; i++) {
        if (old_refs[i] != nil) {
            append_referrer(entry, old_refs[i]);
            num_refs--;
        }
    }
    // Insert
    append_referrer(entry, new_referrer);
    if (old_refs) free(old_refs);//释放旧指针空间
}

/**  在 weak_entry_t 中添加新的弱引用指针
 * 1、当前没有使用离线存储，将 new_referrer 保存至数组 inline_referrers的空余位置；
 *    如果没有空余位置，将数组 new_referrer 的元素拷至数组 referrers ，并设置为离线存储；
 * 2、如果数组 new_referrer 当前已经使用了总量的3/4 ，则需要扩充容量，并将指针 new_referrer 存储至 weak_entry_t
 * 3、如果数组 new_referrer 当前还未超出总量的3/4 ，则直接将指针 new_referrer 存储至 weak_entry_t
 * @param entry 存储指定对象的所有弱指针。
 * @param new_referrer 要添加的新弱指针。
 */
static void append_referrer(weak_entry_t *entry, objc_object **new_referrer){
    //在增加新的弱引用指针之前使用非离线存储弱引用指针：使用静态数组inline_referrers来进行存储
    if (!entry->out_of_line()) {
        for (size_t i = 0; i < WEAK_INLINE_COUNT; i++) {//遍历数组inline_referrers，是否存在空位置
            if (entry->inline_referrers[i] == nil) {//将新的弱引用指针存储在该数组空位置上,并返回
                entry->inline_referrers[i] = new_referrer;
                return;
            }
        }
        
        // 在静态数组中没有可用的存储位置，需要开辟离线空间
        weak_referrer_t *new_referrers = (weak_referrer_t *)calloc(WEAK_INLINE_COUNT, sizeof(weak_referrer_t));
        
        //将之前inline_referrers数组的元素复制到数组 new_referrers 中
        for (size_t i = 0; i < WEAK_INLINE_COUNT; i++) {
            new_referrers[i] = entry->inline_referrers[i];
        }
        entry->referrers = new_referrers;
        entry->num_refs = WEAK_INLINE_COUNT;
        entry->out_of_line_ness = REFERRERS_OUT_OF_LINE;
        entry->mask = WEAK_INLINE_COUNT-1;
        entry->max_hash_displacement = 0;
    }
    assert(entry->out_of_line());//断言：代码执行到这个位置时 entry 应该是离线存储
    
    if (entry->num_refs >= TABLE_SIZE(entry) * 3/4) {//如果当前已经使用了总量的3/4,则扩容并添加新的引用,并返回
        return grow_refs_and_insert(entry, new_referrer);
    }
    
    //如果当前已经使用量小于总量的3/4,则直接添加
    size_t begin = w_hash_pointer(new_referrer) & (entry->mask);
    size_t index = begin;
    size_t hash_displacement = 0;
    while (entry->referrers[index] != nil) {//发生hash碰撞
        hash_displacement++;
        index = (index+1) & entry->mask;
        if (index == begin) bad_weak_table(entry);
    }
    //更新存储时最大的hash碰撞次数,由于优化取值时算法减少搜索次数
    if (hash_displacement > entry->max_hash_displacement) {
        entry->max_hash_displacement = hash_displacement;
    }
    weak_referrer_t &ref = entry->referrers[index];
    ref = new_referrer;
    entry->num_refs++;
}

/** 从指定 weak_entry_t 实例中的数组移出某个弱引用指针
 * 1、如果使用非离线存储,则遍历静态数组 inline_referrers,找到 old_referrer 则移出数组，否则继续执行;
 * 2、如果使用离线存储：使用 w_hash_pointer(old_referrer) & (entry->mask)获取起始索引,
 *                  遍历entry->referrers，找到之后置空，并entry->num_refs自减.
 */
static void remove_referrer(weak_entry_t *entry, objc_object **old_referrer){
    //如果 entry 没有使用离线机制存储
    if (!entry->out_of_line()) {
        for (size_t i = 0; i < WEAK_INLINE_COUNT; i++) {
            if (entry->inline_referrers[i] == old_referrer) {
                entry->inline_referrers[i] = nil;//old_referrer 移出数组
                return;
            }
        }
        _objc_inform("Attempted to unregister unknown __weak variable "
                     "at %p. This is probably incorrect use of "
                     "objc_storeWeak() and objc_loadWeak(). "
                     "Break on objc_weak_error to debug.\n", 
                     old_referrer);
        objc_weak_error();
        return;
    }
    
    //如果entry使用离线机制存储:对象弱引用个数大于WEAK_INLINE_COUNT
    size_t begin = w_hash_pointer(old_referrer) & (entry->mask);
    size_t index = begin;
    size_t hash_displacement = 0;
    while (entry->referrers[index] != old_referrer) {
        index = (index+1) & entry->mask;
        if (index == begin) bad_weak_table(entry);
        hash_displacement++;//搜索次数+1
        if (hash_displacement > entry->max_hash_displacement) {
            _objc_inform("Attempted to unregister unknown __weak variable "
                         "at %p. This is probably incorrect use of "
                         "objc_storeWeak() and objc_loadWeak(). "
                         "Break on objc_weak_error to debug.\n", 
                         old_referrer);
            objc_weak_error();
            return;
        }
    }
    entry->referrers[index] = nil;//old_referrer 移出数组
    entry->num_refs--;//弱引用计数-1
}

#pragma mark - 哈希表的 扩增 与 缩减

/** 将 new_entry 添加到弱引用表中
 * @note 不会检查引用是否已经在表中
 */
static void weak_entry_insert(weak_table_t *weak_table, weak_entry_t *new_entry){
    weak_entry_t *weak_entries = weak_table->weak_entries;
    assert(weak_entries != nil);
    size_t begin = hash_pointer(new_entry->referent) & (weak_table->mask);//获取起始索引
    size_t index = begin;
    size_t hash_displacement = 0;
    while (weak_entries[index].referent != nil) {//循环查找weak_entries中为空的位置
        index = (index+1) & weak_table->mask;
        if (index == begin) bad_weak_table(weak_entries);
        hash_displacement++;
    }
    //在index位置保存new_entry并num_entries进行自增;
    weak_entries[index] = *new_entry;
    weak_table->num_entries++;
    
    //保存哈希碰撞最大的尝试次数,在查找时可以减少搜索次数.
    if (hash_displacement > weak_table->max_hash_displacement) {
        weak_table->max_hash_displacement = hash_displacement;
    }
}

/* 调整弱引用表中的大小
 * @param new_size 新的大小
 */
static void weak_resize(weak_table_t *weak_table, size_t new_size){
    size_t old_size = TABLE_SIZE(weak_table);
    weak_entry_t *old_entries = weak_table->weak_entries;
    weak_entry_t *new_entries = (weak_entry_t *)calloc(new_size, sizeof(weak_entry_t));//申请相应大小的内存
    weak_table->mask = new_size - 1;//记录weak_table实际占用的内存边界
    weak_table->weak_entries = new_entries;
    
    /* 哈希表可能会有 hash 碰撞，而 weak_table_t 使用了开放寻址法来处理碰撞。
     * 如果发生碰撞的话，将寻找相邻(如果已经到最尾端的话，则从头开始)的下一个空位。
     * max_hash_displacement 记录当前 weak_table 最大的偏移值，即hash函数计算的位置和实际存储位置的最大偏差。
     */
    weak_table->max_hash_displacement = 0;
    weak_table->num_entries = 0;// restored by weak_entry_insert below
    if (old_entries) {
        weak_entry_t *entry;
        weak_entry_t *end = old_entries + old_size;
        for (entry = old_entries; entry < end; entry++) {
            if (entry->referent) {
                weak_entry_insert(weak_table, entry);
            }
        }
        free(old_entries);
    }
}

/** 当 weak_table_t 过满时，及时调整其大小，以优化内存的使用率，提高运行效率
 * 该函数的目的是扩充 HashTable 的空间，扩充的条件是Table 3/4及以上的空间已经被使用。
 * 可以看出 HashTable 的初始化大小是 64 个 weak_entry_t 的空间，每次扩充后的空间都是当前空间的两倍，即2的N次方(N>=6)
 */
static void weak_grow_maybe(weak_table_t *weak_table){
    size_t old_size = TABLE_SIZE(weak_table);
    if (weak_table->num_entries >= old_size * 3 / 4) {
        weak_resize(weak_table, old_size ? old_size*2 : 64);
    }
}

/** 当 weak_table_t 过空时，及时调整其大小，以优化内存的使用率，提高运行效率
* 该函数的目的是缩小 HashTable 的空间，缩小的条件是 weak_table 目前的大小不小于1024个weak_entry_t的空间，并且低于1/16的空间被占用
* 缩小后的空间是当前空间的1/8。
*/
static void weak_compact_maybe(weak_table_t *weak_table){
    size_t old_size = TABLE_SIZE(weak_table);
    // Shrink if larger than 1024 buckets and at most 1/16 full.
    if (old_size >= 1024  && old_size / 16 >= weak_table->num_entries) {
        weak_resize(weak_table, old_size / 8);
        // leaves new table no more than 1/2 full
    }
}

#pragma mark - 哈希表的 插入、删除、查询

/** 从弱引用表移除弱引用 weak_entry_t
 */
static void weak_entry_remove(weak_table_t *weak_table, weak_entry_t *entry){
    // remove entry
    if (entry->out_of_line()) free(entry->referrers);
    bzero(entry, sizeof(*entry));
    weak_table->num_entries--;
    weak_compact_maybe(weak_table);
}

/** 在弱引用表查询指定对象的 weak_entry_t
 * @param referent 指定对象，不能为 nil
 * @return 如果弱引用表没有该对象的 weak_entry_t ，则返回 NULL
 */
static weak_entry_t *weak_entry_for_referent(weak_table_t *weak_table, objc_object *referent){
    assert(referent);
    weak_entry_t *weak_entries = weak_table->weak_entries;
    if (!weak_entries) return nil;
    size_t begin = hash_pointer(referent) & weak_table->mask;
    size_t index = begin;
    size_t hash_displacement = 0;
    while (weak_table->weak_entries[index].referent != referent) {
        index = (index+1) & weak_table->mask;
        if (index == begin) bad_weak_table(weak_table->weak_entries);
        hash_displacement++;
        if (hash_displacement > weak_table->max_hash_displacement) {
            return nil;
        }
    }
    return &weak_table->weak_entries[index];
}

#pragma mark - public func

/**
 * This is used when referrer's storage is about to go away, but referent isn't dead yet. (Otherwise, zeroing referrer later would be a bad memory access.)
 *
 * Does nothing if referent/referrer is not a currently active weak reference.
 * Does not zero referrer.
 * 
 * FIXME currently requires old referent value to be passed in (lame)
 * FIXME unregistration should be automatic if referrer is collected
 *
 */
/** 移除指定的弱引用指针：
 * 该函数主要由三个功能：
 *    1、在 weak_table 中查找对应的 weak_entry_t；
 *    2、从 weak_entry_t 的数组中移除referrer指针；
 *    3、判断 weak_entry_t 的数组是否为空，若不再存储弱引用指针,则从弱引用表中移除 weak_entry_t；
 *
 * @param weak_table 全局弱引用表
 * @param referent 指定的对象
 * @param *referrer 带移除的弱引用指针
 */
void weak_unregister_no_lock(weak_table_t *weak_table, id referent_id,id *referrer_id){
    objc_object *referent = (objc_object *)referent_id;
    objc_object **referrer = (objc_object **)referrer_id;
    weak_entry_t *entry;
    if (!referent) return;

    //在弱引用表查询指定对象的 weak_entry_t
    if ((entry = weak_entry_for_referent(weak_table, referent))) {
        remove_referrer(entry, referrer);//从表中移出该指针
        
        bool empty = true;//判断移除指针之后entry数组是否为空
        if (entry->out_of_line()  &&  entry->num_refs != 0) {
            empty = false;
        }else {
            for (size_t i = 0; i < WEAK_INLINE_COUNT; i++) {
                if (entry->inline_referrers[i]) {
                    empty = false; 
                    break;
                }
            }
        }
        if (empty) {//如果移出指针之后entry数组为空，则从弱引用表中移除entry
            weak_entry_remove(weak_table, entry);
        }
    }

    // Do not set *referrer = nil. objc_storeWeak() requires that the 
    // value not change.
}

/** 向弱引用表里添加新的弱应用指针
 * 1、如果被引用对象正在释放，则不能再添加弱应用指针
 * 2、在弱引用表查询指定对象的 weak_entry_t
 *    2.1、如果查到 weak_entry_t ，则将弱引用指针存储至 weak_entry_t
 *    2.2、如果没有查到 weak_entry_t，新建一个 weak_entry_t 并存储弱指针，将 weak_entry_t 存储在弱引用表
 * @param referent 被引用对象，不能为空、不能是TaggedPointer
 * @note 在 -dealloc 方法中,不能增加新的弱引用指针,否则会报错.
 */
id  weak_register_no_lock(weak_table_t *weak_table, id referent_id, id *referrer_id, bool crashIfDeallocating){
    objc_object *referent = (objc_object *)referent_id;//获取被引用对象
    objc_object **referrer = (objc_object **)referrer_id;//强转referrer_id为二级指针
    if (!referent||referent->isTaggedPointer()) return referent_id;
    
    bool deallocating;//确保被引用对象是可行的
    if (!referent->ISA()->hasCustomRR()) {
        deallocating = referent->rootIsDeallocating();
    }else {
        BOOL (*allowsWeakReference)(objc_object *, SEL) = (BOOL(*)(objc_object *, SEL))
            object_getMethodImplementation((id)referent, SEL_allowsWeakReference);
        if ((IMP)allowsWeakReference == _objc_msgForward) {
            return nil;
        }
        deallocating = !(*allowsWeakReference)(referent, SEL_allowsWeakReference);
    }
    if (deallocating) {//如果对象正在释放,不能增加新的弱引用指针
        if (crashIfDeallocating) {
            _objc_fatal("Cannot form weak reference to instance (%p) of "
                        "class %s. It is possible that this object was "
                        "over-released, or is in the process of deallocation.",
                        (void*)referent, object_getClassName((id)referent));
        } else {
            return nil;
        }
    }
    
    weak_entry_t *entry;
    if ((entry = weak_entry_for_referent(weak_table, referent))) {//在弱引用表查询指定对象的 weak_entry_t
        append_referrer(entry, referrer);//把弱引用指针 referrer 加入到对象 referent 已经存在的引用列表中
    } else {//在weak_table中未找到referent对应的weak_entry_t
        weak_entry_t new_entry(referent, referrer);//给对象referent创建一个新的引用列表
        weak_grow_maybe(weak_table);// weak_table 增加内存
        weak_entry_insert(weak_table, &new_entry);//把referent的引用列表加入到weak_table中
    }
    // Do not set *referrer.
    // objc_storeWeak() requires that the value not change.
    return referent_id;
}


#if DEBUG
bool weak_is_registered_no_lock(weak_table_t *weak_table, id referent_id){
    return weak_entry_for_referent(weak_table, (objc_object *)referent_id);
}
#endif


/** 从弱引用表 清空某个对象的所有的 weak指针
 * 当对象被销毁的时候调用 -dealloc 方法，在这个方法里面把所有指向这个对象的弱引用指针全部置为 nil，最后从弱引用表中移除该对象和它的弱引用列表。
 * @param referent 正在调用 -dealloc 方法 的对象
 */
void  weak_clear_no_lock(weak_table_t *weak_table, id referent_id){
    objc_object *referent = (objc_object *)referent_id;

    weak_entry_t *entry = weak_entry_for_referent(weak_table, referent);
    if (entry == nil) {//若entry为空则证明当前对象不存在弱引用指针.
        /// XXX shouldn't happen, but does with mismatched CF/objc
        //printf("XXX no entry for clear deallocating %p\n", referent);
        return;
    }

    // zero out references
    weak_referrer_t *referrers;
    size_t count;
    
    if (entry->out_of_line()) {//使用离线存储弱引用指针
        referrers = entry->referrers;
        count = TABLE_SIZE(entry);
    } else { //使用内部静态数组存储弱引用指针
        referrers = entry->inline_referrers;
        count = WEAK_INLINE_COUNT;
    }
    
    //遍历弱引用数组逐个置空指向referent的弱引用指针
    for (size_t i = 0; i < count; ++i) {
        objc_object **referrer = referrers[i];
        if (referrer) {
            if (*referrer == referent) {//当前弱指针指向对象referent
                *referrer = nil;//置空弱引用指针
            }else if (*referrer) {
                _objc_inform("__weak variable at %p holds %p instead of %p. "
                             "This is probably incorrect use of "
                             "objc_storeWeak() and objc_loadWeak(). "
                             "Break on objc_weak_error to debug.\n", 
                             referrer, (void*)*referrer, (void*)referent);
                objc_weak_error();
            }
        }
    }
    //从weak_table中移除entry
    weak_entry_remove(weak_table, entry);
}

//https://blog.csdn.net/WangErice/article/details/104950156
