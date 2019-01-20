/*
 * Copyright (c) 2008 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_GDB_H
#define _OBJC_GDB_H

/* 
 * WARNING  DANGER  HAZARD  BEWARE  EEK
 * 
 * Everything in this file is for debugger and developer tool use only.
 * These will change in arbitrary OS updates and in unpredictable ways.
 * When your program breaks, you get to keep both pieces.
 */

#ifdef __APPLE_API_PRIVATE

#ifndef _OBJC_PRIVATE_H_
#   define _OBJC_PRIVATE_H_
#endif
#include <stdint.h>
#include <objc/hashtable.h>
#include <objc/maptable.h>

__BEGIN_DECLS


/***********************************************************************
* Class pointer preflighting
**********************************************************************/

// 如果cls是一个有效的类，则返回cls，否则崩溃。
OBJC_EXPORT Class _Nonnull
gdb_class_getClass(Class _Nonnull cls)
#if __OBJC2__
    OBJC_AVAILABLE(10.6, 3.1, 9.0, 1.0, 2.0);
#else
    OBJC_AVAILABLE(10.7, 3.1, 9.0, 1.0, 2.0);
#endif

// 与 gdb_class_getClass(object_getClass(cls)) 相同.
OBJC_EXPORT Class _Nonnull gdb_object_getClass(id _Nullable obj)
    OBJC_AVAILABLE(10.7, 4.3, 9.0, 1.0, 2.0);


/***********************************************************************
* Class lists for heap.
**********************************************************************/

#if __OBJC2__

//哈希表：将类名映射到类，仅用于使用中的类
OBJC_EXPORT NXMapTable * _Nullable gdb_objc_realized_classes
    OBJC_AVAILABLE(10.6, 3.1, 9.0, 1.0, 2.0);

#else

// Hashes Classes, for all known classes. Custom prototype.
OBJC_EXPORT NXHashTable * _Nullable _objc_debug_class_hash
    __OSX_AVAILABLE(10.2) 
    __IOS_UNAVAILABLE __TVOS_UNAVAILABLE
    __WATCHOS_UNAVAILABLE __BRIDGEOS_UNAVAILABLE;

#endif


/***********************************************************************
* Non-pointer isa
**********************************************************************/

#if __OBJC2__

// Extract isa pointer from an isa field.
// (Class)(isa & mask) == class pointer
OBJC_EXPORT const uintptr_t objc_debug_isa_class_mask
    OBJC_AVAILABLE(10.10, 7.0, 9.0, 1.0, 2.0);

// Extract magic cookie from an isa field.
// (isa & magic_mask) == magic_value
OBJC_EXPORT const uintptr_t objc_debug_isa_magic_mask
    OBJC_AVAILABLE(10.10, 7.0, 9.0, 1.0, 2.0);
OBJC_EXPORT const uintptr_t objc_debug_isa_magic_value
    OBJC_AVAILABLE(10.10, 7.0, 9.0, 1.0, 2.0);

// Use indexed ISAs for targets which store index of the class in the ISA.
// This index can be used to index the array of classes.
OBJC_EXPORT const uintptr_t objc_debug_indexed_isa_magic_mask;
OBJC_EXPORT const uintptr_t objc_debug_indexed_isa_magic_value;

// Then these are used to extract the index from the ISA.
OBJC_EXPORT const uintptr_t objc_debug_indexed_isa_index_mask;
OBJC_EXPORT const uintptr_t objc_debug_indexed_isa_index_shift;

// And then we can use that index to get the class from this array.  Note
// the size is provided so that clients can ensure the index they get is in
// bounds and not read off the end of the array.
OBJC_EXPORT Class _Nullable objc_indexed_classes[];

// When we don't have enough bits to store a class*, we can instead store an
// index in to this array.  Classes are added here when they are realized.
// Note, an index of 0 is illegal.
OBJC_EXPORT uintptr_t objc_indexed_classes_count;

// Absolute symbols for some of the above values are in objc-abi.h.

#endif


/***********************************************************************
* Class structure decoding
**********************************************************************/
#if __OBJC2__

// Mask for the pointer from class struct to class rw data.
// Other bits may be used for flags.
// Use 0x00007ffffffffff8UL or 0xfffffffcUL when this variable is unavailable.
OBJC_EXPORT const uintptr_t objc_debug_class_rw_data_mask
    OBJC_AVAILABLE(10.13, 11.0, 11.0, 4.0, 2.0);

#endif


/***********************************************************************
* Tagged Pointer 解码
**********************************************************************/
#if __OBJC2__

// 基础的 tagged pointers (7 个类, 60位 净负荷).

// if (obj & mask) obj is a tagged pointer object
/* Tagged Pointer 的标志：高位优先（MSB）时 64 位的最左边一定是 1；
 * 指定指针与 objc_debug_taggedpointer_mask 做 & 运算，可以判断该指针是否是 Tagged Pointer
 */
OBJC_EXPORT uintptr_t objc_debug_taggedpointer_mask OBJC_AVAILABLE(10.9, 7.0, 9.0, 1.0, 2.0);

//Tagged Pointer 指针混淆器：用于保护 Tagged Pointer 上的数据
OBJC_EXPORT uintptr_t objc_debug_taggedpointer_obfuscator OBJC_AVAILABLE(10.14, 12.0, 12.0, 5.0, 3.0);


// Tagged Pointer 的标志位置：高位优先（MSB）时值为 60
OBJC_EXPORT unsigned int objc_debug_taggedpointer_slot_shift
    OBJC_AVAILABLE(10.9, 7.0, 9.0, 1.0, 2.0);
OBJC_EXPORT uintptr_t objc_debug_taggedpointer_slot_mask
    OBJC_AVAILABLE(10.9, 7.0, 9.0, 1.0, 2.0);

// class = classes[tag_slot]
OBJC_EXPORT Class _Nullable objc_debug_taggedpointer_classes[]
    OBJC_AVAILABLE(10.9, 7.0, 9.0, 1.0, 2.0);

// payload = (decoded_obj << payload_lshift) >> payload_rshift
// Payload signedness is determined by the signedness of the right-shift.
OBJC_EXPORT unsigned int objc_debug_taggedpointer_payload_lshift
    OBJC_AVAILABLE(10.9, 7.0, 9.0, 1.0, 2.0);
OBJC_EXPORT unsigned int objc_debug_taggedpointer_payload_rshift
    OBJC_AVAILABLE(10.9, 7.0, 9.0, 1.0, 2.0);


// 扩展的 tagged pointers (255 classes, 52位 净负荷).

/* 如果使用基本的tagged pointer模式来查询扩展的tagged pointers，那么它的isa可能nil，也可能是类__NSUnrecognizedTaggedPointer。
 */

// if (ext_mask != 0  &&  (decoded_obj & ext_mask) == ext_mask)
//   obj is a ext tagged pointer object
OBJC_EXPORT uintptr_t objc_debug_taggedpointer_ext_mask
    OBJC_AVAILABLE(10.12, 10.0, 10.0, 3.0, 2.0);

// ext_tag_slot = (obj >> ext_slot_shift) & ext_slot_mask
OBJC_EXPORT unsigned int objc_debug_taggedpointer_ext_slot_shift
    OBJC_AVAILABLE(10.12, 10.0, 10.0, 3.0, 2.0);
OBJC_EXPORT uintptr_t objc_debug_taggedpointer_ext_slot_mask
    OBJC_AVAILABLE(10.12, 10.0, 10.0, 3.0, 2.0);

// class = ext_classes[ext_tag_slot]
OBJC_EXPORT Class _Nullable objc_debug_taggedpointer_ext_classes[]
    OBJC_AVAILABLE(10.12, 10.0, 10.0, 3.0, 2.0);

// payload = (decoded_obj << ext_payload_lshift) >> ext_payload_rshift
// Payload signedness is determined by the signedness of the right-shift.
OBJC_EXPORT unsigned int objc_debug_taggedpointer_ext_payload_lshift
    OBJC_AVAILABLE(10.12, 10.0, 10.0, 3.0, 2.0);
OBJC_EXPORT unsigned int objc_debug_taggedpointer_ext_payload_rshift
    OBJC_AVAILABLE(10.12, 10.0, 10.0, 3.0, 2.0);

#endif

__END_DECLS

// APPLE_API_PRIVATE
#endif

// _OBJC_GDB_H
#endif
