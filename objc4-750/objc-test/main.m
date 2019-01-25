//
//  main.m
//  objc-test
//
//  Created by GongCF on 2018/12/16.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "MyModel.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MyModel *model = [[MyModel alloc] init];
        model.name = @"Hello Word!";
        [model logName];
        NSLog(@"model === %p",model);
    }
    return 0;
}
