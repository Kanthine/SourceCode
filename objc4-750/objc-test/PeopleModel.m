//
//  PeopleModel.m
//  objc-test
//
//  Created by 苏沫离 on 2019/1/26.
//

#import "PeopleModel.h"

@implementation PeopleModel
+ (void)load{
    printf("=========  PeopleModel ========= +load \n");
}
@end


@implementation ManModel
+ (void)load{
    printf("=========  ManModel ========= +load \n");
    
    //自己生成并持有的对象
    NSObject *object = [[NSObject alloc] init];
    
    
    [ManModel losdaf];
    
}
@end


@implementation WomanModel

@end


@implementation ManModel(ManCategory)

+ (void)losdaf{
    printf("=========  ManCategory ========= \n");
}

@end

@implementation WomanModel(WomanCategory)

+ (void)load{
    printf("=========  WomanCategory ========= +load \n");
}

- (void)PeopleModelTestProtocol{
    
}

@end

