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
