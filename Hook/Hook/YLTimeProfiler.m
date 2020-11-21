//
//  YLTimeProfiler.m
//  Hook
//
//  Created by 苏沫离 on 2020/11/19.
//

#import "YLTimeProfiler.h"
#include "YLMsgSend.h"

static TimeProfilerFileStoreType kTimeProfilerStoreType = 0;
static int kTimeProfilerStarted = 0;
static NSString *kTimeProfilerFolderPath = @"";


@implementation YLTimeProfiler

+ (void)setTimeProfilerFolderPath:(NSString *)folderPath storeType:(TimeProfilerFileStoreType)storeType{
    kTimeProfilerFolderPath = folderPath;
    kTimeProfilerStoreType = storeType;
}

+ (void)startMonitor{
    if (kTimeProfilerStarted != 0) {
        yl_msgSend_resume_print();
        return;
    }
    kTimeProfilerStarted = 1;
    
    if (kTimeProfilerFolderPath.length < 1) {
        NSString *rootdir = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)[0];
        kTimeProfilerFolderPath = [rootdir stringByAppendingPathComponent:@"TimeProfiler"];
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:kTimeProfilerFolderPath] &&
        kTimeProfilerStoreType == TimeProfilerFileStoreTypeSingle) {
        [fileManager removeItemAtPath:kTimeProfilerFolderPath error:nil];
    }
    if (![fileManager fileExistsAtPath:kTimeProfilerFolderPath]) {
        [fileManager createDirectoryAtPath:kTimeProfilerFolderPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSTimeInterval timeInterval = NSDate.date.timeIntervalSince1970;
    NSString *log_name = [NSString stringWithFormat:@"trace_%.f.json", timeInterval];
    char *log_path = (char *)[[kTimeProfilerFolderPath stringByAppendingPathComponent:log_name] UTF8String];
    yl_msgSend_start(log_path);
}

+ (void)stopMonitor{
    yl_msgSend_stop_print();
}

+ (void)setMinDuration:(int)minDuration {
    method_min_duration = minDuration * 1000;
}

@end
