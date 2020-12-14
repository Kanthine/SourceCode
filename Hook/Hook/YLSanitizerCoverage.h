//
//  YLSanitizerCoverage.h
//  Hook
//
//  Created by 苏沫离 on 2020/11/30.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN


/** 二进制重排，减少 缺页中断 的耗时
 * 1、获取  data.order 文件
 *    clang 自带的静态插桩工具：SanitizerCoverage
 *          -fsanitize-coverage=func,trace-pc-guard
 *  2、拿到函数符号后，二进制重排
 */
@interface YLSanitizerCoverage : NSObject


+ (void)getDataOrder;
/** .order 文件缓存方案
 * @param filePath 缓存文件路径
 */
+ (void)getDataOrderFilePath:(NSString *)filePath;

@end

NS_ASSUME_NONNULL_END

 /*
  
  二进制重排是为了解决什么问题?
  
  1、虚拟内存与物理内存

  1.1、早起的物理内存

  1.2、虚拟内存工作原理

  2、内存分页

  2.1、内存分页原理

  3、二进制重排

  3.1、概述

  3.2、二进制重排优化原理
  
  3.3、如何检测 page fault
  
  3.4、如何重排二进制？
  
  3.5、如何查看自己重排成功了没有?
  
  3.6、如何检测自己启动时刻需要调用的所有方法？
  
  LLVM 内置了一个简单的代码覆盖率检测（SanitizeRcoverage）。
  它在函数级、基本块级和边缘级插入对用户定义函数的调用；提供了这些回调的默认实现，并实现了简单的覆盖率报告和可视化。


  
  */
