/*
 * Copyright (c) 1999-2003, 2006-2007 Apple Inc.  All Rights Reserved.
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
/*	maptable.h
	Scalable hash table of mappings.
	Bertrand, August 1990
	Copyright 1990-1996 NeXT Software, Inc.
*/

#ifndef _OBJC_MAPTABLE_H_
#define _OBJC_MAPTABLE_H_

#ifndef _OBJC_PRIVATE_H_
#   define OBJC_MAP_AVAILABILITY                             \
    __OSX_DEPRECATED(10.0, 10.1, "NXMapTable is deprecated") \
    __IOS_UNAVAILABLE __TVOS_UNAVAILABLE                     \
    __WATCHOS_UNAVAILABLE __BRIDGEOS_UNAVAILABLE
#else
#   define OBJC_MAP_AVAILABILITY
#endif

#include <objc/objc.h>

__BEGIN_DECLS

#pragma mark - 结构定义

/* 映射哈希表 NXMapTable
 * 存储任意的键值对：键和值必须是指针或整数，客户端负责分配/释放这些数据。提供了一个deallocation回调。
 * 作为表现良好的可扩展数据结构，哈希表在开始变满时会增加一倍，从而保证了平均固定时间访问和线性大小。
 * 该映射表是可变的；
 * 可以通过弱引用来持有keys和values，所以当key或者value被deallocated的时候，所存储的实体也会被移除；
 * 该映射表可以在添加value的时候对value进行复制；
 * 和 NSHashTable 类似，NSMapTable可以随意的存储指针，并且利用指针的唯一性来进行对比和重复检查。
 */
typedef struct _NXMapTable {
    /* private data structure; may change */
    const struct _NXMapTablePrototype	* _Nonnull prototype;
    unsigned	count;//存储元素的数量
    unsigned	nbBucketsMinusOne;
    void	* _Nullable buckets;//真正用来存储数据的数组。
} NXMapTable OBJC_MAP_AVAILABILITY;

//_NXMapTablePrototype 存储了一些构建哈希表必要的函数指针如：hash、isEqual 和 free 的函数指针
typedef struct _NXMapTablePrototype {
    unsigned	(* _Nonnull hash)(NXMapTable * _Nonnull,const void * _Nullable key);//用于获取数据的哈希的函数指针
    int		(* _Nonnull isEqual)(NXMapTable * _Nonnull,const void * _Nullable key1,
                                 const void * _Nullable key2);//判断两个数据是否相等的函数指针
    void	(* _Nonnull free)(NXMapTable * _Nonnull,void * _Nullable key,
                              void * _Nullable value);//释放数据的函数指针；
    int		style; //预留作日后扩展之用;目前为 0；
} NXMapTablePrototype OBJC_MAP_AVAILABILITY;
    
    /* invariants assumed by the implementation: 
	A - key != -1
	B - key1 == key2 => hash(key1) == hash(key2)
	    when key varies over time, hash(key) must remain invariant
	    e.g. if string key, the string must not be changed
	C - isEqual(key1, key2) => key1 == key2
    */

//NX_MAPNOTAKEY(-1)在内部用作标记，因此键必须始终与-1不同。
#define NX_MAPNOTAKEY	((void * _Nonnull)(-1))

#pragma mark - 功能函数

//初始化哈希表
OBJC_EXPORT NXMapTable * _Nonnull NXCreateMapTableFromZone(NXMapTablePrototype prototype,unsigned capacity, void * _Nullable z)OBJC_MAP_AVAILABILITY;

OBJC_EXPORT NXMapTable * _Nonnull NXCreateMapTable(NXMapTablePrototype prototype, unsigned capacity)OBJC_MAP_AVAILABILITY;
    /* capacity is only a hint; 0 creates a small table */

//释放哈希表 NXMapTable
OBJC_EXPORT void NXFreeMapTable(NXMapTable * _Nonnull table)OBJC_MAP_AVAILABILITY;
    /* call free for each pair, and recovers table */
	
OBJC_EXPORT void
NXResetMapTable(NXMapTable * _Nonnull table)
    OBJC_MAP_AVAILABILITY;
    /* free each pair; keep current capacity */

OBJC_EXPORT BOOL
NXCompareMapTables(NXMapTable * _Nonnull table1, NXMapTable * _Nonnull table2)
    OBJC_MAP_AVAILABILITY;
    /* Returns YES if the two sets are equal (each member of table1 in table2, and table have same size) */

OBJC_EXPORT unsigned
NXCountMapTable(NXMapTable * _Nonnull table)
    OBJC_MAP_AVAILABILITY;
    /* current number of data in table */



/* 获取指定哈希表中的指定键，并将哈希表中对应的值赋值给 value
 * @param table 指定的哈希表
 * @param key 指定的键
 * @param value 要写入键值的内存地址；如果找到键，则设置值
 * @return 如果该哈希表中存在键key，则返回哈希表中的键 key ；否则返回 NX_MAPNOTAKEY
 */
OBJC_EXPORT void * _Nullable NXMapMember(NXMapTable * _Nonnull table, const void * _Nullable key,void * _Nullable * _Nonnull value) OBJC_MAP_AVAILABILITY;



OBJC_EXPORT void * _Nullable NXMapGet(NXMapTable * _Nonnull table, const void * _Nullable key)
    OBJC_MAP_AVAILABILITY;
    /* return original corresponding value or NULL.  When NULL need be stored as value, NXMapMember can be used to test for presence */
	
OBJC_EXPORT void * _Nullable
NXMapInsert(NXMapTable * _Nonnull table, const void * _Nullable key,
            const void * _Nullable value)
    OBJC_MAP_AVAILABILITY;
    /* override preexisting pair; Return previous value or NULL. */
	
OBJC_EXPORT void * _Nullable
NXMapRemove(NXMapTable * _Nonnull table, const void * _Nullable key)
    OBJC_MAP_AVAILABILITY;
    /* previous value or NULL is returned */
	
/* Iteration over all elements of a table consists in setting up an iteration state and then to progress until all entries have been visited.  An example of use for counting elements in a table is:
    unsigned	count = 0;
    const MyKey	*key;
    const MyValue	*value;
    NXMapState	state = NXInitMapState(table);
    while(NXNextMapState(table, &state, &key, &value)) {
	count++;
    }
*/

typedef struct {int index;} NXMapState OBJC_MAP_AVAILABILITY;
    /* callers should not rely on actual contents of the struct */

OBJC_EXPORT NXMapState
NXInitMapState(NXMapTable * _Nonnull table)
    OBJC_MAP_AVAILABILITY;

OBJC_EXPORT int
NXNextMapState(NXMapTable * _Nonnull table, NXMapState * _Nonnull state,
               const void * _Nullable * _Nonnull key,
               const void * _Nullable * _Nonnull value)
    OBJC_MAP_AVAILABILITY;
    /* returns 0 when all elements have been visited */

/***************	Conveniences		***************/

OBJC_EXPORT const NXMapTablePrototype NXPtrValueMapPrototype
    OBJC_MAP_AVAILABILITY;
    /* hashing is pointer/integer hashing;
      isEqual is identity;
      free is no-op. */
OBJC_EXPORT const NXMapTablePrototype NXStrValueMapPrototype
    OBJC_MAP_AVAILABILITY;
    /* hashing is string hashing;
      isEqual is strcmp;
      free is no-op. */
OBJC_EXPORT const NXMapTablePrototype NXObjectMapPrototype
    OBJC2_UNAVAILABLE;
    /* for objects; uses methods: hash, isEqual:, free, all for key. */

__END_DECLS

#endif /* _OBJC_MAPTABLE_H_ */
