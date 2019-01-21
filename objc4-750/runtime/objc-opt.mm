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

/* objc-opt.mm 对 dyld 共享缓存中的优化进行管理
 */

#include "objc-private.h"



#if !SUPPORT_PREOPT
#pragma mark - 适配：当前系统不支持 dyld 共享缓存优化

struct objc_selopt_t;

bool isPreoptimized(void) {
    return false;
}

bool noMissingWeakSuperclasses(void) {
    return false;
}

bool header_info::isPreoptimized() const{
    return false;
}

objc_selopt_t *preoptimizedSelectors(void) {
    return nil;
}

Protocol *getPreoptimizedProtocol(const char *name){
    return nil;
}

unsigned int getPreoptimizedClassUnreasonableCount(){
    return 0;
}

Class getPreoptimizedClass(const char *name){
    return nil;
}

Class* copyPreoptimizedClasses(const char *name, int *outCount){
    *outCount = 0;
    return nil;
}

bool sharedRegionContains(const void *ptr){
    return false;
}

header_info *preoptimizedHinfoForHeader(const headerType *mhdr){
    return nil;
}

header_info_rw *getPreoptimizedHeaderRW(const struct header_info *const hdr){
    return nil;
}

void preopt_init(void){
    disableSharedCacheOptimizations();
    
    if (PrintPreopt) {
        _objc_inform("PREOPTIMIZATION: is DISABLED (not supported on ths platform)");
    }
}

#else
#pragma mark - 适配：在 iOS 系统上必须支持 dyld 共享缓存优化

#include <objc-shared-cache.h>

using objc_opt::objc_stringhash_offset_t;
using objc_opt::objc_protocolopt_t;
using objc_opt::objc_clsopt_t;
using objc_opt::objc_headeropt_ro_t;
using objc_opt::objc_headeropt_rw_t;
using objc_opt::objc_opt_t;

__BEGIN_DECLS

/* preopt: runtime 使用的实际 opt ( nil 或 &_objc_opt_data )
 * _objc_opt_data: opt数据可能是由 dyld 写入
 * opt 被初始化为 ~0，以便在 preopt_init() 之前检测错误的使用
 */
static const objc_opt_t *opt = (objc_opt_t *)~0;
static uintptr_t shared_cache_start;//共享缓存的开始地址
static uintptr_t shared_cache_end;//共享缓存的结束地址：如果一个指针在 start 与 end 之间，则位于共享缓存内
static bool preoptimized;//是否预优化

extern const objc_opt_t _objc_opt_data;  // in __TEXT, __objc_opt_ro

/* 判断是否是预优化
 * @return 如果我们有一个有效的优化共享缓存，返回YES。
 */
bool isPreoptimized(void) {
    return preoptimized;
}

/* 如果共享缓存没有任何缺少 weak 父类的类，则返回YES。
 */
bool noMissingWeakSuperclasses(void) {
    if (!preoptimized) return NO;  // 可能丢失了weak父类
    return opt->flags & objc_opt::NoMissingWeakSuperclasses;
}

/* 如果该镜像的 dyld 共享缓存优化有效，则返回YES。
 */
bool header_info::isPreoptimized() const{
    if (!preoptimized) return NO;// 由于某些原因禁用了预优化
    if (!info()->optimizedByDyld()) return NO;// 镜像不是来自共享缓存，或不在共享缓存内
    return YES;
}

//获取预优化的选择器
objc_selopt_t *preoptimizedSelectors(void) {
    return opt ? opt->selopt() : nil;
}

/* 根据指定名称，获取预优化的协议
 */
Protocol *getPreoptimizedProtocol(const char *name){
    objc_protocolopt_t *protocols = opt ? opt->protocolopt() : nil;
    if (!protocols) return nil;
    return (Protocol *)protocols->getProtocol(name);
}


unsigned int getPreoptimizedClassUnreasonableCount(){
    objc_clsopt_t *classes = opt ? opt->clsopt() : nil;
    if (!classes) return 0;
    
    // This is an overestimate: each set of duplicates
    // gets double-counted in `capacity` as well.
    return classes->capacity + classes->duplicateCount();
}

/* 根据指定名称，获取预优化的类
 */
Class getPreoptimizedClass(const char *name)
{
    objc_clsopt_t *classes = opt ? opt->clsopt() : nil;
    if (!classes) return nil;
    
    void *cls;
    void *hi;
    uint32_t count = classes->getClassAndHeader(name, cls, hi);
    if (count == 1  &&  ((header_info *)hi)->isLoaded()) {
        // exactly one matching class, and its image is loaded
        return (Class)cls;
    }
    else if (count > 1) {
        // more than one matching class - find one that is loaded
        void *clslist[count];
        void *hilist[count];
        classes->getClassesAndHeaders(name, clslist, hilist);
        for (uint32_t i = 0; i < count; i++) {
            if (((header_info *)hilist[i])->isLoaded()) {
                return (Class)clslist[i];
            }
        }
    }
    
    // no match that is loaded
    return nil;
}


Class* copyPreoptimizedClasses(const char *name, int *outCount){
    *outCount = 0;
    
    objc_clsopt_t *classes = opt ? opt->clsopt() : nil;
    if (!classes) return nil;
    
    void *cls;
    void *hi;
    uint32_t count = classes->getClassAndHeader(name, cls, hi);
    if (count == 0) return nil;
    
    Class *result = (Class *)calloc(count, sizeof(Class));
    if (count == 1  &&  ((header_info *)hi)->isLoaded()) {
        // exactly one matching class, and its image is loaded
        result[(*outCount)++] = (Class)cls;
        return result;
    }
    else if (count > 1) {
        // more than one matching class - find those that are loaded
        void *clslist[count];
        void *hilist[count];
        classes->getClassesAndHeaders(name, clslist, hilist);
        for (uint32_t i = 0; i < count; i++) {
            if (((header_info *)hilist[i])->isLoaded()) {
                result[(*outCount)++] = (Class)clslist[i];
            }
        }
        
        if (*outCount == 0) {
            // found multiple classes with that name, but none are loaded
            free(result);
            result = nil;
        }
        return result;
    }
    
    // no match that is loaded
    return nil;
}

/* 判断指定的指针是否位于共享缓存中
 * @param ptr 指定的指针
 * @return 如果指定指针位于共享缓存内，则返回 YES。
 */
bool sharedRegionContains(const void *ptr){
    uintptr_t address = (uintptr_t)ptr;
    return shared_cache_start <= address && address < shared_cache_end;
}

//
namespace objc_opt {
    struct objc_headeropt_ro_t {//只读
        uint32_t count;
        uint32_t entsize;
        header_info headers[0];  // 以 mhdr 地址排序
        
        header_info *get(const headerType *mhdr){
            assert(entsize == sizeof(header_info));
            
            int32_t start = 0;
            int32_t end = count;
            while (start <= end) {//二分法查找数组 headers 中的指定元素
                int32_t i = (start+end)/2;
                header_info *hi = headers+i;
                if (mhdr == hi->mhdr()) return hi;
                else if (mhdr < hi->mhdr()) end = i-1;
                else start = i+1;
            }
#if DEBUG
            for (uint32_t i = 0; i < count; i++) {
                header_info *hi = headers+i;
                if (mhdr == hi->mhdr()) {
                    _objc_fatal("failed to find header %p (%d/%d)", mhdr, i, count);
                }
            }
#endif
            return nil;//没有找到，则返回 nil
        }
    };
    
    struct objc_headeropt_rw_t {//读写
        uint32_t count;
        uint32_t entsize;
        header_info_rw headers[0]; //以 mhdr 地址排序
    };
};


header_info *preoptimizedHinfoForHeader(const headerType *mhdr){
#if !__OBJC2__
    // 修复旧ABI共享缓存没有正确准备这些
    return nil;
#endif
    
    objc_headeropt_ro_t *hinfos = opt ? opt->headeropt_ro() : nil;
    if (hinfos) return hinfos->get(mhdr);
    else return nil;
}

/* 获取预优化的 header_info_rw
 * @param hdr
 */
header_info_rw *getPreoptimizedHeaderRW(const struct header_info *const hdr){
#if !__OBJC2__
    // fixme old ABI shared cache doesn't prepare these properly
    return nil;
#endif
    
    objc_headeropt_ro_t *hinfoRO = opt ? opt->headeropt_ro() : nil;
    objc_headeropt_rw_t *hinfoRW = opt ? opt->headeropt_rw() : nil;
    if (!hinfoRO || !hinfoRW) {//都不能为空
        _objc_fatal("preoptimized header_info missing for %s (%p %p %p)",hdr->fname(), hdr, hinfoRO, hinfoRW);
    }
    int32_t index = (int32_t)(hdr - hinfoRO->headers);
    assert(hinfoRW->entsize == sizeof(header_info_rw));
    return &hinfoRW->headers[index];
}


/* 共享内存优化
 */
void preopt_init(void){
    // 获取共享缓存占用的内存区域。
    size_t length;
    const void *start = _dyld_get_shared_cache_range(&length);
    if (start) {
        shared_cache_start = (uintptr_t)start;
        shared_cache_end = shared_cache_start + length;
    } else {
        shared_cache_start = shared_cache_end = 0;
    }
    
    // `opt` not set at compile time in order to detect too-early usage
    const char *failure = nil;
    opt = &_objc_opt_data;
    
    if (DisablePreopt) {
        // OBJC_DISABLE_PREOPTIMIZATION 设置
        // 如果 opt->version != VERSION 那么将承担风险。
        failure = "(by OBJC_DISABLE_PREOPTIMIZATION)";
    }
    else if (opt->version != objc_opt::VERSION) {
        // 这不该发生。可能忘记编辑 objc-sel-table.s.
        // 如果 dyld 确实编写了错误的优化版本，必须停下来，因为我们二进制 dyld 有何改动。
        _objc_fatal("bad objc preopt version (want %d, got %d)",objc_opt::VERSION, opt->version);
    }
    else if (!opt->selopt()  ||  !opt->headeropt_ro()) {
        // One of the tables is missing.
        failure = "(dyld shared cache is absent or out of date)";
    }
    
    if (failure) {
        // 所有预先优化的选择器引用无效。
        preoptimized = NO;
        opt = nil;
        disableSharedCacheOptimizations();
        
        if (PrintPreopt) {
            _objc_inform("PREOPTIMIZATION: is DISABLED %s", failure);
        }
    }
    else {
        // 由 dyld 共享缓存写入的有效优化数据
        preoptimized = YES;
        
        if (PrintPreopt) {
            _objc_inform("PREOPTIMIZATION: is ENABLED (version %d)", opt->version);
        }
    }
}


__END_DECLS

// SUPPORT_PREOPT
#endif

