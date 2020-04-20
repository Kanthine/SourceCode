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
*	objc-class.m
*	Copyright 1988-1997, Apple Computer, Inc.
*	Author:	s. naroff
**********************************************************************/


/*
 * 懒加载方法列表数组和方法列表锁定 (2004-10-19)
 * cls->methodLists 有三种形式:
 * 1. nil: 这个类没有方法。
 * 2. 非nil，使用 CLS_NO_METHOD_ARRAY 设置:cls->methodLists指向一个方法列表，这是类唯一的方法列表。
 * 3. 非nil，清除 CLS_NO_METHOD_ARRAY : cls->methodLists指向一个方法列表指针数组。数组块的末尾被设置为-1。如果方法列表的实际数量小于这个数，那么数组的其余部分就是nil。
 *
 *
 * 附加分类以及添加和删除类可能会更改类列表的形式。此外，单个方法列表可以在修复时重新分配。
 *
 * 类最初读作#1或#2。如果附加了分类或添加了其他方法，则该类将更改为#3。一旦进入#3，即使删除了方法，类也不会降级为#1或#2。
 * 使用 objc_addClass() 添加的类最初是#1或#3。
 *
 * 需要同步访问和操作类的方法列表，以防止在一个线程修改列表时发生数据竞争。但是，如果这个类还没有被使用(即不在class_hash中)，那么加载这个类的线程可以不加锁地访问它的方法列表。
 * 下面的函数获取 methodListLock:
 *     class_getInstanceMethod() 函数
 *     class_getClassMethod() 函数
 *     class_nextMethodList() 函数
 *     class_addMethods() 函数
 *     class_removeMethods() 函数
 *     class_respondsToMethod() 函数
 *     _class_lookupMethodAndLoadCache() 函数
 *     lookupMethodInClassAndLoadCache() 函数
 *     _objc_add_category_flush_caches() 函数
 *
 * 下面的函数不获取methodListLock，因为它们只在类加载和卸载期间访问方法列表:
 *     _objc_register_category() 函数
 *     _resolve_categories_for_class (calls _objc_add_category) 函数
 *     add_class_to_loadable_list() 函数
 *     _objc_addClass() 函数
 *     _objc_remove_classes_in_image() 函数
 *
 * 下面的函数使用方法列表而不保存methodListLock ：调用方必须持有methodListLock或正在加载类。
 *     _getMethod (called by class_getInstanceMethod, class_getClassMethod, class_respondsToMethod) 函数
 *     _findMethodInClass (called by _class_lookupMethodAndLoadCache,lookupMethodInClassAndLoadCache, _getMethod)
 *     _findMethodInList (called by _findMethodInClass)
 *     nextMethodList (called by _findMethodInClass and class_nextMethodList
 *     fixupSelectorsInMethodList (called by nextMethodList)
 *     _objc_add_category (called by _objc_add_category_flush_caches, resolve_categories_for_class and _objc_register_category)
 *     _objc_insertMethods (called by class_addMethods and _objc_add_category)
 *     _objc_removeMethods (called by class_removeMethods)
 *     _objcTweakMethodListPointerForClass (called by _objc_insertMethods)
 *     get_base_method_list (called by add_class_to_loadable_list)
 *     lookupNamedMethodInMethodList (called by add_class_to_loadable_list)
 *
 *
 *
 * 类信息位的线程安全性 （2004-10-19）
 *
 * 一些类信息位用于存储可变的运行时状态：信息位在特定时间的修改需要同步，以防止竞争。
 *
 * 提供三个线程安全的修改函数:
 *   cls->setInfo()     // atomically 设置一些位
 *   cls->clearInfo()   // atomically 清除一些位
 *   cls->changeInfo()  // atomically 设置一些位、清除一些位
 * 它们替换多线程情况下的 CLS_SETINFO()。
 *
 * 定义了三个修改窗口:
 *   编译时
 *   一个线程中的类构造或镜像加载（在+load之前）
 *   多线程消息传递和方法缓存
 * 编译时的信息位修改和类构造不需要锁定，因为只有一个线程在操作类。
 * 消息传递期间的信息位修改需要锁定，因为可能有其他线程同时消息传递或以其他方式操作类。
 *
 *
 * 每个标志的修改窗口:
 *  CLS_CLASS: 编译时和类加载
 *  CLS_META: 编译时和类加载
 *  CLS_INITIALIZED: +initialize
 *  CLS_POSING: 消息传递
 *  CLS_MAPPED: 编译时
 *  CLS_FLUSH_CACHE: 类加载和消息传递
 *  CLS_GROW_CACHE: 消息传递
 *  CLS_NEED_BIND: 未使用
 *  CLS_METHOD_ARRAY: 未使用
 *  CLS_JAVA_HYBRID: JavaBridge only
 *  CLS_JAVA_CLASS: JavaBridge only
 *  CLS_INITIALIZING: 消息传递
 *  CLS_FROM_BUNDLE: 类加载
 *  CLS_HAS_CXX_STRUCTORS: 编译时和类加载
 *  CLS_NO_METHOD_ARRAY: 类加载和消息传递
 *  CLS_HAS_LOAD_METHOD: 类加载
 *
 * CLS_INITIALIZED 和 CLS_INITIALIZING 有额外的线程安全约束来支持线程安全 +initialize。有关详细信息，请参见“类初始化期间的线程安全”。
 * 在 JavaBridge 调用 objc_addClass() 之后立即设置 CLS_JAVA_HYBRID 和 CLS_JAVA_CLASS 。 JavaBridge不使用原子更新，但修改计为“类构造”，除非其他一些线程通过类列表快速找到类。 这种竞争很小，在行为良好的代码中不太可能发生。
 *
 * 在消息传递期间可能被修改的大多数信息位，不会在没有锁的情况下读取。信息位没有通用读锁。
 *  CLS_INITIALIZED: classInitLock
 *  CLS_FLUSH_CACHE: cacheUpdateLock
 *  CLS_GROW_CACHE: cacheUpdateLock
 *  CLS_NO_METHOD_ARRAY: methodListLock
 *  CLS_INITIALIZING: classInitLock
 */

/* Imports.
 */

#include "objc-private.h"
#include "objc-abi.h"
#include <objc/message.h>

/* 关于多线程支持的信息:
 * 由于不会锁定很多遍历超类、方法和ivars的操作，因此通过将类插入类hashtable，这些链必须在发布类时保持完整。所有的修改都必须是原子的，这样通过这些链的操作将始终得到有效的结果。
 */



/* 获取 obj 的 isa 指针
* @param obj 指定对象
*        如果是实例对象，那么该实例对象的 isa 指向其所属的类；
*        如果是一个类，那么该类的 isa 指向其所属的元类；
* @note  如果 obj 为 nil ，则返回 nil
*/
Class object_getClass(id obj){
    if (obj) return obj->getIsa();
    else return Nil;
}


/* 设置一个对象所属的类
 */
Class object_setClass(id obj, Class cls){
    if (!obj) return nil;

    /* 防止弱引用机制之间的死锁
     * 通过确保没有弱引用的对象具有未初始化的isa，防止弱引用机制和 +initialize 机制之间的死锁。 未解决的future classes不受保护。
     */
    if (!cls->isFuture()  &&  !cls->isInitialized()) {
        _class_initialize(_class_getNonMetaClass(cls, nil));
    }

    return obj->changeIsa(cls);
}


/* 判断指定的对象是否是一个 Objective—C 类
 * @note 本质还是判断该实例的 isa 是否指向元类，如果指向元类，则是一个 Objective—C 类，否则不是 Objective—C 类；
 * @note 如果是 Tagged Pointer 对象，则不是一个类
 */
BOOL object_isClass(id obj){
    if (!obj) return NO;
    return obj->isClass();
}


/* 获取指定实例的类名
 */
const char *object_getClassName(id obj){
    return class_getName(obj ? obj->getIsa() : nil);
}


/* 获取一个实例中指定名称的方法实现
 * @param obj 一个实例对象
 * @param name 指定方法的名称
 */
IMP object_getMethodImplementation(id obj, SEL name){
    Class cls = (obj ? obj->getIsa() : nil);
    return class_getMethodImplementation(cls, name);
}


/***********************************************************************
 * object_getMethodImplementation_stret.
 **********************************************************************/
#if SUPPORT_STRET
IMP object_getMethodImplementation_stret(id obj, SEL name)
{
    Class cls = (obj ? obj->getIsa() : nil);
    return class_getMethodImplementation_stret(cls, name);
}
#endif


/* 被扫描？
 */
static bool isScanned(ptrdiff_t ivar_offset, const uint8_t *layout) {
    if (!layout) return NO;

    ptrdiff_t index = 0, ivar_index = ivar_offset / sizeof(void*);
    uint8_t byte;
    while ((byte = *layout++)) {
        unsigned skips = (byte >> 4);
        unsigned scans = (byte & 0x0F);
        index += skips;
        if (index > ivar_index) return NO;
        index += scans;
        if (index > ivar_index) return YES;
    }
    return NO;
}


/***********************************************************************
* _class_lookUpIvar
* Given an object and an ivar in it, look up some data about that ivar:
* - its offset
* - its memory management behavior
* The ivar is assumed to be word-aligned and of of object type.
**********************************************************************/
static void 
_class_lookUpIvar(Class cls, Ivar ivar, ptrdiff_t& ivarOffset, 
                  objc_ivar_memory_management_t& memoryManagement)
{
    ivarOffset = ivar_getOffset(ivar);
    
    // Look for ARC variables and ARC-style weak.

    // Preflight the hasAutomaticIvars check
    // because _class_getClassForIvar() may need to take locks.
    bool hasAutomaticIvars = NO;
    for (Class c = cls; c; c = c->superclass) {
        if (c->hasAutomaticIvars()) {
            hasAutomaticIvars = YES;
            break;
        }
    }

    if (hasAutomaticIvars) {
        Class ivarCls = _class_getClassForIvar(cls, ivar);
        if (ivarCls->hasAutomaticIvars()) {
            // ARC layout bitmaps encode the class's own ivars only.
            // Use alignedInstanceStart() because unaligned bytes at the start
            // of this class's ivars are not represented in the layout bitmap.
            ptrdiff_t localOffset = 
                ivarOffset - ivarCls->alignedInstanceStart();

            if (isScanned(localOffset, class_getIvarLayout(ivarCls))) {
                memoryManagement = objc_ivar_memoryStrong;
                return;
            }
            
            if (isScanned(localOffset, class_getWeakIvarLayout(ivarCls))) {
                memoryManagement = objc_ivar_memoryWeak;
                return;
            }

            // Unretained is only for true ARC classes.
            if (ivarCls->isARC()) {
                memoryManagement = objc_ivar_memoryUnretained;
                return;
            }
        }
    }
    
    memoryManagement = objc_ivar_memoryUnknown;
}


/***********************************************************************
* _class_getIvarMemoryManagement
* SPI for KVO and others to decide what memory management to use 
* when setting instance variables directly.
**********************************************************************/
objc_ivar_memory_management_t 
_class_getIvarMemoryManagement(Class cls, Ivar ivar)
{
    ptrdiff_t offset;
    objc_ivar_memory_management_t memoryManagement;
    _class_lookUpIvar(cls, ivar, offset, memoryManagement);
    return memoryManagement;
}


static ALWAYS_INLINE 
void _object_setIvar(id obj, Ivar ivar, id value, bool assumeStrong)
{
    if (!obj  ||  !ivar  ||  obj->isTaggedPointer()) return;

    ptrdiff_t offset;
    objc_ivar_memory_management_t memoryManagement;
    _class_lookUpIvar(obj->ISA(), ivar, offset, memoryManagement);

    if (memoryManagement == objc_ivar_memoryUnknown) {
        if (assumeStrong) memoryManagement = objc_ivar_memoryStrong;
        else memoryManagement = objc_ivar_memoryUnretained;
    }

    id *location = (id *)((char *)obj + offset);

    switch (memoryManagement) {
    case objc_ivar_memoryWeak:       objc_storeWeak(location, value); break;
    case objc_ivar_memoryStrong:     objc_storeStrong(location, value); break;
    case objc_ivar_memoryUnretained: *location = value; break;
    case objc_ivar_memoryUnknown:    _objc_fatal("impossible");
    }
}

void object_setIvar(id obj, Ivar ivar, id value)
{
    return _object_setIvar(obj, ivar, value, false /*not strong default*/);
}

void object_setIvarWithStrongDefault(id obj, Ivar ivar, id value)
{
    return _object_setIvar(obj, ivar, value, true /*strong default*/);
}


id object_getIvar(id obj, Ivar ivar){
    if (!obj  ||  !ivar  ||  obj->isTaggedPointer()) return nil;
    ptrdiff_t offset;
    objc_ivar_memory_management_t memoryManagement;
    _class_lookUpIvar(obj->ISA(), ivar, offset, memoryManagement);
    id *location = (id *)((char *)obj + offset);
    if (memoryManagement == objc_ivar_memoryWeak) {
        return objc_loadWeak(location);
    } else {
        return *location;
    }
}


static ALWAYS_INLINE  Ivar _object_setInstanceVariable(id obj, const char *name, void *value,
                                 bool assumeStrong){
    Ivar ivar = nil;

    if (obj  &&  name  &&  !obj->isTaggedPointer()) {
        if ((ivar = _class_getVariable(obj->ISA(), name))) {
            _object_setIvar(obj, ivar, (id)value, assumeStrong);
        }
    }
    return ivar;
}

Ivar object_setInstanceVariable(id obj, const char *name, void *value)
{
    return _object_setInstanceVariable(obj, name, value, false);
}

Ivar object_setInstanceVariableWithStrongDefault(id obj, const char *name, 
                                                 void *value)
{
    return _object_setInstanceVariable(obj, name, value, true);
}


Ivar object_getInstanceVariable(id obj, const char *name, void **value)
{
    if (obj  &&  name  &&  !obj->isTaggedPointer()) {
        Ivar ivar;
        if ((ivar = class_getInstanceVariable(obj->ISA(), name))) {
            if (value) *value = (void *)object_getIvar(obj, ivar);
            return ivar;
        }
    }
    if (value) *value = nil;
    return nil;
}


/***********************************************************************
* object_cxxDestructFromClass.
* Call C++ destructors on obj, starting with cls's 
*   dtor method (if any) followed by superclasses' dtors (if any), 
*   stopping at cls's dtor (if any).
* Uses methodListLock and cacheUpdateLock. The caller must hold neither.
**********************************************************************/
static void object_cxxDestructFromClass(id obj, Class cls)
{
    void (*dtor)(id);

    // Call cls's dtor first, then superclasses's dtors.

    for ( ; cls; cls = cls->superclass) {
        if (!cls->hasCxxDtor()) return; 
        dtor = (void(*)(id))
            lookupMethodInClassAndLoadCache(cls, SEL_cxx_destruct);
        if (dtor != (void(*)(id))_objc_msgForward_impcache) {
            if (PrintCxxCtors) {
                _objc_inform("CXX: calling C++ destructors for class %s", 
                             cls->nameForLogging());
            }
            (*dtor)(obj);
        }
    }
}


/***********************************************************************
* object_cxxDestruct.
* Call C++ destructors on obj, if any.
* Uses methodListLock and cacheUpdateLock. The caller must hold neither.
**********************************************************************/
void object_cxxDestruct(id obj)
{
    if (!obj) return;
    if (obj->isTaggedPointer()) return;
    object_cxxDestructFromClass(obj, obj->ISA());
}


/***********************************************************************
* object_cxxConstructFromClass.
* Recursively call C++ constructors on obj, starting with base class's 
*   ctor method (if any) followed by subclasses' ctors (if any), stopping 
*   at cls's ctor (if any).
* Does not check cls->hasCxxCtor(). The caller should preflight that.
* Returns self if construction succeeded.
* Returns nil if some constructor threw an exception. The exception is 
*   caught and discarded. Any partial construction is destructed.
* Uses methodListLock and cacheUpdateLock. The caller must hold neither.
*
* .cxx_construct returns id. This really means:
* return self: construction succeeded
* return nil:  construction failed because a C++ constructor threw an exception
**********************************************************************/
id 
object_cxxConstructFromClass(id obj, Class cls)
{
    assert(cls->hasCxxCtor());  // required for performance, not correctness

    id (*ctor)(id);
    Class supercls;

    supercls = cls->superclass;

    // Call superclasses' ctors first, if any.
    if (supercls  &&  supercls->hasCxxCtor()) {
        bool ok = object_cxxConstructFromClass(obj, supercls);
        if (!ok) return nil;  // some superclass's ctor failed - give up
    }

    // Find this class's ctor, if any.
    ctor = (id(*)(id))lookupMethodInClassAndLoadCache(cls, SEL_cxx_construct);
    if (ctor == (id(*)(id))_objc_msgForward_impcache) return obj;  // no ctor - ok
    
    // Call this class's ctor.
    if (PrintCxxCtors) {
        _objc_inform("CXX: calling C++ constructors for class %s", 
                     cls->nameForLogging());
    }
    if ((*ctor)(obj)) return obj;  // ctor called and succeeded - ok

    // This class's ctor was called and failed. 
    // Call superclasses's dtors to clean up.
    if (supercls) object_cxxDestructFromClass(obj, supercls);
    return nil;
}


/***********************************************************************
* fixupCopiedIvars
* Fix up ARC strong and ARC-style weak variables 
* after oldObject was memcpy'd to newObject.
**********************************************************************/
void fixupCopiedIvars(id newObject, id oldObject)
{
    for (Class cls = oldObject->ISA(); cls; cls = cls->superclass) {
        if (cls->hasAutomaticIvars()) {
            // Use alignedInstanceStart() because unaligned bytes at the start
            // of this class's ivars are not represented in the layout bitmap.
            size_t instanceStart = cls->alignedInstanceStart();

            const uint8_t *strongLayout = class_getIvarLayout(cls);
            if (strongLayout) {
                id *newPtr = (id *)((char*)newObject + instanceStart);
                unsigned char byte;
                while ((byte = *strongLayout++)) {
                    unsigned skips = (byte >> 4);
                    unsigned scans = (byte & 0x0F);
                    newPtr += skips;
                    while (scans--) {
                        // ensure strong references are properly retained.
                        id value = *newPtr++;
                        if (value) objc_retain(value);
                    }
                }
            }

            const uint8_t *weakLayout = class_getWeakIvarLayout(cls);
            // fix up weak references if any.
            if (weakLayout) {
                id *newPtr = (id *)((char*)newObject + instanceStart), *oldPtr = (id *)((char*)oldObject + instanceStart);
                unsigned char byte;
                while ((byte = *weakLayout++)) {
                    unsigned skips = (byte >> 4);
                    unsigned weaks = (byte & 0x0F);
                    newPtr += skips, oldPtr += skips;
                    while (weaks--) {
                        objc_copyWeak(newPtr, oldPtr);
                        ++newPtr, ++oldPtr;
                    }
                }
            }
        }
    }
}


/***********************************************************************
* _class_resolveClassMethod
* Call +resolveClassMethod, looking for a method to be added to class cls.
* cls should be a metaclass.
* Does not check if the method already exists.
**********************************************************************/
static void _class_resolveClassMethod(Class cls, SEL sel, id inst)
{
    assert(cls->isMetaClass());

    if (! lookUpImpOrNil(cls, SEL_resolveClassMethod, inst, NO, YES, NO))
    {
        // SEL_resolveClassMethod 方法没有实现。
        return;
    }

    BOOL (*msg)(Class, SEL, SEL) = (typeof(msg))objc_msgSend;
    bool resolved = msg(_class_getNonMetaClass(cls, inst), SEL_resolveClassMethod, sel);

    // 缓存结果(好或坏)，这样 SEL_resolveInstanceMethod 下次就不会触发。
    // +resolveClassMethod 增加了 self->ISA()
    IMP imp = lookUpImpOrNil(cls, sel, inst,NO, YES, NO);

    if (resolved  &&  PrintResolving) {
        if (imp) {
            _objc_inform("RESOLVE: method %c[%s %s] "
                         "dynamically resolved to %p", 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel), imp);
        }
        else {
            // Method resolver didn't add anything?
            _objc_inform("RESOLVE: +[%s resolveClassMethod:%s] returned YES"
                         ", but no new implementation of %c[%s %s] was found",
                         cls->nameForLogging(), sel_getName(sel), 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel));
        }
    }
}


/* 调用 +resolveInstanceMethod: ，查找要添加到类cls中的方法。
 * @param cls 可以是元类，也可以是非元类。
 * @note 不检查方法是否已经存在。
 * @note 关键处在于 class_addMethod() 函数，在 +resolveInstanceMethod: 中是否调用了该函数添加 IMP
 */
static void _class_resolveInstanceMethod(Class cls, SEL sel, id inst){
    if (! lookUpImpOrNil(cls->ISA(), SEL_resolveInstanceMethod, cls, NO, YES, NO)){
        // SEL_resolveInstanceMethod 方法没有实现。
        return;
    }
    
    BOOL (*msg)(Class, SEL, SEL) = (typeof(msg))objc_msgSend;
    bool resolved = msg(cls, SEL_resolveInstanceMethod, sel);//执行 SEL_resolveInstanceMethod，并获取返回值
    
    // 缓存结果(好或坏)，这样 SEL_resolveInstanceMethod 下次就不会触发。
    // +resolveInstanceMethod 增加了 self ，即 cls
    IMP imp = lookUpImpOrNil(cls, sel, inst, NO, YES, NO);
    
    if (resolved  &&  PrintResolving) {
        if (imp) {
            _objc_inform("RESOLVE: method %c[%s %s] dynamically resolved to %p",
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel), imp);
        }else {
            // 方法解析器没有添加任何东西吗?
            _objc_inform("RESOLVE: +[%s resolveInstanceMethod:%s] returned YES, but no new implementation of %c[%s %s] was found",
                         cls->nameForLogging(), sel_getName(sel), 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel));
        }
    }
}


/** 动态方法决议
 * 调用 NSObject 的 +resolveClassMethod: 类方法与 +resolveInstanceMethod: 类方法 以动态方式实现由选择器指定的实例和类方法
 * @note 该函数不会去检查指定的类 cls 中选择器sel对应的方法是否已经存在。
 */
void _class_resolveMethod(Class cls, SEL sel, id inst)
{
    if (! cls->isMetaClass()) {//不是元类
        // 尝试调用 [cls resolveInstanceMethod:sel]
        _class_resolveInstanceMethod(cls, sel, inst);
    } 
    else {
        //元类： 尝试调用 [nonMetaClass resolveClassMethod:sel] 和 [cls resolveInstanceMethod:sel]
        _class_resolveClassMethod(cls, sel, inst);
        if (!lookUpImpOrNil(cls, sel, inst, NO, YES, NO)){
            _class_resolveInstanceMethod(cls, sel, inst);
        }
    }
}


/***********************************************************************
* class_getClassMethod.  Return the class method for the specified
* class and selector.
**********************************************************************/
Method class_getClassMethod(Class cls, SEL sel)
{
    if (!cls  ||  !sel) return nil;

    return class_getInstanceMethod(cls->getMeta(), sel);
}


/***********************************************************************
* class_getInstanceVariable.  Return the named instance variable.
**********************************************************************/
Ivar class_getInstanceVariable(Class cls, const char *name)
{
    if (!cls  ||  !name) return nil;

    return _class_getVariable(cls, name);
}


/***********************************************************************
* class_getClassVariable.  Return the named class variable.
**********************************************************************/
Ivar class_getClassVariable(Class cls, const char *name)
{
    if (!cls) return nil;

    return class_getInstanceVariable(cls->ISA(), name);
}


/***********************************************************************
* gdb_objc_class_changed
* Tell gdb that a class changed. Currently used for OBJC2 ivar layouts only
* Does nothing; gdb sets a breakpoint on it.
**********************************************************************/
BREAKPOINT_FUNCTION( 
    void gdb_objc_class_changed(Class cls, unsigned long changes, const char *classname)
);


/***********************************************************************
* class_respondsToSelector.
**********************************************************************/
BOOL class_respondsToMethod(Class cls, SEL sel)
{
    OBJC_WARN_DEPRECATED;

    return class_respondsToSelector(cls, sel);
}


BOOL class_respondsToSelector(Class cls, SEL sel)
{
    return class_respondsToSelector_inst(cls, sel, nil);
}


// inst is an instance of cls or a subclass thereof, or nil if none is known.
// Non-nil inst is faster in some cases. See lookUpImpOrForward() for details.
bool class_respondsToSelector_inst(Class cls, SEL sel, id inst)
{
    IMP imp;

    if (!sel  ||  !cls) return NO;

    // Avoids +initialize because it historically did so.
    // We're not returning a callable IMP anyway.
    imp = lookUpImpOrNil(cls, sel, inst, 
                         NO/*initialize*/, YES/*cache*/, YES/*resolver*/);
    return bool(imp);
}


/***********************************************************************
* class_getMethodImplementation.
* Returns the IMP that would be invoked if [obj sel] were sent, 
* where obj is an instance of class cls.
**********************************************************************/
IMP class_lookupMethod(Class cls, SEL sel)
{
    OBJC_WARN_DEPRECATED;

    // No one responds to zero!
    if (!sel) {
        __objc_error(cls, "invalid selector (null)");
    }

    return class_getMethodImplementation(cls, sel);
}

IMP class_getMethodImplementation(Class cls, SEL sel)
{
    IMP imp;

    if (!cls  ||  !sel) return nil;

    imp = lookUpImpOrNil(cls, sel, nil, 
                         YES/*initialize*/, YES/*cache*/, YES/*resolver*/);

    // Translate forwarding function to C-callable external version
    if (!imp) {
        return _objc_msgForward;
    }

    return imp;
}

#if SUPPORT_STRET
IMP class_getMethodImplementation_stret(Class cls, SEL sel)
{
    IMP imp = class_getMethodImplementation(cls, sel);

    // Translate forwarding function to struct-returning version
    if (imp == (IMP)&_objc_msgForward /* not _internal! */) {
        return (IMP)&_objc_msgForward_stret;
    }
    return imp;
}
#endif


/***********************************************************************
* instrumentObjcMessageSends
**********************************************************************/
// Define this everywhere even if it isn't used to simplify fork() safety code.
spinlock_t objcMsgLogLock;

#if !SUPPORT_MESSAGE_LOGGING

void	instrumentObjcMessageSends(BOOL flag)
{
}

#else

bool objcMsgLogEnabled = false;
static int objcMsgLogFD = -1;

bool logMessageSend(bool isClassMethod,
                    const char *objectsClass,
                    const char *implementingClass,
                    SEL selector)
{
    char	buf[ 1024 ];

    // Create/open the log file
    if (objcMsgLogFD == (-1))
    {
        snprintf (buf, sizeof(buf), "/tmp/msgSends-%d", (int) getpid ());
        objcMsgLogFD = secure_open (buf, O_WRONLY | O_CREAT, geteuid());
        if (objcMsgLogFD < 0) {
            // no log file - disable logging
            objcMsgLogEnabled = false;
            objcMsgLogFD = -1;
            return true;
        }
    }

    // Make the log entry
    snprintf(buf, sizeof(buf), "%c %s %s %s\n",
            isClassMethod ? '+' : '-',
            objectsClass,
            implementingClass,
            sel_getName(selector));

    objcMsgLogLock.lock();
    write (objcMsgLogFD, buf, strlen(buf));
    objcMsgLogLock.unlock();

    // Tell caller to not cache the method
    return false;
}

void instrumentObjcMessageSends(BOOL flag)
{
    bool enable = flag;

    // Shortcut NOP
    if (objcMsgLogEnabled == enable)
        return;

    // If enabling, flush all method caches so we get some traces
    if (enable)
        _objc_flush_caches(Nil);

    // Sync our log file
    if (objcMsgLogFD != -1)
        fsync (objcMsgLogFD);

    objcMsgLogEnabled = enable;
}

// SUPPORT_MESSAGE_LOGGING
#endif


Class _calloc_class(size_t size)
{
    return (Class) calloc(1, size);
}

/*  获取指定类的父类
 */
Class class_getSuperclass(Class cls){
    if (!cls) return nil;
    return cls->superclass;
}

BOOL class_isMetaClass(Class cls)
{
    if (!cls) return NO;
    return cls->isMetaClass();
}


size_t class_getInstanceSize(Class cls)
{
    if (!cls) return 0;
    return cls->alignedInstanceSize();
}


/***********************************************************************
* method_getNumberOfArguments.
**********************************************************************/
unsigned int method_getNumberOfArguments(Method m)
{
    if (!m) return 0;
    return encoding_getNumberOfArguments(method_getTypeEncoding(m));
}


void method_getReturnType(Method m, char *dst, size_t dst_len)
{
    encoding_getReturnType(method_getTypeEncoding(m), dst, dst_len);
}


char * method_copyReturnType(Method m)
{
    return encoding_copyReturnType(method_getTypeEncoding(m));
}


void method_getArgumentType(Method m, unsigned int index, 
                            char *dst, size_t dst_len)
{
    encoding_getArgumentType(method_getTypeEncoding(m),
                             index, dst, dst_len);
}


char * method_copyArgumentType(Method m, unsigned int index)
{
    return encoding_copyArgumentType(method_getTypeEncoding(m), index);
}


/***********************************************************************
* _objc_constructOrFree
* Call C++ constructors, and free() if they fail.
* bytes->isa must already be set.
* cls must have cxx constructors.
* Returns the object, or nil.
**********************************************************************/
id
_objc_constructOrFree(id bytes, Class cls)
{
    assert(cls->hasCxxCtor());  // for performance, not correctness

    id obj = object_cxxConstructFromClass(bytes, cls);
    if (!obj) free(bytes);

    return obj;
}


/***********************************************************************
* _class_createInstancesFromZone
* Batch-allocating version of _class_createInstanceFromZone.
* Attempts to allocate num_requested objects, each with extraBytes.
* Returns the number of allocated objects (possibly zero), with 
* the allocated pointers in *results.
**********************************************************************/
unsigned
_class_createInstancesFromZone(Class cls, size_t extraBytes, void *zone, 
                               id *results, unsigned num_requested)
{
    unsigned num_allocated;
    if (!cls) return 0;

    size_t size = cls->instanceSize(extraBytes);

    num_allocated = 
        malloc_zone_batch_malloc((malloc_zone_t *)(zone ? zone : malloc_default_zone()), 
                                 size, (void**)results, num_requested);
    for (unsigned i = 0; i < num_allocated; i++) {
        bzero(results[i], size);
    }

    // Construct each object, and delete any that fail construction.

    unsigned shift = 0;
    bool ctor = cls->hasCxxCtor();
    for (unsigned i = 0; i < num_allocated; i++) {
        id obj = results[i];
        obj->initIsa(cls);    // fixme allow nonpointer
        if (ctor) obj = _objc_constructOrFree(obj, cls);

        if (obj) {
            results[i-shift] = obj;
        } else {
            shift++;
        }
    }

    return num_allocated - shift;    
}


/* 警告重复的类实现
 */
void inform_duplicate(const char *name, Class oldCls, Class newCls){
#if TARGET_OS_WIN32
    (DebugDuplicateClasses ? _objc_fatal : _objc_inform)
        ("Class %s is implemented in two different images.", name);
#else
    const header_info *oldHeader = _headerForClass(oldCls);
    const header_info *newHeader = _headerForClass(newCls);
    const char *oldName = oldHeader ? oldHeader->fname() : "??";
    const char *newName = newHeader ? newHeader->fname() : "??";

    (DebugDuplicateClasses ? _objc_fatal : _objc_inform)
        ("Class %s is implemented in both %s (%p) and %s (%p). "
         "One of the two will be used. Which one is undefined.",
         name, oldName, oldCls, newName, newCls);
#endif
}


const char * copyPropertyAttributeString(const objc_property_attribute_t *attrs,
                            unsigned int count)
{
    char *result;
    unsigned int i;
    if (count == 0) return strdup("");
    
#if DEBUG
    // debug build: sanitize input
    for (i = 0; i < count; i++) {
        assert(attrs[i].name);
        assert(strlen(attrs[i].name) > 0);
        assert(! strchr(attrs[i].name, ','));
        assert(! strchr(attrs[i].name, '"'));
        if (attrs[i].value) assert(! strchr(attrs[i].value, ','));
    }
#endif

    size_t len = 0;
    for (i = 0; i < count; i++) {
        if (attrs[i].value) {
            size_t namelen = strlen(attrs[i].name);
            if (namelen > 1) namelen += 2;  // long names get quoted
            len += namelen + strlen(attrs[i].value) + 1;
        }
    }

    result = (char *)malloc(len + 1);
    char *s = result;
    for (i = 0; i < count; i++) {
        if (attrs[i].value) {
            size_t namelen = strlen(attrs[i].name);
            if (namelen > 1) {
                s += sprintf(s, "\"%s\"%s,", attrs[i].name, attrs[i].value);
            } else {
                s += sprintf(s, "%s%s,", attrs[i].name, attrs[i].value);
            }
        }
    }

    // remove trailing ',' if any
    if (s > result) s[-1] = '\0';

    return result;
}

/*
  Property attribute string format:

  - Comma-separated name-value pairs. 
  - Name and value may not contain ,
  - Name may not contain "
  - Value may be empty
  - Name is single char, value follows
  - OR Name is double-quoted string of 2+ chars, value follows

  Grammar:
    attribute-string: \0
    attribute-string: name-value-pair (',' name-value-pair)*
    name-value-pair:  unquoted-name optional-value
    name-value-pair:  quoted-name optional-value
    unquoted-name:    [^",]
    quoted-name:      '"' [^",]{2,} '"'
    optional-value:   [^,]*

*/
static unsigned int 
iteratePropertyAttributes(const char *attrs, 
                          bool (*fn)(unsigned int index, 
                                     void *ctx1, void *ctx2, 
                                     const char *name, size_t nlen, 
                                     const char *value, size_t vlen), 
                          void *ctx1, void *ctx2)
{
    if (!attrs) return 0;

#if DEBUG
    const char *attrsend = attrs + strlen(attrs);
#endif
    unsigned int attrcount = 0;

    while (*attrs) {
        // Find the next comma-separated attribute
        const char *start = attrs;
        const char *end = start + strcspn(attrs, ",");

        // Move attrs past this attribute and the comma (if any)
        attrs = *end ? end+1 : end;

        assert(attrs <= attrsend);
        assert(start <= attrsend);
        assert(end <= attrsend);
        
        // Skip empty attribute
        if (start == end) continue;

        // Process one non-empty comma-free attribute [start,end)
        const char *nameStart;
        const char *nameEnd;

        assert(start < end);
        assert(*start);
        if (*start != '\"') {
            // single-char short name
            nameStart = start;
            nameEnd = start+1;
            start++;
        }
        else {
            // double-quoted long name
            nameStart = start+1;
            nameEnd = nameStart + strcspn(nameStart, "\",");
            start++;                       // leading quote
            start += nameEnd - nameStart;  // name
            if (*start == '\"') start++;   // trailing quote, if any
        }

        // Process one possibly-empty comma-free attribute value [start,end)
        const char *valueStart;
        const char *valueEnd;

        assert(start <= end);

        valueStart = start;
        valueEnd = end;

        bool more = (*fn)(attrcount, ctx1, ctx2, 
                          nameStart, nameEnd-nameStart, 
                          valueStart, valueEnd-valueStart);
        attrcount++;
        if (!more) break;
    }

    return attrcount;
}


static bool 
copyOneAttribute(unsigned int index, void *ctxa, void *ctxs, 
                 const char *name, size_t nlen, const char *value, size_t vlen)
{
    objc_property_attribute_t **ap = (objc_property_attribute_t**)ctxa;
    char **sp = (char **)ctxs;

    objc_property_attribute_t *a = *ap;
    char *s = *sp;

    a->name = s;
    memcpy(s, name, nlen);
    s += nlen;
    *s++ = '\0';
    
    a->value = s;
    memcpy(s, value, vlen);
    s += vlen;
    *s++ = '\0';

    a++;
    
    *ap = a;
    *sp = s;

    return YES;
}

                 
objc_property_attribute_t *
copyPropertyAttributeList(const char *attrs, unsigned int *outCount)
{
    if (!attrs) {
        if (outCount) *outCount = 0;
        return nil;
    }

    // Result size:
    //   number of commas plus 1 for the attributes (upper bound)
    //   plus another attribute for the attribute array terminator
    //   plus strlen(attrs) for name/value string data (upper bound)
    //   plus count*2 for the name/value string terminators (upper bound)
    unsigned int attrcount = 1;
    const char *s;
    for (s = attrs; s && *s; s++) {
        if (*s == ',') attrcount++;
    }

    size_t size = 
        attrcount * sizeof(objc_property_attribute_t) + 
        sizeof(objc_property_attribute_t) + 
        strlen(attrs) + 
        attrcount * 2;
    objc_property_attribute_t *result = (objc_property_attribute_t *) 
        calloc(size, 1);

    objc_property_attribute_t *ra = result;
    char *rs = (char *)(ra+attrcount+1);

    attrcount = iteratePropertyAttributes(attrs, copyOneAttribute, &ra, &rs);

    assert((uint8_t *)(ra+1) <= (uint8_t *)result+size);
    assert((uint8_t *)rs <= (uint8_t *)result+size);

    if (attrcount == 0) {
        free(result);
        result = nil;
    }

    if (outCount) *outCount = attrcount;
    return result;
}


static bool 
findOneAttribute(unsigned int index, void *ctxa, void *ctxs, 
                 const char *name, size_t nlen, const char *value, size_t vlen)
{
    const char *query = (char *)ctxa;
    char **resultp = (char **)ctxs;

    if (strlen(query) == nlen  &&  0 == strncmp(name, query, nlen)) {
        char *result = (char *)calloc(vlen+1, 1);
        memcpy(result, value, vlen);
        result[vlen] = '\0';
        *resultp = result;
        return NO;
    }

    return YES;
}

char *copyPropertyAttributeValue(const char *attrs, const char *name)
{
    char *result = nil;

    iteratePropertyAttributes(attrs, findOneAttribute, (void*)name, &result);

    return result;
}
