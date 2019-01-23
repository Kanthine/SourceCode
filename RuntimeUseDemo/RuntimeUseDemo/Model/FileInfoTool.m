//
//  FileInfoTool.m
//  RuntimeUseDemo
//
//  Created by Wanst on 2019/1/23.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import "FileInfoTool.h"
#include <mach-o/getsect.h>
@implementation FileInfoTool

/* getsectiondata() 函数从 Mach-O 文件获取某个区段数据
 * @param mhp Mach-O 文件头信息
 * @param segname 段名
 * @param sectname 段中节的名称
 * @param size 函数内部赋值所获取数据的字节数
 * @return uint8_t 返回的数据
 */
+ (void)info{
    unsigned long byteCount = 0;//所获取数据的字节数

//    getsectiondata(<#const struct mach_header_64 *mhp#>, "__DATA", "__objc_init_func", &byteCount);
    
}

@end
