//
//  MyModel.m
//  objc-test
//
//  Created by Wanst on 2019/1/25.
//

#import "MyModel.h"

@implementation MyModel

+ (void)load{
    printf("MyModel ========= +load \n");
}

+ (void)initialize{
    printf("MyModel ========= +initialize \n");
}

- (void)logName{
    printf("%s:%s \n",__func__,self.name);
}

@end
