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
        __weak MyModel *weakModel = model;
        weakModel.name = @"Hello Word!";
        [weakModel logName];
        printf("model === %p \n",weakModel);
    }
    return 0;
}
