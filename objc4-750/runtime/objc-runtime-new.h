/*
 * Copyright (c) 2005-2007 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_RUNTIME_NEW_H
#define _OBJC_RUNTIME_NEW_H

#if __LP64__
typedef uint32_t mask_t;  //16位的x86_64和arm64 的 asm效率较低
#else
typedef uint16_t mask_t;
#endif
typedef uintptr_t cache_key_t;

struct swift_class_t;


struct bucket_t {
private:
    // IMP-first is better for arm64e ptrauth and no worse for arm64.
    // SEL-first is better for armv7* and i386 and x86_64.
#if __arm64__
    MethodCacheIMP _imp;
    cache_key_t _key;
#else
    cache_key_t _key;
    MethodCacheIMP _imp;
#endif
    
public:
    inline cache_key_t key() const { return _key; }
    inline IMP imp() const { return (IMP)_imp; }
    inline void setKey(cache_key_t newKey) { _key = newKey; }
    inline void setImp(IMP newImp) { _imp = newImp; }
    
    void set(cache_key_t newKey, IMP newImp);
};


struct cache_t {
    struct bucket_t *_buckets;
    mask_t _mask;
    mask_t _occupied;
    
public:
    struct bucket_t *buckets();
    mask_t mask();
    mask_t occupied();
    void incrementOccupied();
    void setBucketsAndMask(struct bucket_t *newBuckets, mask_t newMask);
    void initializeToEmpty();
    
    mask_t capacity();
    bool isConstantEmptyCache();
    bool canBeFreed();
    
    static size_t bytesForCapacity(uint32_t cap);
    static struct bucket_t * endMarker(struct bucket_t *b, uint32_t cap);
    
    void expand();
    void reallocate(mask_t oldCapacity, mask_t newCapacity);
    struct bucket_t * find(cache_key_t key, id receiver);
    
    static void bad_cache(id receiver, SEL sel, Class isa) __attribute__((noreturn));
};


// classref_t 是未重新映射的 class_t*
typedef struct classref * classref_t;

/* non-fragile 结构数组的通用实现。
 * @param Element  数组元素是结构类型(例如method_t)
 * @param List 存储单一类型 entsize_list_tt 的数组 (例如method_list_t)
 * @param FlagMask 用于在entsize字段中存储额外的位(例如，方法列表修复标记)
 */
template <typename Element, typename List, uint32_t FlagMask>
struct entsize_list_tt {
    uint32_t entsizeAndFlags;
    uint32_t count;
    Element first;
    
    uint32_t entsize() const {
        return entsizeAndFlags & ~FlagMask;
    }
    uint32_t flags() const {
        return entsizeAndFlags & FlagMask;
    }
    
    Element& getOrEnd(uint32_t i) const {
        assert(i <= count);
        return *(Element *)((uint8_t *)&first + i*entsize());
    }
    Element& get(uint32_t i) const {
        assert(i < count);
        return getOrEnd(i);
    }
    
    size_t byteSize() const {
        return byteSize(entsize(), count);
    }
    
    static size_t byteSize(uint32_t entsize, uint32_t count) {
        return sizeof(entsize_list_tt) + (count-1)*entsize;
    }
    
    List *duplicate() const {
        auto *dup = (List *)calloc(this->byteSize(), 1);
        dup->entsizeAndFlags = this->entsizeAndFlags;
        dup->count = this->count;
        std::copy(begin(), end(), dup->begin());
        return dup;
    }
    
    struct iterator;
    const iterator begin() const {
        return iterator(*static_cast<const List*>(this), 0);
    }
    iterator begin() {
        return iterator(*static_cast<const List*>(this), 0);
    }
    const iterator end() const {
        return iterator(*static_cast<const List*>(this), count);
    }
    iterator end() {
        return iterator(*static_cast<const List*>(this), count);
    }
    
    struct iterator {
        uint32_t entsize;
        uint32_t index;  // keeping track of this saves a divide in operator-
        Element* element;
        
        typedef std::random_access_iterator_tag iterator_category;
        typedef Element value_type;
        typedef ptrdiff_t difference_type;
        typedef Element* pointer;
        typedef Element& reference;
        
        iterator() { }
        
        iterator(const List& list, uint32_t start = 0)
        : entsize(list.entsize())
        , index(start)
        , element(&list.getOrEnd(start))
        { }
        
        const iterator& operator += (ptrdiff_t delta) {
            element = (Element*)((uint8_t *)element + delta*entsize);
            index += (int32_t)delta;
            return *this;
        }
        const iterator& operator -= (ptrdiff_t delta) {
            element = (Element*)((uint8_t *)element - delta*entsize);
            index -= (int32_t)delta;
            return *this;
        }
        const iterator operator + (ptrdiff_t delta) const {
            return iterator(*this) += delta;
        }
        const iterator operator - (ptrdiff_t delta) const {
            return iterator(*this) -= delta;
        }
        
        iterator& operator ++ () { *this += 1; return *this; }
        iterator& operator -- () { *this -= 1; return *this; }
        iterator operator ++ (int) {
            iterator result(*this); *this += 1; return result;
        }
        iterator operator -- (int) {
            iterator result(*this); *this -= 1; return result;
        }
        
        ptrdiff_t operator - (const iterator& rhs) const {
            return (ptrdiff_t)this->index - (ptrdiff_t)rhs.index;
        }
        
        Element& operator * () const { return *element; }
        Element* operator -> () const { return element; }
        
        operator Element& () const { return *element; }
        
        bool operator == (const iterator& rhs) const {
            return this->element == rhs.element;
        }
        bool operator != (const iterator& rhs) const {
            return this->element != rhs.element;
        }
        
        bool operator < (const iterator& rhs) const {
            return this->element < rhs.element;
        }
        bool operator > (const iterator& rhs) const {
            return this->element > rhs.element;
        }
    };
};


struct method_t {
    SEL name;
    const char *types;
    MethodListIMP imp;
    
    struct SortBySELAddress :
    public std::binary_function<const method_t&,
    const method_t&, bool>{
        bool operator() (const method_t& lhs, const method_t& rhs){
            return lhs.name < rhs.name;
        }
    };
};

struct ivar_t {
#if __x86_64__
    /* *offset 最初在某些x86_64平台上是64位的。
     * 我们只读写它的32位。
     * 一些元数据提供所有64位。这对于无符号的little-endian值无影响。
     * 有些代码使用全部 64 位。class_addIvar() 为其利益过度分配了偏移量。
     */
#endif
    int32_t *offset;
    const char *name;
    const char *type;
    // 对齐有时是 -1;使用 alignment()
    uint32_t alignment_raw;
    uint32_t size;
    
    uint32_t alignment() const {
        if (alignment_raw == ~(uint32_t)0) return 1U << WORD_SHIFT;
        return 1 << alignment_raw;
    }
};

struct property_t {
    const char *name;
    const char *attributes;
};

// entsize 的两个位用于固定标记。
struct method_list_t : entsize_list_tt<method_t, method_list_t, 0x3> {
    bool isFixedUp() const;
    void setFixedUp();
    
    uint32_t indexOfMethod(const method_t *meth) const {
        uint32_t i =
        (uint32_t)(((uintptr_t)meth - (uintptr_t)this) / entsize());
        assert(i < count);
        return i;
    }
};

struct ivar_list_t : entsize_list_tt<ivar_t, ivar_list_t, 0> {
    bool containsIvar(Ivar ivar) const {
        return (ivar >= (Ivar)&*begin()  &&  ivar < (Ivar)&*end());
    }
};

struct property_list_t : entsize_list_tt<property_t, property_list_t, 0> {
};

// protocol_t *, 没有重新映射的
typedef uintptr_t protocol_ref_t;
// Values for protocol_t->flags
#define PROTOCOL_FIXED_UP_2 (1<<31)  // 不能由编译器设置
#define PROTOCOL_FIXED_UP_1 (1<<30)  // 不能由编译器设置
// 0..15 位被保留给 Swift 使用.

#define PROTOCOL_FIXED_UP_MASK (PROTOCOL_FIXED_UP_1 | PROTOCOL_FIXED_UP_2)

struct protocol_t : objc_object {
    const char *mangledName;
    struct protocol_list_t *protocols;
    method_list_t *instanceMethods;
    method_list_t *classMethods;
    method_list_t *optionalInstanceMethods;
    method_list_t *optionalClassMethods;
    property_list_t *instanceProperties;
    uint32_t size;   // sizeof(protocol_t)
    uint32_t flags;
    // 以下字段并不总是出现在磁盘上。
    const char **_extendedMethodTypes;
    const char *_demangledName;
    property_list_t *_classProperties;
    
    const char *demangledName();
    
    const char *nameForLogging() {
        return demangledName();
    }
    
    bool isFixedUp() const;
    void setFixedUp();
    
#   define HAS_FIELD(f) (size >= offsetof(protocol_t, f) + sizeof(f))
    
    bool hasExtendedMethodTypesField() const {
        return HAS_FIELD(_extendedMethodTypes);
    }
    bool hasDemangledNameField() const {
        return HAS_FIELD(_demangledName);
    }
    bool hasClassPropertiesField() const {
        return HAS_FIELD(_classProperties);
    }
    
#   undef HAS_FIELD
    
    const char **extendedMethodTypes() const {
        return hasExtendedMethodTypesField() ? _extendedMethodTypes : nil;
    }
    
    property_list_t *classProperties() const {
        return hasClassPropertiesField() ? _classProperties : nil;
    }
};

struct protocol_list_t {
    // count is 64-bit by accident.
    uintptr_t count;
    protocol_ref_t list[0]; // variable-size
    
    size_t byteSize() const {
        return sizeof(*this) + count*sizeof(list[0]);
    }
    
    protocol_list_t *duplicate() const {
        return (protocol_list_t *)memdup(this, this->byteSize());
    }
    
    typedef protocol_ref_t* iterator;
    typedef const protocol_ref_t* const_iterator;
    
    const_iterator begin() const {
        return list;
    }
    iterator begin() {
        return list;
    }
    const_iterator end() const {
        return list + count;
    }
    iterator end() {
        return list + count;
    }
};

struct locstamped_category_t {
    category_t *cat;
    struct header_info *hi;
};

struct locstamped_category_list_t {
    uint32_t count;
#if __LP64__
    uint32_t reserved;
#endif
    locstamped_category_t list[0];
};


#pragma mark - 编译时类的结构标志 class_ro_t->flags
#define RO_META               (1<<0)   // 元类
#define RO_ROOT               (1<<1)   // 根类
#define RO_HAS_CXX_STRUCTORS  (1<<2)  // class 具有 .cxx_construct/destruct 实现
// #define RO_HAS_LOAD_METHOD (1<<3)  // class 已经实现 +load
#define RO_HIDDEN    (1<<4) // class 已经设置 visibility=hidden
#define RO_EXCEPTION (1<<5) // 类具有 attribute(objc_exception): OBJC_EHTYPE_$_ThisClass 是非弱类型
//#define RO_REUSE_ME (1<<6)//该位可用于重新分配
#define RO_IS_ARC (1<<7)// 用ARC编译的类
// 类有 .cxx_destruct，但没有.cxx_construct(带有 RO_HAS_CXX_STRUCTORS)
#define RO_HAS_CXX_DTOR_ONLY  (1<<8)
// 不是ARC编译的类，但具有ARC样式的弱ivar布局
#define RO_HAS_WEAK_WITHOUT_ARC (1<<9)

/*********   不能由编译器设置的几个标记   **********/
// 类位于不可加载的 Bundle 中
#define RO_FROM_BUNDLE        (1<<29)
// 未实现的future class
#define RO_FUTURE             (1<<30)
// 类是可实现的
#define RO_REALIZED           (1<<31)

#pragma mark - Runtime 时类的结构标志 class_rw_t->flags

#define RW_REALIZED     (1<<31) // 已实现
#define RW_FUTURE       (1<<30) // 未解析的 future class
#define RW_INITIALIZED  (1<<29) // 已经完成初始化
#define RW_INITIALIZING (1<<28) // 正在初始化
#define RW_COPIED_RO    (1<<27) // class_rw_t->ro is heap copy of class_ro_t
#define RW_CONSTRUCTING (1<<26) // 已创建但尚未注册的类
#define RW_CONSTRUCTED  (1<<25) // 已创建并且注册的类
// #define RW_24        (1<<24) // available for use; was RW_FINALIZE_ON_MAIN_THREAD
#define RW_LOADED       (1<<23) // 类方法 +load 已经调用

#if !SUPPORT_NONPOINTER_ISA
#define RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS (1<<22)// 类实例可能具有关联引用
#endif

#define RW_HAS_INSTANCE_SPECIFIC_LAYOUT (1 << 21) //类具有特定于实例的GC布局
// #define RW_20       (1<<20) // 可用的
#define RW_REALIZING   (1<<19) // 类正在实现，但尚未完成

// 注:更多的RW_标志定义如下

// Values for class_rw_t->flags or class_t->bits
// 这些标志针对retain/release和alloc/dealloc进行了优化
// 64位将它们更多地存储在 class_t->bits 中，以减少指针的间接指向。

#if !__LP64__

// class or superclass has .cxx_construct implementation
#define RW_HAS_CXX_CTOR       (1<<18)
// class or superclass has .cxx_destruct implementation
#define RW_HAS_CXX_DTOR       (1<<17)
// 类或父类实现默认的alloc/allocWithZone:方法；注意这是存储在元类中的。
#define RW_HAS_DEFAULT_AWZ    (1<<16)
// class's instances requires raw isa
#if SUPPORT_NONPOINTER_ISA
#define RW_REQUIRES_RAW_ISA   (1<<15)
#endif
// class or superclass has default retain/release/autorelease/retainCount/
//   _tryRetain/_isDeallocating/retainWeakReference/allowsWeakReference
#define RW_HAS_DEFAULT_RR     (1<<14)

// class is a Swift class from the pre-stable Swift ABI
#define FAST_IS_SWIFT_LEGACY  (1UL<<0)
// class is a Swift class from the stable Swift ABI
#define FAST_IS_SWIFT_STABLE  (1UL<<1)
// data pointer
#define FAST_DATA_MASK        0xfffffffcUL

#elif 1
// Leaks-compatible version that steals low bits only.

// class or superclass has .cxx_construct implementation
#define RW_HAS_CXX_CTOR       (1<<18)
// class or superclass has .cxx_destruct implementation
#define RW_HAS_CXX_DTOR       (1<<17)
// class or superclass has default alloc/allocWithZone: implementation
// Note this is is stored in the metaclass.
#define RW_HAS_DEFAULT_AWZ    (1<<16)
// class's instances requires raw isa
#define RW_REQUIRES_RAW_ISA   (1<<15)

// class is a Swift class from the pre-stable Swift ABI
#define FAST_IS_SWIFT_LEGACY    (1UL<<0)
// class is a Swift class from the stable Swift ABI
#define FAST_IS_SWIFT_STABLE    (1UL<<1)
// 类或者父类拥有默认的 retain/release/autorelease/retainCount/
//   _tryRetain/_isDeallocating/retainWeakReference/allowsWeakReference 等方法
#define FAST_HAS_DEFAULT_RR     (1UL<<2)
// 数据指针
#define FAST_DATA_MASK          0x00007ffffffffff8UL

#else
// Leaks-incompatible version that steals lots of bits.

// class is a Swift class from the pre-stable Swift ABI
#define FAST_IS_SWIFT_LEGACY    (1UL<<0)
// class is a Swift class from the stable Swift ABI
#define FAST_IS_SWIFT_STABLE    (1UL<<1)
// summary bit for fast alloc path: !hasCxxCtor and
//   !instancesRequireRawIsa and instanceSize fits into shiftedSize
#define FAST_ALLOC              (1UL<<2)
// data pointer
#define FAST_DATA_MASK          0x00007ffffffffff8UL
// class or superclass has .cxx_construct implementation
#define FAST_HAS_CXX_CTOR       (1UL<<47)
// class or superclass has default alloc/allocWithZone: implementation
// Note this is is stored in the metaclass.
#define FAST_HAS_DEFAULT_AWZ    (1UL<<48)
// class or superclass has default retain/release/autorelease/retainCount/
//   _tryRetain/_isDeallocating/retainWeakReference/allowsWeakReference
#define FAST_HAS_DEFAULT_RR     (1UL<<49)
// class's instances requires raw isa
//   This bit is aligned with isa_t->hasCxxDtor to save an instruction.
#define FAST_REQUIRES_RAW_ISA   (1UL<<50)
// class or superclass has .cxx_destruct implementation
#define FAST_HAS_CXX_DTOR       (1UL<<51)
// instance size in units of 16 bytes
//   or 0 if the instance size is too big in this field
//   This field must be LAST
#define FAST_SHIFTED_SIZE_SHIFT 52

// FAST_ALLOC means
//   FAST_HAS_CXX_CTOR is set
//   FAST_REQUIRES_RAW_ISA is not set
//   FAST_SHIFTED_SIZE is not zero
// FAST_ALLOC does NOT check FAST_HAS_DEFAULT_AWZ because that
// bit is stored on the metaclass.
#define FAST_ALLOC_MASK  (FAST_HAS_CXX_CTOR | FAST_REQUIRES_RAW_ISA)
#define FAST_ALLOC_VALUE (0)

#endif

// The Swift ABI requires that these bits be defined like this on all platforms.
static_assert(FAST_IS_SWIFT_LEGACY == 1, "resistance is futile");
static_assert(FAST_IS_SWIFT_STABLE == 2, "resistance is futile");

//class_ro_t 存储了该类在编译时就已经确定的属性、方法以及遵循的协议
struct class_ro_t {
    uint32_t flags;//标志
    uint32_t instanceStart;
    uint32_t instanceSize;
#ifdef __LP64__
    uint32_t reserved;
#endif
    
    const uint8_t * ivarLayout;
    
    const char * name;//类的名称
    method_list_t * baseMethodList;//基础方法列表
    protocol_list_t * baseProtocols;//基础协议列表
    const ivar_list_t * ivars;//变量列表
    
    const uint8_t * weakIvarLayout;
    property_list_t *baseProperties;//基础属性列表
    //获取基础方法列表
    method_list_t *baseMethods() const {
        return baseMethodList;
    }
};


/* 可被分类扩展的元数据的通用实现。
 * @param Element 底层元数据类型(例如method_t)
 * @param List 元数据的列表类型(例如method_list_t)
 *
 * list_array_tt 有三个值:
 * - empty
 * - 指向单个列表的指针
 * - 指向列表的指针数组
 *
 * countLists/beginLists/endLists 迭代元数据列表
 * count/begin/end 迭代底层元数据元素
 */
template <typename Element, typename List> class list_array_tt {
    struct array_t {
        uint32_t count;
        List* lists[0];//方法列表，存储着一个个方法
        
        static size_t byteSize(uint32_t count) {
            return sizeof(array_t) + count*sizeof(lists[0]);
        }
        size_t byteSize() {
            return byteSize(count);
        }
    };
    
protected:
    class iterator {
        List **lists;
        List **listsEnd;
        typename List::iterator m, mEnd;
        
    public:
        iterator(List **begin, List **end)
        : lists(begin), listsEnd(end)
        {
            if (begin != end) {
                m = (*begin)->begin();
                mEnd = (*begin)->end();
            }
        }
        
        const Element& operator * () const {
            return *m;
        }
        Element& operator * () {
            return *m;
        }
        
        bool operator != (const iterator& rhs) const {
            if (lists != rhs.lists) return true;
            if (lists == listsEnd) return false;  // m 未定义的
            if (m != rhs.m) return true;
            return false;
        }
        
        const iterator& operator ++ () {
            assert(m != mEnd);
            m++;
            if (m == mEnd) {
                assert(lists != listsEnd);
                lists++;
                if (lists != listsEnd) {
                    m = (*lists)->begin();
                    mEnd = (*lists)->end();
                }
            }
            return *this;
        }
    };
    
private:
    union {
        List* list;
        uintptr_t arrayAndFlag;
    };
    
    bool hasArray() const {
        return arrayAndFlag & 1;
    }
    
    array_t *array() {
        return (array_t *)(arrayAndFlag & ~1);
    }
    
    void setArray(array_t *array) {
        arrayAndFlag = (uintptr_t)array | 1;
    }
    
public:
    
    uint32_t count() {
        uint32_t result = 0;
        for (auto lists = beginLists(), end = endLists();
             lists != end;
             ++lists)
        {
            result += (*lists)->count;
        }
        return result;
    }
    
    iterator begin() {
        return iterator(beginLists(), endLists());
    }
    
    iterator end() {
        List **e = endLists();
        return iterator(e, e);
    }
    
    
    uint32_t countLists() {
        if (hasArray()) {
            return array()->count;
        } else if (list) {
            return 1;
        } else {
            return 0;
        }
    }
    
    List** beginLists() {
        if (hasArray()) {
            return array()->lists;
        } else {
            return &list;
        }
    }
    
    List** endLists() {
        if (hasArray()) {
            return array()->lists + array()->count;
        } else if (list) {
            return &list + 1;
        } else {
            return &list;
        }
    }
    
    void attachLists(List* const * addedLists, uint32_t addedCount) {
        if (addedCount == 0) return;
        
        if (hasArray()) {
            // many lists -> many lists
            uint32_t oldCount = array()->count;
            uint32_t newCount = oldCount + addedCount;
            setArray((array_t *)realloc(array(), array_t::byteSize(newCount)));
            array()->count = newCount;
            memmove(array()->lists + addedCount, array()->lists, oldCount * sizeof(array()->lists[0]));
            memcpy(array()->lists, addedLists,addedCount * sizeof(array()->lists[0]));
        }
        else if (!list  &&  addedCount == 1) {
            // 0 lists -> 1 list
            list = addedLists[0];
        }
        else {
            // 1 list -> many lists
            List* oldList = list;
            uint32_t oldCount = oldList ? 1 : 0;
            uint32_t newCount = oldCount + addedCount;
            setArray((array_t *)malloc(array_t::byteSize(newCount)));
            array()->count = newCount;
            if (oldList) array()->lists[addedCount] = oldList;
            memcpy(array()->lists, addedLists,addedCount * sizeof(array()->lists[0]));
        }
    }
    
    void tryFree() {
        if (hasArray()) {
            for (uint32_t i = 0; i < array()->count; i++) {
                try_free(array()->lists[i]);
            }
            try_free(array());
        }
        else if (list) {
            try_free(list);
        }
    }
    
    template<typename Result>
    Result duplicate() {
        Result result;
        
        if (hasArray()) {
            array_t *a = array();
            result.setArray((array_t *)memdup(a, a->byteSize()));
            for (uint32_t i = 0; i < a->count; i++) {
                result.array()->lists[i] = a->lists[i]->duplicate();
            }
        } else if (list) {
            result.list = list->duplicate();
        } else {
            result.list = nil;
        }
        
        return result;
    }
};


class method_array_t : public list_array_tt<method_t, method_list_t>{
    typedef list_array_tt<method_t, method_list_t> Super;
    
public:
    method_list_t **beginCategoryMethodLists() {
        return beginLists();
    }
    
    method_list_t **endCategoryMethodLists(Class cls);
    
    method_array_t duplicate() {
        return Super::duplicate<method_array_t>();
    }
};


class property_array_t : public list_array_tt<property_t, property_list_t>{
    typedef list_array_tt<property_t, property_list_t> Super;
    
public:
    property_array_t duplicate() {
        return Super::duplicate<property_array_t>();
    }
};


class protocol_array_t : public list_array_tt<protocol_ref_t, protocol_list_t>{
    typedef list_array_tt<protocol_ref_t, protocol_list_t> Super;
    
public:
    protocol_array_t duplicate() {
        return Super::duplicate<protocol_array_t>();
    }
};

//ObjC 类中的属性、方法还有遵循的协议等信息都保存在 class_rw_t 中
struct class_rw_t {
    // Symbolication 知道此结构的布局。
    uint32_t flags;
    uint32_t version;
    
    const class_ro_t *ro;
    
    method_array_t methods;
    property_array_t properties;
    protocol_array_t protocols;
    
    Class firstSubclass;
    Class nextSiblingClass;
    
    char *demangledName;
    
#if SUPPORT_INDEXED_ISA
    uint32_t index;
#endif
    
    void setFlags(uint32_t set)
    {
        OSAtomicOr32Barrier(set, &flags);
    }
    
    void clearFlags(uint32_t clear)
    {
        OSAtomicXor32Barrier(clear, &flags);
    }
    
    // 设置和清除不能重叠
    void changeFlags(uint32_t set, uint32_t clear)
    {
        assert((set & clear) == 0);
        
        uint32_t oldf, newf;
        do {
            oldf = flags;
            newf = (oldf | set) & ~clear;
        } while (!OSAtomicCompareAndSwap32Barrier(oldf, newf, (volatile int32_t *)&flags));
    }
};


struct class_data_bits_t {
    
    uintptr_t bits;//值是上面的 FAST_ 标志。
private:
    bool getBit(uintptr_t bit){
        return bits & bit;
    }
    
#if FAST_ALLOC
    static uintptr_t updateFastAlloc(uintptr_t oldBits, uintptr_t change){
        if (change & FAST_ALLOC_MASK) {
            if (((oldBits & FAST_ALLOC_MASK) == FAST_ALLOC_VALUE)  &&
                ((oldBits >> FAST_SHIFTED_SIZE_SHIFT) != 0))
            {
                oldBits |= FAST_ALLOC;
            } else {
                oldBits &= ~FAST_ALLOC;
            }
        }
        return oldBits;
    }
#else
    static uintptr_t updateFastAlloc(uintptr_t oldBits, uintptr_t change) {
        return oldBits;
    }
#endif
    
    void setBits(uintptr_t set)
    {
        uintptr_t oldBits;
        uintptr_t newBits;
        do {
            oldBits = LoadExclusive(&bits);
            newBits = updateFastAlloc(oldBits | set, set);
        } while (!StoreReleaseExclusive(&bits, oldBits, newBits));
    }
    
    void clearBits(uintptr_t clear){
        uintptr_t oldBits;
        uintptr_t newBits;
        do {
            oldBits = LoadExclusive(&bits);
            newBits = updateFastAlloc(oldBits & ~clear, clear);
        } while (!StoreReleaseExclusive(&bits, oldBits, newBits));
    }
    
public:
    
    class_rw_t* data() {
        // 0x00007ffffffffff8
        //
        // 将 bits 与 FAST_DATA_MASK 进行位运算，只取其中的 [3, 47] 位转换成 class_rw_t * 返回。
        return (class_rw_t *)(bits & FAST_DATA_MASK);
    }
    void setData(class_rw_t *newData)
    {
        assert(!data()  ||  (newData->flags & (RW_REALIZING | RW_FUTURE)));
        
        /* 仅在实现或构建期间设置;不需要锁。
         * 使用 store-release 隔离，因为可能存在数据和数据内容的并发读取器。
         */
        uintptr_t newBits = (bits & ~FAST_DATA_MASK) | (uintptr_t)newData;
        atomic_thread_fence(memory_order_release);
        bits = newBits;
    }
    
#if FAST_HAS_DEFAULT_RR
    /* 当前类或者父类含有默认的 retain/release/autorelease/retainCount/_tryRetain/_isDeallocating/retainWeakReference/allowsWeakReference 方法
     */
    bool hasDefaultRR() {
        return getBit(FAST_HAS_DEFAULT_RR);
    }
    void setHasDefaultRR() {
        setBits(FAST_HAS_DEFAULT_RR);
    }
    void setHasCustomRR() {
        clearBits(FAST_HAS_DEFAULT_RR);
    }
#else
    bool hasDefaultRR() {
        return data()->flags & RW_HAS_DEFAULT_RR;
    }
    void setHasDefaultRR() {
        data()->setFlags(RW_HAS_DEFAULT_RR);
    }
    void setHasCustomRR() {
        data()->clearFlags(RW_HAS_DEFAULT_RR);
    }
#endif
    
#if FAST_HAS_DEFAULT_AWZ
    bool hasDefaultAWZ() {
        // 类或父类实现默认的alloc/allocWithZone:方法；注意这是存储在元类中的。
        return getBit(FAST_HAS_DEFAULT_AWZ);
    }
    void setHasDefaultAWZ() {
        setBits(FAST_HAS_DEFAULT_AWZ);
    }
    void setHasCustomAWZ() {
        clearBits(FAST_HAS_DEFAULT_AWZ);
    }
#else
    bool hasDefaultAWZ() {
        return data()->flags & RW_HAS_DEFAULT_AWZ;
    }
    void setHasDefaultAWZ() {
        data()->setFlags(RW_HAS_DEFAULT_AWZ);
    }
    void setHasCustomAWZ() {
        data()->clearFlags(RW_HAS_DEFAULT_AWZ);
    }
#endif
    
#if FAST_HAS_CXX_CTOR
    bool hasCxxCtor() {
        return getBit(FAST_HAS_CXX_CTOR);
    }
    void setHasCxxCtor() {
        setBits(FAST_HAS_CXX_CTOR);
    }
#else
    bool hasCxxCtor() {
        return data()->flags & RW_HAS_CXX_CTOR;
    }
    void setHasCxxCtor() {
        data()->setFlags(RW_HAS_CXX_CTOR);
    }
#endif
    
#if FAST_HAS_CXX_DTOR
    bool hasCxxDtor() {
        return getBit(FAST_HAS_CXX_DTOR);
    }
    void setHasCxxDtor() {
        setBits(FAST_HAS_CXX_DTOR);
    }
#else
    bool hasCxxDtor() {
        return data()->flags & RW_HAS_CXX_DTOR;
    }
    void setHasCxxDtor() {
        data()->setFlags(RW_HAS_CXX_DTOR);
    }
#endif
    
#if FAST_REQUIRES_RAW_ISA
    bool instancesRequireRawIsa() {
        return getBit(FAST_REQUIRES_RAW_ISA);
    }
    void setInstancesRequireRawIsa() {
        setBits(FAST_REQUIRES_RAW_ISA);
    }
#elif SUPPORT_NONPOINTER_ISA
    bool instancesRequireRawIsa() {
        return data()->flags & RW_REQUIRES_RAW_ISA;
    }
    void setInstancesRequireRawIsa() {
        data()->setFlags(RW_REQUIRES_RAW_ISA);
    }
#else
    bool instancesRequireRawIsa() {
        return true;
    }
    void setInstancesRequireRawIsa() {
        // nothing
    }
#endif
    
#if FAST_ALLOC
    size_t fastInstanceSize()
    {
        assert(bits & FAST_ALLOC);
        return (bits >> FAST_SHIFTED_SIZE_SHIFT) * 16;
    }
    void setFastInstanceSize(size_t newSize)
    {
        // Set during realization or construction only. No locking needed.
        assert(data()->flags & RW_REALIZING);
        
        // Round up to 16-byte boundary, then divide to get 16-byte units
        newSize = ((newSize + 15) & ~15) / 16;
        
        uintptr_t newBits = newSize << FAST_SHIFTED_SIZE_SHIFT;
        if ((newBits >> FAST_SHIFTED_SIZE_SHIFT) == newSize) {
            int shift = WORD_BITS - FAST_SHIFTED_SIZE_SHIFT;
            uintptr_t oldBits = (bits << shift) >> shift;
            if ((oldBits & FAST_ALLOC_MASK) == FAST_ALLOC_VALUE) {
                newBits |= FAST_ALLOC;
            }
            bits = oldBits | newBits;
        }
    }
    
    bool canAllocFast() {
        return bits & FAST_ALLOC;
    }
#else
    size_t fastInstanceSize() {
        abort();
    }
    void setFastInstanceSize(size_t) {
        // nothing
    }
    bool canAllocFast() {
        return false;
    }
#endif
    
    void setClassArrayIndex(unsigned Idx) {
#if SUPPORT_INDEXED_ISA
        // 0 is unused as then we can rely on zero-initialisation from calloc.
        assert(Idx > 0);
        data()->index = Idx;
#endif
    }
    
    unsigned classArrayIndex() {
#if SUPPORT_INDEXED_ISA
        return data()->index;
#else
        return 0;
#endif
    }
    
    bool isAnySwift() {
        return isSwiftStable() || isSwiftLegacy();
    }
    
    bool isSwiftStable() {
        return getBit(FAST_IS_SWIFT_STABLE);
    }
    void setIsSwiftStable() {
        setBits(FAST_IS_SWIFT_STABLE);
    }
    
    bool isSwiftLegacy() {
        return getBit(FAST_IS_SWIFT_LEGACY);
    }
    void setIsSwiftLegacy() {
        setBits(FAST_IS_SWIFT_LEGACY);
    }
};


struct objc_class : objc_object {
    // Class ISA;
    Class superclass;//指向当前类的父类
    cache_t cache;  //用于缓存指针和 vtable，加速方法的调用
    class_data_bits_t bits;// class_rw_t* 加上自定义的rr/alloc标志；rr/alloc标志是指含有这些方法：retain/release/autorelease/retainCount/alloc等
    //存储类的方法、属性、遵循的协议等信息
    
    class_rw_t *data() {
        return bits.data();
    }
    void setData(class_rw_t *newData) {
        bits.setData(newData);
    }
    
    void setInfo(uint32_t set) {
        assert(isFuture()  ||  isRealized());
        data()->setFlags(set);
    }
    
    void clearInfo(uint32_t clear) {
        assert(isFuture()  ||  isRealized());
        data()->clearFlags(clear);
    }
    
    // set and clear must not overlap
    void changeInfo(uint32_t set, uint32_t clear) {
        assert(isFuture()  ||  isRealized());
        assert((set & clear) == 0);
        data()->changeFlags(set, clear);
    }
    //表明该类是否自定义了release和retain方法,在ARC下是不允许使用release和retain的
    bool hasCustomRR() {
         /* 查看是否有自定义的RR方法,RR方法包括：
             retain、release、autorelease、retainCount、tryRetain
             SEL_retainWeakReference
             isDeallocating
             allowsWeakReference);
             */
        return ! bits.hasDefaultRR();
    }
    void setHasDefaultRR() {
        assert(isInitializing());
        bits.setHasDefaultRR();
    }
    void setHasCustomRR(bool inherited = false);
    void printCustomRR(bool inherited);
    
    bool hasCustomAWZ() {
        // 类或父类实现默认的alloc/allocWithZone:方法；注意这是存储在元类中的。
        return ! bits.hasDefaultAWZ();
    }
    void setHasDefaultAWZ() {
        assert(isInitializing());
        bits.setHasDefaultAWZ();
    }
    void setHasCustomAWZ(bool inherited = false);
    void printCustomAWZ(bool inherited);
    
    bool instancesRequireRawIsa() {
        return bits.instancesRequireRawIsa();
    }
    void setInstancesRequireRawIsa(bool inherited = false);
    void printInstancesRequireRawIsa(bool inherited);
    
    bool canAllocNonpointer() {
        assert(!isFuture());
        return !instancesRequireRawIsa();
    }
    bool canAllocFast() {
        assert(!isFuture());
        return bits.canAllocFast();
    }
    
    
    bool hasCxxCtor() {
        // addSubclass() 从超类传播此标志。
        assert(isRealized());
        return bits.hasCxxCtor();
    }
    void setHasCxxCtor() {
        bits.setHasCxxCtor();
    }
    
    bool hasCxxDtor() {
        // addSubclass() 从超类传播此标志。
        assert(isRealized());
        return bits.hasCxxDtor();
    }
    void setHasCxxDtor() {
        bits.setHasCxxDtor();
    }
    
    
    bool isSwiftStable() {
        return bits.isSwiftStable();
    }
    
    bool isSwiftLegacy() {
        return bits.isSwiftLegacy();
    }
    
    bool isAnySwift() {
        return bits.isAnySwift();
    }
    
    
    // 如果类的ivars由ARC管理，则返回YES，
    // 类是MRC但具有ARC风格的弱ivars，则返回YES。
    bool hasAutomaticIvars() {
        return data()->ro->flags & (RO_IS_ARC | RO_HAS_WEAK_WITHOUT_ARC);
    }
    
    // 如果类的ivars由ARC管理，则返回YES。
    bool isARC() {
        return data()->ro->flags & RO_IS_ARC;
    }
    
    
#if SUPPORT_NONPOINTER_ISA
    // Tracked in non-pointer isas; not tracked otherwise
#else
    bool instancesHaveAssociatedObjects() {
        // this may be an unrealized future class in the CF-bridged case
        assert(isFuture()  ||  isRealized());
        return data()->flags & RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS;
    }
    
    void setInstancesHaveAssociatedObjects() {
        // this may be an unrealized future class in the CF-bridged case
        assert(isFuture()  ||  isRealized());
        setInfo(RW_INSTANCES_HAVE_ASSOCIATED_OBJECTS);
    }
#endif
    
    bool shouldGrowCache() {
        return true;
    }
    
    void setShouldGrowCache(bool) {
        // fixme good or bad for memory use?
    }
    
    bool isInitializing() {
        return getMeta()->data()->flags & RW_INITIALIZING;
    }
    
    void setInitializing() {//设置该类的状态为：正在初始化
        assert(!isMetaClass());
        ISA()->setInfo(RW_INITIALIZING);//正在初始化 flags&1<<28
    }
    
    bool isInitialized() {//判断该类的状态为：已完成初始化
        return getMeta()->data()->flags & RW_INITIALIZED;// flags&1<<29
    }
    
    void setInitialized();
    
    bool isLoadable() {
        assert(isRealized());
        return true;  // any class registered for +load is definitely loadable
    }
    
    IMP getLoadMethod();
    
    // Locking: To prevent concurrent realization, hold runtimeLock.
    bool isRealized() {
        return data()->flags & RW_REALIZED;// flags&1<<31
    }
    
    // Returns true if this is an unrealized future class.
    // Locking: To prevent concurrent realization, hold runtimeLock.
    bool isFuture() {
        return data()->flags & RW_FUTURE;// flags&1<<30
    }
    
    bool isMetaClass() {//只读
        assert(this);
        assert(isRealized());
        return data()->ro->flags & RO_META;// flags&1<<0
    }
    
    /* 获取该类的元类
     * @note 当该类就是元类时，只会返回自身，不会返回根元类 NSObject
     */
    Class getMeta() {
        if (isMetaClass()) return (Class)this;
        else return this->ISA();
    }
    
    //判断该类是否是根类
    bool isRootClass() {
        return superclass == nil;//根类的 superclass 为 nil
    }
    
    //判断该类是否是根元类
    bool isRootMetaclass() {
        return ISA() == (Class)this;//根元类的 isa 指向它自身
    }
    
    const char *mangledName() {
        // fixme can't assert locks here
        assert(this);
        
        if (isRealized()  ||  isFuture()) {
            return data()->ro->name;
        } else {
            return ((const class_ro_t *)data())->name;
        }
    }
    
    const char *demangledName(bool realize = false);
    const char *nameForLogging();
    
    // May be unaligned depending on class's ivars.
    uint32_t unalignedInstanceStart() {
        assert(isRealized());
        return data()->ro->instanceStart;
    }
    
    // Class's instance start rounded up to a pointer-size boundary.
    // This is used for ARC layout bitmaps.
    uint32_t alignedInstanceStart() {
        return word_align(unalignedInstanceStart());
    }
    
    // May be unaligned depending on class's ivars.
    uint32_t unalignedInstanceSize() {
        assert(isRealized());
        return data()->ro->instanceSize;
    }
    
    // Class's ivar size rounded up to a pointer-size boundary.
    uint32_t alignedInstanceSize() {
        return word_align(unalignedInstanceSize());
    }
    
    size_t instanceSize(size_t extraBytes) {
        size_t size = alignedInstanceSize() + extraBytes;
        // CF requires all objects be at least 16 bytes.
        if (size < 16) size = 16;
        return size;
    }
    
    void setInstanceSize(uint32_t newSize) {
        assert(isRealized());
        if (newSize != data()->ro->instanceSize) {
            assert(data()->flags & RW_COPIED_RO);
            *const_cast<uint32_t *>(&data()->ro->instanceSize) = newSize;
        }
        bits.setFastInstanceSize(newSize);
    }
    
    void chooseClassArrayIndex();
    
    void setClassArrayIndex(unsigned Idx) {
        bits.setClassArrayIndex(Idx);
    }
    
    unsigned classArrayIndex() {
        return bits.classArrayIndex();
    }
    
};


struct swift_class_t : objc_class {
    uint32_t flags;
    uint32_t instanceAddressOffset;
    uint32_t instanceSize;
    uint16_t instanceAlignMask;
    uint16_t reserved;
    
    uint32_t classSize;
    uint32_t classAddressOffset;
    void *description;
    // ...
    
    void *baseAddress() {
        return (void *)((uint8_t *)this - classAddressOffset);
    }
};


struct category_t {
    const char *name;//分类所属的类的名称
    classref_t cls;//分类所属的类
    struct method_list_t *instanceMethods;//分类里添加的实例方法列表
    struct method_list_t *classMethods;//分类添加的类方法列表
    struct protocol_list_t *protocols;//分类实现的协议列表
    struct property_list_t *instanceProperties;//分类添加的实例属性列表
    struct property_list_t *_classProperties;  //分类添加的类属性列表
    
    //获取方法列表
    method_list_t *methodsForMeta(bool isMeta) {
        if (isMeta) return classMethods;
        else return instanceMethods;
    }
    //获取属性列表
    property_list_t *propertiesForMeta(bool isMeta, struct header_info *hi);
};

struct objc_super2 {
    id receiver;
    Class current_class;
};

struct message_ref_t {
    IMP imp;
    SEL sel;
};


extern Method protocol_getMethod(protocol_t *p, SEL sel, bool isRequiredMethod, bool isInstanceMethod, bool recursive);

static inline void foreach_realized_class_and_subclass_2(Class top, unsigned& count, std::function<bool (Class)> code){
    // runtimeLock.assertLocked();
    assert(top);
    Class cls = top;
    while (1) {
        if (--count == 0) {
            _objc_fatal("Memory corruption in class list.");
        }
        if (!code(cls)) break;
        
        if (cls->data()->firstSubclass) {
            cls = cls->data()->firstSubclass;
        } else {
            while (!cls->data()->nextSiblingClass  &&  cls != top) {
                cls = cls->superclass;
                if (--count == 0) {
                    _objc_fatal("Memory corruption in class list.");
                }
            }
            if (cls == top) break;
            cls = cls->data()->nextSiblingClass;
        }
    }
}

extern Class firstRealizedClass();
extern unsigned int unreasonableClassCount();

// 枚举一个类及其所有已实现的子类
static inline void foreach_realized_class_and_subclass(Class top, std::function<void (Class)> code){
    unsigned int count = unreasonableClassCount();
    
    foreach_realized_class_and_subclass_2(top, count,
                                          [&code](Class cls) -> bool
                                          {
                                              code(cls);
                                              return true;
                                          });
}

// 枚举所有已实现的类和元类。
static inline void foreach_realized_class_and_metaclass(std::function<void (Class)> code){
    unsigned int count = unreasonableClassCount();
    
    for (Class top = firstRealizedClass();
         top != nil;
         top = top->data()->nextSiblingClass)
    {
        foreach_realized_class_and_subclass_2(top, count,
                                              [&code](Class cls) -> bool
                                              {
                                                  code(cls);
                                                  return true;
                                              });
    }
    
}

#endif


