/** isa 指针的 64 位上的一些信息
 * @param nonpointer 是否对isa开启指针优化：true代表非指针型ISA，除了地址外，还包含了类的一些信息、对象的引用计数等。
 * @param has_assoc：该位表示是否有关联对象
 * @param has_cxx_dtor：在ARC环境下标记对象是否通过ARC来管理的
 * @param shiftcls：标记当前对象所属类的指针地址
 * @param magic：判断当前对象是真的对象还是一段没有初始化的空间
 * @param weakly_referenced：是否有弱引用指针指向该对象
 * @param deallocating：对象是否正在进行dealloc操作
 * @param has_sidetable_rc：标记是否有 sitetable 结构用于存储引用计数
 * @param extra_rc：标记对象的引用计数：首先会存储在该字段中，当到达上限后，再存入对应的引用计数表中
 *
 * @note 非指针型ISA：SUPPORT_NONPOINTER_ISA 64位中存储的内容有：引用计数、析构状态，是否有弱引用指针等等
 * @note 一个实例少量的引用计数不会直接存放在 SideTables 中，引用计数存放在extra_rc 中，当其被存满时才会存入相应的SideTables 散列表中
*/

/**
 * 苹果将ISA设计成了联合体，在ISA中存储了与该对象相关的一些内存信息，因为 并不需要64个二进制全部都用来存储指针

 // x86_64 架构
 struct {
     uintptr_t nonpointer        : 1;  // 0:普通指针，1:优化过，使用位域存储更多信息
     uintptr_t has_assoc         : 1;  // 对象是否含有或曾经含有关联引用
     uintptr_t has_cxx_dtor      : 1;  // 表示是否有C++析构函数或OC的dealloc
     uintptr_t shiftcls          : 44; // 存放着 Class、Meta-Class 对象的内存地址信息
     uintptr_t magic             : 6;  // 用于在调试时分辨对象是否未完成初始化
     uintptr_t weakly_referenced : 1;  // 是否被弱引用指向
     uintptr_t deallocating      : 1;  // 对象是否正在释放
     uintptr_t has_sidetable_rc  : 1;  // 是否需要使用 sidetable 来存储引用计数
     uintptr_t extra_rc          : 8;  // 引用计数能够用 8 个二进制位存储时，直接存储在这里
 };

 // arm64 架构
 struct {
     uintptr_t nonpointer        : 1;  // 0:普通指针，1:优化过，使用位域存储更多信息
     uintptr_t has_assoc         : 1;  // 对象是否含有或曾经含有关联引用
     uintptr_t has_cxx_dtor      : 1;  // 表示是否有C++析构函数或OC的dealloc
     uintptr_t shiftcls          : 33; // 存放着 Class、Meta-Class 对象的内存地址信息
     uintptr_t magic             : 6;  // 用于在调试时分辨对象是否未完成初始化
     uintptr_t weakly_referenced : 1;  // 是否被弱引用指向
     uintptr_t deallocating      : 1;  // 对象是否正在释放
     uintptr_t has_sidetable_rc  : 1;  // 是否需要使用 sidetable 来存储引用计数
     uintptr_t extra_rc          : 19;  // 引用计数能够用 19 个二进制位存储时，直接存储在这里
 };
 */


#ifndef _OBJC_ISA_H_
#define _OBJC_ISA_H_

#include "objc-config.h"


#if (!SUPPORT_NONPOINTER_ISA && !SUPPORT_PACKED_ISA && !SUPPORT_INDEXED_ISA) ||\
    ( SUPPORT_NONPOINTER_ISA &&  SUPPORT_PACKED_ISA && !SUPPORT_INDEXED_ISA) ||\
    ( SUPPORT_NONPOINTER_ISA && !SUPPORT_PACKED_ISA &&  SUPPORT_INDEXED_ISA)
    // good config
#else
#   error bad config
#endif


#if SUPPORT_PACKED_ISA

# if __arm64__
#   define ISA_MASK        0x0000000ffffffff8ULL
#   define ISA_MAGIC_MASK  0x000003f000000001ULL
#   define ISA_MAGIC_VALUE 0x000001a000000001ULL
#   define ISA_BITFIELD                                                      \
      uintptr_t nonpointer        : 1;                                       \
      uintptr_t has_assoc         : 1;                                       \
      uintptr_t has_cxx_dtor      : 1;                                       \
      uintptr_t shiftcls          : 33; /*MACH_VM_MAX_ADDRESS 0x1000000000*/ \
      uintptr_t magic             : 6;                                       \
      uintptr_t weakly_referenced : 1;                                       \
      uintptr_t deallocating      : 1;                                       \
      uintptr_t has_sidetable_rc  : 1;                                       \
      uintptr_t extra_rc          : 19
#   define RC_ONE   (1ULL<<45)
#   define RC_HALF  (1ULL<<18)

# elif __x86_64__
#   define ISA_MASK        0x00007ffffffffff8ULL
#   define ISA_MAGIC_MASK  0x001f800000000001ULL
#   define ISA_MAGIC_VALUE 0x001d800000000001ULL
#   define ISA_BITFIELD                                                        \
      uintptr_t nonpointer        : 1;                                         \
      uintptr_t has_assoc         : 1;                                         \
      uintptr_t has_cxx_dtor      : 1;                                         \
      uintptr_t shiftcls          : 44; /*MACH_VM_MAX_ADDRESS 0x7fffffe00000*/ \
      uintptr_t magic             : 6;                                         \
      uintptr_t weakly_referenced : 1;                                         \
      uintptr_t deallocating      : 1;                                         \
      uintptr_t has_sidetable_rc  : 1;                                         \
      uintptr_t extra_rc          : 8
#   define RC_ONE   (1ULL<<56)
#   define RC_HALF  (1ULL<<7)

# else
#   error unknown architecture for packed isa
# endif

// SUPPORT_PACKED_ISA
#endif


#if SUPPORT_INDEXED_ISA

# if  __ARM_ARCH_7K__ >= 2  ||  (__arm64__ && !__LP64__)
    // armv7k or arm64_32

#   define ISA_INDEX_IS_NPI_BIT  0
#   define ISA_INDEX_IS_NPI_MASK 0x00000001
#   define ISA_INDEX_MASK        0x0001FFFC
#   define ISA_INDEX_SHIFT       2
#   define ISA_INDEX_BITS        15
#   define ISA_INDEX_COUNT       (1 << ISA_INDEX_BITS)
#   define ISA_INDEX_MAGIC_MASK  0x001E0001
#   define ISA_INDEX_MAGIC_VALUE 0x001C0001
#   define ISA_BITFIELD                         \
      uintptr_t nonpointer        : 1;          \
      uintptr_t has_assoc         : 1;          \
      uintptr_t indexcls          : 15;         \
      uintptr_t magic             : 4;          \
      uintptr_t has_cxx_dtor      : 1;          \
      uintptr_t weakly_referenced : 1;          \
      uintptr_t deallocating      : 1;          \
      uintptr_t has_sidetable_rc  : 1;          \
      uintptr_t extra_rc          : 7
#   define RC_ONE   (1ULL<<25)
#   define RC_HALF  (1ULL<<6)

# else
#   error unknown architecture for indexed isa
# endif

// SUPPORT_INDEXED_ISA
#endif


// _OBJC_ISA_H_
#endif
