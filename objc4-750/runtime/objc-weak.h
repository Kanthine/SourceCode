#ifndef _OBJC_WEAK_H_
#define _OBJC_WEAK_H_

#include <objc/objc.h>
#include "objc-config.h"

__BEGIN_DECLS
 

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
 * @param referent 被弱引用指针指向的对象，
 * @note 该结构使用两种存储方案存储弱引用指针：
 *       case_1：弱引用指针数量 < 4 : 使用静态数组 inline_referrers 进行保存,同时 out_of_line_ness = 0;
 *       case_2：弱引用指针数量 > 4 : 使用二维数组 referrers 保存, out_of_line_ness = 2;
 **/
struct weak_entry_t {
    DisguisedPtr<objc_object> referent;
    union {
        struct {//当弱引用指针个数大于 WEAK_INLINE_COUNT 时,使用二维指针数组进行存储
            weak_referrer_t *referrers;
            uintptr_t        out_of_line_ness : 2;
            uintptr_t        num_refs : PTR_MINUS_2;
            uintptr_t        mask;
            uintptr_t        max_hash_displacement;
        };
        struct {//当弱引用指针个数小于 WEAK_INLINE_COUNT 时,使用一维数组进行存储
            weak_referrer_t  inline_referrers[WEAK_INLINE_COUNT];
        };
    };
    bool out_of_line() {//判断当前是否是离线存储
        return (out_of_line_ness == REFERRERS_OUT_OF_LINE);
    }
    weak_entry_t& operator=(const weak_entry_t& other) {//重载运算符=
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

/** 全局的弱引用表是一个由自旋锁控制的哈希表 : 程序中所有的弱引用都在该表中进行存储；
 *  该表以键值对的形式存储，对象作为 key，value 是结构 weak_entry_t
 * @param weak_entry_t 该结构体中保存着所有指向某个对象的弱引用指针
 */
struct weak_table_t {
    weak_entry_t *weak_entries;//保存了所有指向指定对象的weak指针
    size_t    num_entries;// weak对象的存储空间大小
    uintptr_t mask;//参与判断引用计数辅助量
    uintptr_t max_hash_displacement;//最大偏移值:hash冲撞时最大尝试次数，用于优化搜索算法
};

/* 向弱引用表里添加一对 (object, weak pointer)
 * @param weak_table 弱引用表
 * @param referent 添加的对象
 * @param *referrer 弱引用指针
 * @param crashIfDeallocating
 */
id weak_register_no_lock(weak_table_t *weak_table, id referent, id *referrer, bool crashIfDeallocating);

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

/*

 
 

 
1、弱引用表 weak_table_t

####1.1、初始化一个弱引用变量

####1.2、弱引用指针指向它处

 
 
 */
