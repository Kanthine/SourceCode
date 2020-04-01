//
//  main.m
//  objc-test
//
//  Created by 苏沫离 on 2018/12/16.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "MyModel.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        printf("\n\n objc-test ----- main \n");
                
        __weak MyModel *weakModel = [[MyModel alloc] init];
        
//        weakModel = [[MyModel alloc] init];
        weakModel.name = @"Hello Word!";
        [weakModel logName];
        printf("model === %p \n",weakModel);
        
        weakModel = nil;
    }
    return 0;
}
