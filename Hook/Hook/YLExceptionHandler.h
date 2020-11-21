//
//  YLExceptionHandler.h
//  Hook
//
//  Created by 苏沫离 on 2020/11/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YLExceptionHandler : NSObject
/**
 保存崩溃日志到沙盒中的Library/Caches/Crash目录下
 
 @param log 崩溃日志的内容
 @param fileName 保存的文件名
 */
+ (void)saveCrashLog:(NSString *)log fileName:(NSString *)fileName;

/**
 获取崩溃日志的目录

 @return 崩溃日志的目录
 */
+ (NSString *)crashDirectory;

@end




@interface YLSignalExceptionHandler : NSObject

+ (void)registerHandler;

@end


@interface YLUncaughtExceptionHandler : NSObject

+ (void)registerHandler;

@end


NS_ASSUME_NONNULL_END
