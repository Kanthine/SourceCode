/*
 * Copyright (c) 2012 Apple Inc.  All Rights Reserved.
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

#if __OBJC2__

#include "objc-private.h"
#include "objc-cache.h"

#if SUPPORT_PREOPT // 在 iOS 系统上必须支持 dyld 共享缓存优化
static const objc_selopt_t *builtins = NULL;
#endif


static size_t SelrefCount = 0; //选择器的总数量，用于创建哈希表的大小
//选择器名称的哈希表：关系映射表
static NXMapTable *namedSelectors;

static SEL search_builtins(const char *key);

/* 初始化选择器列表并注册内部使用的选择器
 */
void sel_init(size_t selrefCount){
    // save this value for later
    SelrefCount = selrefCount;
    
#if SUPPORT_PREOPT // 在 iOS 系统上必须支持 dyld 共享缓存优化
    //初始化选择器列表
    builtins = preoptimizedSelectors();
    
    if (PrintPreopt  &&  builtins) {
        uint32_t occupied = builtins->occupied;//占有的
        uint32_t capacity = builtins->capacity;//容量
        
        _objc_inform("PREOPTIMIZATION: using selopt at %p", builtins);
        _objc_inform("PREOPTIMIZATION: %u selectors", occupied);
        _objc_inform("PREOPTIMIZATION: %u/%u (%u%%) hash table occupancy",occupied, capacity,(unsigned)(occupied/(double)capacity*100));
    }
#endif
    
    //注册内部使用的选择器
    
#define s(x) SEL_##x = sel_registerNameNoLock(#x, NO)
#define t(x,y) SEL_##y = sel_registerNameNoLock(#x, NO)
    
    mutex_locker_t lock(selLock);
    
    s(load);
    s(initialize);
    t(resolveInstanceMethod:, resolveInstanceMethod);
    t(resolveClassMethod:, resolveClassMethod);
    t(.cxx_construct, cxx_construct);
    t(.cxx_destruct, cxx_destruct);
    s(retain);
    s(release);
    s(autorelease);
    s(retainCount);
    s(alloc);
    t(allocWithZone:, allocWithZone);
    s(dealloc);
    s(copy);
    s(new);
    t(forwardInvocation:, forwardInvocation);
    t(_tryRetain, tryRetain);
    t(_isDeallocating, isDeallocating);
    s(retainWeakReference);
    s(allowsWeakReference);
    
#undef s
#undef t
}

/* 根据选择器名称创建一个选择器
 * @param copy 是否拷贝选择器名称
 */
static SEL sel_alloc(const char *name, bool copy){
    selLock.assertLocked();
    return (SEL)(copy ? strdupIfMutable(name) : name);
}


const char *sel_getName(SEL sel){
    if (!sel) return "<null selector>";
    return (const char *)(const void*)sel;
}


BOOL sel_isMapped(SEL sel){
    if (!sel) return NO;
    
    const char *name = (const char *)(void *)sel;
    
    if (sel == search_builtins(name)) return YES;
    
    mutex_locker_t lock(selLock);
    if (namedSelectors) {
        return (sel == (SEL)NXMapGet(namedSelectors, name));
    }
    return false;
}


static SEL search_builtins(const char *name){
#if SUPPORT_PREOPT
    if (builtins) return (SEL)builtins->get(name);
#endif
    return nil;
}

/* 向 Objective-C 运行时系统注册一个方法，将方法名映射到选择器，并返回选择器值。
 * @param name 指向 C 字符串的指针,表示传递要注册的方法的名称。
 * @param lock 布尔值，指示该函数内部是否上锁
 * @param copy 是否拷贝选择器名称
 * @note 在将方法添加到类定义之前，必须向Objective-C运行时系统注册方法名，以获得方法的选择器。
 *       如果方法名已经注册，则该函数只返回选择器。
 */
static SEL __sel_registerName(const char *name, bool shouldLock, bool copy){
    SEL result = 0;
    
    if (shouldLock) selLock.assertUnlocked();
    else selLock.assertLocked();
    
    if (!name) return (SEL)0;
    
    result = search_builtins(name);
    if (result) return result;
    
    conditional_mutex_locker_t lock(selLock, shouldLock);
    if (namedSelectors) {//如果在哈比表中找到该选择器，则返回
        result = (SEL)NXMapGet(namedSelectors, name);
    }
    if (result) return result;
    
    // No match. Insert.
    
    if (!namedSelectors) {//如果哈希表还没有创建，则创建一个哈希表
        namedSelectors = NXCreateMapTable(NXStrValueMapPrototype, (unsigned)SelrefCount);
    }
    if (!result) {
        //创建一个选择器，并将创建的选择器插入哈希表 namedSelectors
        result = sel_alloc(name, copy);
        NXMapInsert(namedSelectors, sel_getName(result), result);
    }
    
    return result;
}

/* 向Objective-C运行时系统注册一个方法，将方法名映射到选择器，并返回选择器值。
 * @param name 指向 C 字符串的指针,表示传递要注册的方法的名称。
 * @param copy 是否复制选择器名称 name（没有创建sel调用sel_alloc()时使用）
 * @note 在将方法添加到类定义之前，必须向Objective-C运行时系统注册方法名，以获得方法的选择器。
 *       如果方法名已经注册，则该函数只返回选择器。
 */
SEL sel_registerName(const char *name) {
    return __sel_registerName(name, 1, 1);     // YES lock, YES copy
}
SEL sel_registerNameNoLock(const char *name, bool copy) {
    return __sel_registerName(name, 0, copy);  // NO lock, maybe copy
}


// 2001/1/24
// 这个函数的大多数用法(如果没有找到，通常返回NULL)都没有检查NULL，因此，实际上，永远不会返回NULL

/* 向Objective-C运行时系统注册一个方法名。
 * @param 指向 C 字符串的指针,表示传递要注册的方法的名称。
 * @note 该方法的实现与sel_registerName的实现相同。
 */
SEL sel_getUid(const char *name) {
    return __sel_registerName(name, 2, 1);  // YES lock, YES copy
}

/* 判断两个选择器是否相等。
 */
BOOL sel_isEqual(SEL lhs, SEL rhs){
    return bool(lhs == rhs);
}


#endif

