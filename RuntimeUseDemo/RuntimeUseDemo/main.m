//
//  main.m
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        
        NSLog(@"-------- %lx",0x000000010000B7A8 -  0x0000000100000000 + 0x00000000);
        NSLog(@"-------- %lx",0x00000a28 -  0x0000000100000000 + 0x00000000);

        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
