/*
 * Copyright (c) 2005-2006 Apple Inc.  All Rights Reserved.
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

#ifndef _OBJC_INITIALIZE_H
#define _OBJC_INITIALIZE_H

#include "objc-private.h"

__BEGIN_DECLS

/* 声明的结构
 * 用于线程存储的数据 _objc_pthread_data结构的一个成员：用于存储正在初始化的 Class
 */
struct _objc_initializing_classes;

extern void _class_initialize(Class cls);

/* 释放指定初始化列表使用的内存。
 * 列表的任何部分都可以是nil。
 * 从 _objc_pthread_destroyspecific() 函数调用.
 */
extern void _destroyInitializingClassList(struct _objc_initializing_classes *list);

/* 判断当前线程是否正在初始化指定的类
 */
extern bool _thisThreadIsInitializingClass(Class cls);

__END_DECLS

#endif
