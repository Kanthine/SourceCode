/* -*- mode: C++; c-basic-offset: 4; tab-width: 4 -*-
 *
 * Copyright (c) 2004-2005 Apple Computer, Inc. All rights reserved.
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

#define __STDC_LIMIT_MACROS
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <mach-o/ldsyms.h>
#include <mach-o/reloc.h>
#if __ppc__ || __ppc64__
#include <mach-o/ppc/reloc.h>
#endif
#if __x86_64__
#include <mach-o/x86_64/reloc.h>
#endif
#include "dyld.h"

#ifndef MH_PIE
#define MH_PIE 0x200000
#endif


#if __LP64__
#define macho_header            mach_header_64
#define LC_SEGMENT_COMMAND        LC_SEGMENT_64
#define macho_segment_command    segment_command_64
#define macho_section            section_64
#define RELOC_SIZE                3
#else
#define macho_header            mach_header
#define LC_SEGMENT_COMMAND        LC_SEGMENT
#define macho_segment_command    segment_command
#define macho_section            section
#define RELOC_SIZE                2
#endif

#if __x86_64__
#define POINTER_RELOC X86_64_RELOC_UNSIGNED
#else
#define POINTER_RELOC GENERIC_RELOC_VANILLA
#endif

// from dyld.cpp
namespace dyld { extern bool isRosetta(); };


/* bootstrap 启动程式
 * 启动 dyld 进入可运行状态的代码
 */
namespace dyldbootstrap {
    
    
    typedef void (*Initializer)(int argc, const char* argv[], const char* envp[], const char* apple[]);
    
    /* 对于常规可执行文件，crt代码调用dyld来运行可执行文件初始化器。
     * 对于静态可执行文件，crt直接运行初始化器。
     * dyld(应该是静态的)是动态可执行文件，需要这个hack来运行自己的初始化器。
     * 我们传递argc，argv等，以防 libc.a 使用这些参数
     */
    static void runDyldInitializers(const struct macho_header* mh, intptr_t slide, int argc, const char* argv[], const char* envp[], const char* apple[]){
        const uint32_t cmd_count = mh->ncmds;
        const struct load_command* const cmds = (struct load_command*)(((char*)mh)+sizeof(macho_header));
        const struct load_command* cmd = cmds;
        for (uint32_t i = 0; i < cmd_count; ++i) {
            switch (cmd->cmd) {
                case LC_SEGMENT_COMMAND:
                {
                    const struct macho_segment_command* seg = (struct macho_segment_command*)cmd;
                    const struct macho_section* const sectionsStart = (struct macho_section*)((char*)seg + sizeof(struct macho_segment_command));
                    const struct macho_section* const sectionsEnd = &sectionsStart[seg->nsects];
                    for (const struct macho_section* sect=sectionsStart; sect < sectionsEnd; ++sect) {
                        const uint8_t type = sect->flags & SECTION_TYPE;
                        if ( type == S_MOD_INIT_FUNC_POINTERS ){
                            Initializer* inits = (Initializer*)(sect->addr + slide);
                            const uint32_t count = sect->size / sizeof(uintptr_t);
                            for (uint32_t i=0; i < count; ++i) {
                                Initializer func = inits[i];
                                func(argc, argv, envp, apple);
                            }
                        }
                    }
                }
                    break;
            }
            cmd = (const struct load_command*)(((char*)cmd)+cmd->cmdsize);
        }
    }
    
    /* 如果内核没有在其首选地址加载dyld，我们需要修正应用：在__DATA段的各个初始化部分
     * rebase 是系统为了解决动态库虚拟内存地址冲突，在加载动态库时进行的基地址重定位操作
     *
     */
    static void rebaseDyld(const struct macho_header* mh, intptr_t slide)
    {
        // rebase 非懒加载指针（所有都指向dyld内部，因为dyld不使用共享库）并获得有关指针放入 dyld
        const uint32_t cmd_count = mh->ncmds;//获取load_command 的个数，记录在cmd_count 中
        const struct load_command* const cmds = (struct load_command*)(((char*)mh)+sizeof(macho_header));
        const struct load_command* cmd = cmds;
        const struct macho_segment_command* linkEditSeg = NULL;
#if __x86_64__
        const struct macho_segment_command* firstWritableSeg = NULL;
#endif
        const struct dysymtab_command* dynamicSymbolTable = NULL;
        for (uint32_t i = 0; i < cmd_count; ++i) {
            switch (cmd->cmd) {
                case LC_SEGMENT_COMMAND:
                {
                    const struct macho_segment_command* seg = (struct macho_segment_command*)cmd;
                    if ( strcmp(seg->segname, "__LINKEDIT") == 0 )
                        linkEditSeg = seg;
                    const struct macho_section* const sectionsStart = (struct macho_section*)((char*)seg + sizeof(struct macho_segment_command));
                    const struct macho_section* const sectionsEnd = &sectionsStart[seg->nsects];
                    for (const struct macho_section* sect=sectionsStart; sect < sectionsEnd; ++sect) {
                        const uint8_t type = sect->flags & SECTION_TYPE;
                        if ( type == S_NON_LAZY_SYMBOL_POINTERS ) {
                            // rebase 非懒加载指针（所有都指向dyld内部，因为dyld不使用共享库）
                            const uint32_t pointerCount = sect->size / sizeof(uintptr_t);
                            uintptr_t* const symbolPointers = (uintptr_t*)(sect->addr + slide);
                            for (uint32_t j=0; j < pointerCount; ++j) {
                                symbolPointers[j] += slide;
                            }
                        }
                    }
#if __x86_64__
                    if ( (firstWritableSeg == NULL) && (seg->initprot & VM_PROT_WRITE) )
                        firstWritableSeg = seg;
#endif
                }
                    break;
                case LC_DYSYMTAB:
                    dynamicSymbolTable = (struct dysymtab_command *)cmd;
                    break;
            }
            cmd = (const struct load_command*)(((char*)cmd)+cmd->cmdsize);
        }
        
        // 使用 reloc 重设所有随机数据指针的基
#if __x86_64__
        const uintptr_t relocBase = firstWritableSeg->vmaddr + slide;// 根据 slide 获取基础偏移地址
#else
        const uintptr_t relocBase = (uintptr_t)mh;
#endif
        
        //获取relocsStart与relocsEnd信息；然后遍历 relocsStart 到 relocsEnd 之前的地址，所有地址都加上 slide
        const relocation_info* const relocsStart = (struct relocation_info*)(linkEditSeg->vmaddr + slide + dynamicSymbolTable->locreloff - linkEditSeg->fileoff);
        const relocation_info* const relocsEnd = &relocsStart[dynamicSymbolTable->nlocrel];
        for (const relocation_info* reloc=relocsStart; reloc < relocsEnd; ++reloc) {
#if __ppc__ || __ppc64__ || __i36__
            if ( (reloc->r_address & R_SCATTERED) != 0 )
                throw "scattered relocation in dyld";
#endif
            if ( reloc->r_length != RELOC_SIZE )
                throw "relocation in dyld has wrong size";
            
            if ( reloc->r_type != POINTER_RELOC )
                throw "relocation in dyld has wrong type";
            
            // 按 dyld 偏移量更新指针
            *((uintptr_t*)(reloc->r_address + relocBase)) += slide;
        }
    }
    
    
    // 出于某种原因，内核使用 __TEXT 和 __LINKEDIT 可写加载 dyld
    // rdar://problem/3702311
    static void segmentProtectDyld(const struct macho_header* mh, intptr_t slide)
    {
        const uint32_t cmd_count = mh->ncmds;
        const struct load_command* const cmds = (struct load_command*)(((char*)mh)+sizeof(macho_header));
        const struct load_command* cmd = cmds;
        for (uint32_t i = 0; i < cmd_count; ++i) {
            switch (cmd->cmd) {
                case LC_SEGMENT_COMMAND:
                {
                    const struct macho_segment_command* seg = (struct macho_segment_command*)cmd;
                    vm_address_t addr = seg->vmaddr + slide;
                    vm_size_t size = seg->vmsize;
                    const bool setCurrentPermissions = false;
                    vm_protect(mach_task_self(), addr, size, setCurrentPermissions, seg->initprot);
                    //dyld::log("dyld: segment %s, 0x%08X -> 0x%08X, set to %d\n", seg->segname, addr, addr+size-1, seg->initprot);
                }
                    break;
            }
            cmd = (const struct load_command*)(((char*)cmd)+cmd->cmdsize);
        }
        
    }
    
    
    // 将主程序重新映射到一个新的随机地址
    static const struct mach_header* randomizeExecutableLoadAddress(const struct mach_header* orgMH, uintptr_t* appsSlide){
#if __ppc__
        // don't slide PIE programs running under rosetta
        if ( dyld::isRosetta() )
            return orgMH;
#endif
        // count segments
        uint32_t segCount = 0;
        const uint32_t cmd_count = orgMH->ncmds;
        const struct load_command* const cmds = (struct load_command*)(((char*)orgMH)+sizeof(macho_header));
        const struct load_command* cmd = cmds;
        for (uint32_t i = 0; i < cmd_count; ++i) {
            if ( cmd->cmd == LC_SEGMENT_COMMAND ) {
                const struct macho_segment_command* segCmd = (struct macho_segment_command*)cmd;
                // page-zero and custom stacks don't move
                if ( (strcmp(segCmd->segname, "__PAGEZERO") != 0) && (strcmp(segCmd->segname, "__UNIXSTACK") != 0) )
                    ++segCount;
            }
            cmd = (const struct load_command*)(((char*)cmd)+cmd->cmdsize);
        }
        
        // make copy of segment info
        macho_segment_command segs[segCount];
        uint32_t index = 0;
        uintptr_t highestAddressUsed = 0;
        uintptr_t lowestAddressUsed = UINTPTR_MAX;
        cmd = cmds;
        for (uint32_t i = 0; i < cmd_count; ++i) {
            if ( cmd->cmd == LC_SEGMENT_COMMAND ) {
                const struct macho_segment_command* segCmd = (struct macho_segment_command*)cmd;
                if ( (strcmp(segCmd->segname, "__PAGEZERO") != 0) && (strcmp(segCmd->segname, "__UNIXSTACK") != 0) ) {
                    segs[index++] = *segCmd;
                    if ( (segCmd->vmaddr + segCmd->vmsize) > highestAddressUsed )
                        highestAddressUsed = ((segCmd->vmaddr + segCmd->vmsize) + 4095) & -4096;
                    if ( segCmd->vmaddr < lowestAddressUsed )
                        lowestAddressUsed = segCmd->vmaddr;
                    // do nothing if kernel has already randomized load address
                    if ( (strcmp(segCmd->segname, "__TEXT") == 0) && (segCmd->vmaddr != (uintptr_t)orgMH) )
                        return orgMH;
                }
            }
            cmd = (const struct load_command*)(((char*)cmd)+cmd->cmdsize);
        }
        
        // choose a random new base address
#if __LP64__
        uintptr_t highestAddressPossible = highestAddressUsed + 0x100000000ULL;
#else
        uintptr_t highestAddressPossible = 0x80000000;
#endif
        uintptr_t sizeNeeded = highestAddressUsed-lowestAddressUsed;
        if ( (highestAddressPossible-sizeNeeded) < highestAddressUsed ) {
            // new and old segments will overlap
            // need better algorithm for remapping
            // punt and don't re-map
            return orgMH;
        }
        uintptr_t possibleRange = (highestAddressPossible-sizeNeeded) - highestAddressUsed;
        uintptr_t newBaseAddress = highestAddressUsed + ((arc4random() % possibleRange) & -4096);
        
        vm_address_t addr = newBaseAddress;
        // 保留新地址范围
        if ( vm_allocate(mach_task_self(), &addr, sizeNeeded, VM_FLAGS_FIXED) == KERN_SUCCESS ) {
            // copy each segment to new address
            for (uint32_t i = 0; i < segCount; ++i) {
                uintptr_t newSegAddress = segs[i].vmaddr - lowestAddressUsed + newBaseAddress;
                if ( (vm_copy(mach_task_self(), segs[i].vmaddr, segs[i].vmsize, newSegAddress) != KERN_SUCCESS)
                    || (vm_protect(mach_task_self(), newSegAddress, segs[i].vmsize, true, segs[i].maxprot) != KERN_SUCCESS)
                    || (vm_protect(mach_task_self(), newSegAddress, segs[i].vmsize, false, segs[i].initprot) != KERN_SUCCESS) ) {
                    // can't copy so dealloc new region and run with original base address
                    vm_deallocate(mach_task_self(), newBaseAddress, sizeNeeded);
                    dyld::warn("could not relocate position independent exectable\n");
                    return orgMH;
                }
            }
            // 取消原始段的映射
            vm_deallocate(mach_task_self(), lowestAddressUsed, highestAddressUsed-lowestAddressUsed);
            
            // 使用新映射的可执行文件运行
            *appsSlide = newBaseAddress - lowestAddressUsed;
            return (const struct mach_header*)newBaseAddress;
        }
        
        // 不能得到新的范围，所以不要移动到随机地址
        return orgMH;
    }
    
    
    extern "C" void dyld_exceptions_init(const struct macho_header*, uintptr_t slide); // in dyldExceptions.cpp
    extern "C" void mach_init();
    
    //
    // _pthread_keys is partitioned in a lower part that dyld will use; libSystem
    // will use the upper part.  We set __pthread_tsd_first to 1 as the start of
    // the lower part.  Libc will take #1 and c++ exceptions will take #2.  There
    // is one free key=3 left.
    //
    extern "C" {
        extern int __pthread_tsd_first;
        extern void _pthread_keys_init();
    }
    
    
    /* start() 函数启动 dyld，该功能通常由 dyld 和 crt 共同完成；但是在 dyld 中，必须手动执行此操作。
     *
     * @param appsMachHeader  一个 App 的 Mach-O 头文件，有了它，相当于知道了 App 的所有的内容
     * @param argc   环境变量的数组的元素数量
     * @param argv[] 环境变量的数组
     * @param slide 基地址偏移量
     */
    uintptr_t start(const struct mach_header* appsMachHeader, int argc, const char* argv[], intptr_t slide)
    {
        
        /* _mh_dylinker_header 是由静态链接器(ld)定义的魔法符号
         * 链接编辑器定义的符号 _MH_DYLINKER_SYM 的值是 mach 头在 Mach-O dylinker 文件类型中的地址。
         * 除了 MH_DYLINKER 文件类型之外，它不会出现在其它任何文件类型中。
         * 即使header不是任何 section 的一部分，符号类型也是 N_SECT 符号。
         * 该符号对于它所在的动态链接器中的代码是私有的。
         *
         */
        const struct macho_header* dyldsMachHeader =  (const struct macho_header*)(((char*)&_mh_dylinker_header)+slide);
        
        // 如果内核必须移动 dyld，我们需要解决加载受影响的的位置；在使用全局变量之前，我们必须这样做
        if ( slide != 0 ) {
            // rebase 是系统为了解决动态库虚拟内存地址冲突，在加载动态库时进行的基地址重定位操作
            rebaseDyld(dyldsMachHeader, slide);// 矫正rebaseDyld
        }
        
        uintptr_t appsSlide = 0;
        
        // 将 pthread 键设置为 dyld 范围
        __pthread_tsd_first = 1;
        _pthread_keys_init();
        
        // 允许 C++ 异常在 dyld 内部工作
        dyld_exceptions_init(dyldsMachHeader, slide);
        
        // 允许 dyld 使用 mach 消息传递
        mach_init();// mach 初始化
        
        // 在段上设置保护(必须在 mach_init() 之后执行)
        segmentProtectDyld(dyldsMachHeader, slide);
        
        // 内核将 env 指针设置在 agv 数组的末尾
        const char** envp = &argv[argc+1];
        
        // 内核将 apple 指针设置为envp数组的末尾
        const char** apple = envp;
        while(*apple != NULL) { ++apple; }
        ++apple;
        
        // 在 dyld 中运行所有 C++ 初始化器
        runDyldInitializers(dyldsMachHeader, slide, argc, argv, envp, apple);
        
        // 如果主可执行文件被链接 -pie，那么随机分配它的加载地址
        if ( appsMachHeader->flags & MH_PIE )
            appsMachHeader = randomizeExecutableLoadAddress(appsMachHeader, &appsSlide);
        
        // 现在我们已经完成了对dyld的启动，调用dyld的main
        return dyld::_main(appsMachHeader, appsSlide, argc, argv, envp, apple);//调用dyld::_main 函数
    }
    
    
    
    
} // end of namespace





