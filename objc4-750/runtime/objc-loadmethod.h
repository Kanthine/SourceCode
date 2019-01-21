/*
 * Copyright (c) 2004-2006 Apple Inc.  All Rights Reserved.
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
* objc-loadmethod.h
* 支持 +load 方法
**********************************************************************/

#ifndef _OBJC_LOADMETHOD_H
#define _OBJC_LOADMETHOD_H

#include "objc-private.h"

__BEGIN_DECLS

/* 将类添加到数组 loadable_classes 中
 * @param cls 要添加的类
 * @note 该函数每执行一次，loadable_classes_used 都会加 1 ；
 * @note loadable_classes_used 用于记录这个方法的调用次数，相当于数组 loadable_classes 的元素个数
 * @note 类cls刚刚连接起来：如果它实现了一个+load方法，那么为+load调用它。
 */
extern void add_class_to_loadable_list(Class cls);

/* 将分类添加到数组 loadable_categories 中
 * @param cat 要添加的分类
 * @note 该函数每执行一次，loadable_categories_used 都会加 1 ；
 * @note loadable_categories_used 用于记录这个方法的调用次数，相当于数组 loadable_categories 的元素个数
 * @note 类cls刚刚连接起来：如果它实现了一个+load方法，那么为+load调用它。
 */
extern void add_category_to_loadable_list(Category cat);

/* 从数组 loadable_classes 中移除指定类
 * @param cls 要移除的类
 * @note 类 cls 以前可能是可加载的，但现在它不再可加载(因为它的镜像是未映射的)。
 */
extern void remove_class_from_loadable_list(Class cls);

/* 从数组 loadable_categories 中移除指定分类
 * @param cls 要移除的分类
 * @note 分类 cat 以前可能是可加载的，但现在它不再可加载(因为它的镜像是未映射的)。
 */
extern void remove_category_from_loadable_list(Category cat);

/* 遍历数组 loadable_classes 与数组 loadable_categories
 * 调用所有挂起(未注册)的类和分类+load方法
 */
extern void call_load_methods(void);

__END_DECLS

#endif
