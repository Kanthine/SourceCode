//
//  ViewController.m
//  Hook
//
//  Created by 苏沫离 on 2020/11/19.
//

#import "ViewController.h"
#import "YLTimeProfiler.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = UIColor.whiteColor;
    
    [self doMethod];
    
    NSLog(@"NSHomeDirectory --- %@",NSHomeDirectory());
}

- (void)doMethod {
    for (int i=0; i<10; i++) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [self sleep];
        });
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (int i=0; i<10; i++) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                [self sleep];
            });
        }
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [YLTimeProfiler stopMonitor];
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [YLTimeProfiler startMonitor];
        for (int i=0; i<10; i++) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                [self sleep];
            });
        }
    });
}

- (void)sleep {
    [NSThread sleepForTimeInterval:2];
}

@end
