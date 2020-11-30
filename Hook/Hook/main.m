//
//  main.m
//  Hook
//
//  Created by 苏沫离 on 2020/11/19.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "YLTimeProfiler.h"

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    
//    [YLTimeProfiler setMinDuration:3];
//    [YLTimeProfiler startMonitor];
    
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
