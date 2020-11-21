//
//  YLTimeProfiler.h
//  Hook
//
//  Created by 苏沫离 on 2020/11/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TimeProfilerFileStoreType) {
    TimeProfilerFileStoreTypeMultiple = 0,      // 保存历史追踪文件
    TimeProfilerFileStoreTypeSingle,            // 每次启动删除历史文件
};

@interface YLTimeProfiler : NSObject

/** 文件缓存方案
 * @param folderPath 缓存文件夹路径
 * @param storeType 缓存方案
 */
+ (void)setTimeProfilerFolderPath:(NSString *)folderPath storeType:(TimeProfilerFileStoreType)storeType;

/// 开始监测
+ (void)startMonitor;

/// 停止监测
+ (void)stopMonitor;

/// 设置打印最小方法执行时间 单位毫秒 默认为1毫秒
+ (void)setMinDuration:(int)minDuration;

@end

NS_ASSUME_NONNULL_END
