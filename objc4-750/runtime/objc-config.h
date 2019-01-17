/*
 * Copyright (c) 1999-2002, 2005-2008 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_CONFIG_H_
#define _OBJC_CONFIG_H_

#include <TargetConditionals.h>

// Define __OBJC2__ for the benefit of our asm files.
#ifndef __OBJC2__
#   if TARGET_OS_OSX  &&  !TARGET_OS_IOSMAC  &&  __i386__
        // old ABI
#   else
#       define __OBJC2__ 1
#   endif
#endif

// Avoid the !NDEBUG double negative.
#if !NDEBUG
#   define DEBUG 1
#else
#   define DEBUG 0
#endif

#if !TARGET_OS_OSX
#   define SUPPORT_GC_COMPAT 0//iOS 不兼容 Garbage Collection
#else
#   define SUPPORT_GC_COMPAT 1//兼容 Garbage Collection
#endif

// Define SUPPORT_ZONES=1 to enable malloc zone support in NXHashTable.
#if !(TARGET_OS_OSX || TARGET_OS_IOSMAC)
#   define SUPPORT_ZONES 0
#else
#   define SUPPORT_ZONES 1
#endif

// Define SUPPORT_MOD=1 to use the mod operator in NXHashTable and objc-sel-set
#if defined(__arm__)
#   define SUPPORT_MOD 0
#else
#   define SUPPORT_MOD 1
#endif

// 定义 SUPPORT_PREOPT=1 以启用 dyld 共享缓存优化
#if TARGET_OS_WIN32  ||  TARGET_OS_SIMULATOR
#   define SUPPORT_PREOPT 0
#else
#   define SUPPORT_PREOPT 1 // 在 iOS 系统上必须支持 dyld 共享缓存优化
#endif

#if !(__OBJC2__  &&  __LP64__)
#   define SUPPORT_TAGGED_POINTERS 0 //禁用 tagged pointer 对象
#else
#   define SUPPORT_TAGGED_POINTERS 1 //启用 tagged pointer 对象
#endif

// 定义 SUPPORT_MSB_TAGGED_POINTERS 来使用MSB作为 tagged pointer 的标记，而不是LSB。确保在objc-internal.h 中编辑 tagged pointer SPI。
#if !SUPPORT_TAGGED_POINTERS  ||  (TARGET_OS_OSX || TARGET_OS_IOSMAC)
#   define SUPPORT_MSB_TAGGED_POINTERS 0
#else
#   define SUPPORT_MSB_TAGGED_POINTERS 1
#endif

// Define SUPPORT_INDEXED_ISA=1 on platforms that store the class in the isa 
// field as an index into a class table.
// Note, keep this in sync with any .s files which also define it.
// Be sure to edit objc-abi.h as well.
#if __ARM_ARCH_7K__ >= 2  ||  (__arm64__ && !__LP64__)
#   define SUPPORT_INDEXED_ISA 1
#else
#   define SUPPORT_INDEXED_ISA 0
#endif

// Define SUPPORT_PACKED_ISA=1 on platforms that store the class in the isa 
// field as a maskable pointer with other data around it.
#if (!__LP64__  ||  TARGET_OS_WIN32  ||  \
     (TARGET_OS_SIMULATOR && !TARGET_OS_IOSMAC))
#   define SUPPORT_PACKED_ISA 0
#else
#   define SUPPORT_PACKED_ISA 1
#endif

// Define SUPPORT_NONPOINTER_ISA=1 on any platform that may store something
// in the isa field that is not a raw pointer.
#if !SUPPORT_INDEXED_ISA  &&  !SUPPORT_PACKED_ISA
#   define SUPPORT_NONPOINTER_ISA 0
#else
#   define SUPPORT_NONPOINTER_ISA 1
#endif

// Define SUPPORT_FIXUP=1 to repair calls sites for fixup dispatch.
// Fixup messaging itself is no longer supported.
// Be sure to edit objc-abi.h as well (objc_msgSend*_fixup)
#if !(defined(__x86_64__) && (TARGET_OS_OSX || TARGET_OS_SIMULATOR))
#   define SUPPORT_FIXUP 0
#else
#   define SUPPORT_FIXUP 1
#endif

// Define SUPPORT_ZEROCOST_EXCEPTIONS to use "zero-cost" exceptions for OBJC2.
// Be sure to edit objc-exception.h as well (objc_add/removeExceptionHandler)
#if !__OBJC2__  ||  (defined(__arm__)  &&  __USING_SJLJ_EXCEPTIONS__)
#   define SUPPORT_ZEROCOST_EXCEPTIONS 0
#else
#   define SUPPORT_ZEROCOST_EXCEPTIONS 1
#endif

// Define SUPPORT_ALT_HANDLERS if you're using zero-cost exceptions 
// but also need to support AppKit's alt-handler scheme
// Be sure to edit objc-exception.h as well (objc_add/removeExceptionHandler)
#if !SUPPORT_ZEROCOST_EXCEPTIONS  ||  !TARGET_OS_OSX
#   define SUPPORT_ALT_HANDLERS 0
#else
#   define SUPPORT_ALT_HANDLERS 1
#endif

// Define SUPPORT_RETURN_AUTORELEASE to optimize autoreleased return values
#if TARGET_OS_WIN32
#   define SUPPORT_RETURN_AUTORELEASE 0
#else
#   define SUPPORT_RETURN_AUTORELEASE 1
#endif

// Define SUPPORT_STRET on architectures that need separate struct-return ABI.
#if defined(__arm64__)
#   define SUPPORT_STRET 0
#else
#   define SUPPORT_STRET 1
#endif

// Define SUPPORT_MESSAGE_LOGGING to enable NSObjCMessageLoggingEnabled
#if !TARGET_OS_OSX
#   define SUPPORT_MESSAGE_LOGGING 0
#else
#   define SUPPORT_MESSAGE_LOGGING 1
#endif

// OBJC_INSTRUMENTED controls whether message dispatching is dynamically
// monitored.  Monitoring introduces substantial overhead.
// NOTE: To define this condition, do so in the build command, NOT by
// uncommenting the line here.  This is because objc-class.h heeds this
// condition, but objc-class.h can not #include this file (objc-config.h)
// because objc-class.h is public and objc-config.h is not.
//#define OBJC_INSTRUMENTED

#endif
