#ifndef _OBJC_WEAK_H_
#define _OBJC_WEAK_H_

#include <objc/objc.h>
#include "objc-config.h"

__BEGIN_DECLS
 
/* 弱引用表是一个由自旋锁控制的哈希表
一个被分配的内存块，通常是一个对象，但是在GC下，任何这样的分配，都可能通过编译器生成的写屏障或寄存器弱原语的手工编码使用，将其地址存储在一个有剩余弱标记的存储位置。
与注册相关的可以是一个回调块，用于回收分配的内存块之一的情况。
表是根据分配内存的地址进行散列的。
当带有弱标记的内存改变它的引用时，我们仍然可以看到它以前的引用。
因此，在由弱引用项索引的哈希表中，是当前存储此地址的所有位置的列表。
对于ARC，我们还可以通过在调用dealloc之前简单地将它放在表中，并在内存回收之前通过objc_clear_deallocate删除它来跟踪任意对象是否正在被释放。

通过使用编译器生成的写屏障或寄存器弱原语的手工编码用法，可以分配已分配的内存块（通常是对象），但在GC中进行任何此类分配，都可以将其地址存储在__weak标记的存储位置中。
在回收分配的内存块之一的情况下，与注册关联的可能是回调块。
该表将在分配的内存地址上进行哈希处理。
当__weak标记的内存更改其引用时，我们依靠这样的事实，即仍然可以看到其先前的引用。
因此，在哈希表中（由弱引用项索引）是当前存储该地址的所有位置的列表。
对于ARC，我们还通过在调用dealloc之前将其短暂放置在表中，然后在回收内存之前通过objc_clear_deallocing将其删除，来跟踪是否正在释放任意对象。
 
An allocated blob of memory, most often an object, but under GC any such allocation, may have its address stored in a __weak marked storage location through use of compiler generated write-barriers or hand coded uses of the register weak primitive.
Associated with the registration can be a callback block for the case when one of the allocated chunks of memory is reclaimed.
The table is hashed on the address of the allocated memory.
When __weak marked memory changes its reference, we count on the fact that we can still see its previous reference.
So, in the hash table, indexed by the weakly referenced item, is a list of all locations where this address is currently being stored.
For ARC, we also keep track of whether an arbitrary object is being deallocated by briefly placing it in the table just prior to invoking dealloc, and removing it via objc_clear_deallocating just prior to memory reclamation.
*/


/** 一个弱变量的地址。
 * 这些指针被伪装起来存储，因此内存分析工具不会看到从弱引用表到对象的大量内部指针。
 */
typedef DisguisedPtr<objc_object *> weak_referrer_t;

#if __LP64__
#define PTR_MINUS_2 62
#else
#define PTR_MINUS_2 30
#endif

/** 存储在弱引用表中的内部结构。
 * 它维护和存储一个指向对象的弱引用散列集。
 * The internal structure stored in the weak references table. 
 * It maintains and stores  a hash set of weak references pointing to an object.
 *
 * If out_of_line_ness != REFERRERS_OUT_OF_LINE then the set is instead a small inline array.
 *
 */
#define WEAK_INLINE_COUNT 4

// out_of_line_ness field overlaps with the low two bits of inline_referrers[1].
// inline_referrers[1] is a DisguisedPtr of a pointer-aligned address.
// The low two bits of a pointer-aligned DisguisedPtr will always be 0b00
// (disguised nil or 0x80..00) or 0b11 (any other address).
// Therefore out_of_line_ness == 0b10 is used to mark the out-of-line state.
#define REFERRERS_OUT_OF_LINE 2

/** 用来存储具体某一对象的所有弱引用指针
 * 当对象弱引用指针小于4个时,使用静态数组 inline_referrers 进行保存,同时 out_of_line_ness = 0;
 * 当对象弱引用指针大于4个时,使用二维数组 referrers 保存 , out_of_line_ness = 2;
 **/
struct weak_entry_t {
    DisguisedPtr<objc_object> referent;
    union {
        //当弱引用指针个数大于 WEAK_INLINE_COUNT 时,使用二维指针数组进行存储
        struct {
            weak_referrer_t *referrers;
            uintptr_t        out_of_line_ness : 2;
            uintptr_t        num_refs : PTR_MINUS_2;
            uintptr_t        mask;
            uintptr_t        max_hash_displacement;
        };
        
        //当弱引用指针个数小于 WEAK_INLINE_COUNT 时,使用一维数组进行存储
        struct {
            // out_of_line_ness field is low bits of inline_referrers[1]
            weak_referrer_t  inline_referrers[WEAK_INLINE_COUNT];
        };
    };

    bool out_of_line() {//判断当前是否是离线存储
        return (out_of_line_ness == REFERRERS_OUT_OF_LINE);
    }

    //重载运算符=
    weak_entry_t& operator=(const weak_entry_t& other) {
        memcpy(this, &other, sizeof(other));
        return *this;
    }

    //第一个弱引用指针使用该方法存储
    weak_entry_t(objc_object *newReferent, objc_object **newReferrer) : referent(newReferent){
        inline_referrers[0] = newReferrer;
        for (int i = 1; i < WEAK_INLINE_COUNT; i++) {
            inline_referrers[i] = nil;
        }
    }
};

/**
 * 全局的弱引用表：所有的弱引用都在该表中进行存储
 * 将对象作为key，weak_entry_t 为 value。
 */
struct weak_table_t {
    weak_entry_t *weak_entries;//保存了所有指向指定对象的weak指针
    size_t    num_entries;// weak对象的存储空间大小
    uintptr_t mask;//参与判断引用计数辅助量
    uintptr_t max_hash_displacement;//hash key 最大偏移值 : hash冲撞时最大尝试次数，用于优化搜索算法
};

/* 向弱引用表里添加一对 (object, weak pointer)
 * @param weak_table 弱引用表
 * @param referent 添加的对象
 * @param *referrer 弱引用指针
 * @param crashIfDeallocating
 */
id weak_register_no_lock(weak_table_t *weak_table, id referent, id *referrer, bool crashIfDeallocating);

/** 移除指定的弱引用指针
 * @param weak_table 弱引用表
 * @param referent 移除的对象
 * @param *referrer 弱引用指针
 */
void weak_unregister_no_lock(weak_table_t *weak_table, id referent, id *referrer);

#if DEBUG
/** 判断弱引用表中是否存储该对象
 * @param referent 需要判断的对象
 * @return 如果 referent 有弱引用返回 true
 */
bool weak_is_registered_no_lock(weak_table_t *weak_table, id referent);
#endif

/** 弱引用表中的对象 referent 被销毁，把所有指向它的弱引用指针全部置为 nil
 */
void weak_clear_no_lock(weak_table_t *weak_table, id referent);

__END_DECLS

#endif /* _OBJC_WEAK_H_ */
