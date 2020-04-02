//
//  MyModel.m
//  objc-test
//
//  Created by 苏沫离 on 2019/1/25.
//

#import "MyModel.h"

@implementation MyModel

+ (void)initialize{
    printf("=========  MyModel ========= +initialize \n");
}

- (void)dealloc{
    printf("%s : %p \n",__func__,self);
}

- (void)logName{
    printf("%s:%s \n",__func__,self.name);
}

@end
