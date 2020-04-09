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
        
        MyModel *model = [[MyModel alloc] init];
        printf("model === %p \n",model);
        printf("model === %p \n",&model);
        MyModel *model2 = model;
        model = nil;
        __weak MyModel *weakModel = [[MyModel alloc] init];
        printf("weakModel === %p \n",weakModel);
        printf("weakModel === %p \n",&weakModel);
        
//        weakModel = [[MyModel alloc] init];
        weakModel.name = @"Hello Word!";
        [weakModel logName];
        
//        weakModel = nil;
    }
    return 0;
}
