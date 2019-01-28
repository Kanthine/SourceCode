//
//  main.m
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "FatherModel.h"


static __attribute__((constructor)) void run_test(void){
    printf("Hello Word!! \n");
    printf("Hello Girl!! \n");
}


int main(int argc, char * argv[]) {
    @autoreleasepool {
        
        NSLog(@"RW_REALIZED|RW_REALIZING -------- %x",1<<31|1<<19);
        NSLog(@"RO_META-------- %x",1<<0);
        NSLog(@"RO_ROOT-------- %x",1<<1);
        NSLog(@"RW_REALIZED-------- %x",1<<31);

        
        NSLog(@"-------- %lx",0x000000010000B9A8 -  0x0000000100000000 + 0x00000000);//0xB9A8
        NSLog(@"-------- %lx",0xDA83000001000000  -  0x0000000100000000 + 0x00000000);//0xda82ffff01000000

        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
