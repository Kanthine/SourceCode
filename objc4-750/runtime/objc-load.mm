/*
 * Copyright (c) 1999-2001, 2004-2007 Apple Inc.  All Rights Reserved.
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

/*
 *    objc-load.m
 *    Copyright 1988-1996, NeXT Software, Inc.
 *    Author:    s. naroff
 *
 */

#include "objc-private.h"
#include "objc-load.h"

#if !__OBJC2__  &&  !TARGET_OS_WIN32

extern void (*callbackFunction)( Class, Category );


/* 加载模块
 *
 * 注意:加载并不是真正的线程安全。如果一个负载消息递归调用objc_loadModules()，这两个集合都将被正确加载，但是如果原始调用者调用objc_unloadModules()，它可能会卸载错误的模块。
 * 注意：加载不是真正的线程安全。如果 load 消息以递归方式调用objc_loadModules()，则两个集合都将正确加载，但如果原始调用者调用objc_unloadModules（），则可能会卸载错误的模块。
 * 如果 load 消息调用 objc_unloadModules()，那么它将卸载当前加载的模块，这可能会导致崩溃。
 *
 * 错误处理仍然有些粗略。如果我们在链接类或分类时遇到错误，我们将无法正确恢复。
 *
 * 我删除了锁定类哈希表的尝试，因为这引入了很难删除的死锁。唯一可能遇到麻烦的方法是，如果一个线程加载一个模块，而另一个线程在加载完成之前尝试访问加载的类（使用objc_lookUpClass）。
 */
int objc_loadModule(char *moduleName, void (*class_callback) (Class, Category), int *errorCode)
{
    int                                successFlag = 1;
    int                                locErrorCode;
    NSObjectFileImage                objectFileImage;
    NSObjectFileImageReturnCode        code;
    
    // 我们不需要到处检查
    if (errorCode == NULL)
        errorCode = &locErrorCode;
    
    if (moduleName == NULL)
    {
        *errorCode = NSObjectFileImageInappropriateFile;
        return 0;
    }
    
    if (_dyld_present () == 0)
    {
        *errorCode = NSObjectFileImageFailure;
        return 0;
    }
    
    callbackFunction = class_callback;
    code = NSCreateObjectFileImageFromFile (moduleName, &objectFileImage);
    if (code != NSObjectFileImageSuccess)
    {
        *errorCode = code;
        return 0;
    }
    
    if (NSLinkModule(objectFileImage, moduleName, NSLINKMODULE_OPTION_RETURN_ON_ERROR) == NULL) {
        NSLinkEditErrors error;
        int errorNum;
        const char *fileName, *errorString;
        NSLinkEditError(&error, &errorNum, &fileName, &errorString);
        // 这些错误可能与objc_loadModule在其他故障情况下返回的其他错误重叠。
        *errorCode = error;
        return 0;
    }
    callbackFunction = NULL;
    
    
    return successFlag;
}

/**********************************************************************************
 * objc_loadModules.
 **********************************************************************************/
/* Lock for dynamic loading and unloading. */
//    static OBJC_DECLARE_LOCK (loadLock);


long    objc_loadModules   (char *            modlist[],
                            void *            errStream,
                            void            (*class_callback) (Class, Category),
                            headerType **    hdr_addr,
                            char *            debug_file)
{
    char **                modules;
    int                    code;
    int                    itWorked;
    
    if (modlist == 0)
        return 0;
    
    for (modules = &modlist[0]; *modules != 0; modules++)
    {
        itWorked = objc_loadModule (*modules, class_callback, &code);
        if (itWorked == 0)
        {
            //if (errStream)
            //    NXPrintf ((NXStream *) errStream, "objc_loadModules(%s) code = %d\n", *modules, code);
            return 1;
        }
        
        if (hdr_addr)
            *(hdr_addr++) = 0;
    }
    
    return 0;
}

/*注意:卸载并不是真正的线程安全。如果卸载消息调用objc_loadModules()或objc_unloadModules()，那么当前对objc_unloadModules()的调用可能会卸载错误的内容。
  */

long    objc_unloadModules (void *            errStream,
                            void            (*unload_callback) (Class, Category))
{
    headerType *    header_addr = 0;
    int errflag = 0;
    
    // TODO: to make unloading work, should get the current header
    // 要使卸载工作，应该得到当前header
    if (header_addr)
    {
        ; // TODO: 卸载当前header
    }
    else
    {
        errflag = 1;
    }
    
    return errflag;
}

#endif

