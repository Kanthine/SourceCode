//
//  FatherModel.h
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FatherModelDelegate <NSObject>

- (void)logFatherModelDelegate;

+ (void)logFatherModelDelegate1;

@end

@interface FatherModel : NSObject
{
    float _height;
    float _weight;
}
@property (nonatomic ,strong) NSString *name;
@property (nonatomic ,strong ,class) NSString *className;

#pragma mark - 根据类名称获取指定的类

+ (void)getClassWithName:(NSString *)name;
+ (void)getMetaClassWithName:(NSString *)name;
+ (void)getRequiredClassWithName:(NSString *)name;
+ (void)lookUpClassWithName:(NSString *)name;
+ (void)getAllRegisterClass;
+ (void)getClassList;
//获取指定数量的已注册类列表
+ (void)getRandomClassListWithCount:(int)count;
//获取指定类的所有子类
+ (void)getAllSubclassWithSupercalss:(Class)superclass;

#pragma mark - 获取类的变量

+ (void)class_getInstanceVariable:(NSString *)ivarName;
+ (void)class_getClassVariable:(NSString *)ivarName;
+ (void)getAllIvarList;

#pragma mark - 获取类的方法


@end

NS_ASSUME_NONNULL_END
