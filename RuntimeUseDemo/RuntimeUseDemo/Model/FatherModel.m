//
//  FatherModel.m
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import "FatherModel.h"

@implementation FatherModel

+ (void)load{
    NSLog(@"%s",__func__);
    
}

#pragma mark - 根据类名称获取指定的类

+ (void)getClassWithName:(NSString *)name{
    Class theClass = objc_getClass(name.UTF8String);
    NSLog(@"类名是 %s",class_getName(theClass));
}

+ (void)lookUpClassWithName:(NSString *)name{
    Class theMetaClass = objc_lookUpClass(name.UTF8String);
    NSLog(@"类名是 %s",class_getName(theMetaClass));
}

//运行时异常：objc[3652]: link error: class 'SonModel_' not found.
+ (void)getRequiredClassWithName:(NSString *)name{
    Class theMetaClass = objc_getRequiredClass(name.UTF8String);
    NSLog(@"类名是 %s",class_getName(theMetaClass));
}

+ (void)getMetaClassWithName:(NSString *)name{
    Class theMetaClass = objc_getMetaClass(name.UTF8String);
    NSLog(@"类名是 %s",class_getName(theMetaClass));
}


//获取所有注册类
+ (void)getAllRegisterClass{
    unsigned int outCount = 0;
    Class *list = objc_copyClassList(&outCount);
    for (int i = 0; i < outCount; i ++) {
        Class class = list[i];
        NSLog(@"%d 的类名是 %s",i,class_getName(class));
    }
    free(list);
}

+ (void)getClassList{
    Class *buffer = NULL;
    //buffer 为 NULL 且 bufferCount 为 0； 此时可以获取：已注册的所有类的总数量
    int bufferCount = objc_getClassList(buffer, 0);
    if (bufferCount > 0 ){
        buffer = (Class *)realloc(buffer, sizeof(Class) * bufferCount); //分配内存空间
        bufferCount = objc_getClassList(buffer, bufferCount);//将类写入分配好的内存空间buffer
        for (int i = 0; i < bufferCount; i ++) {
            Class class = buffer[i];
            NSLog(@"%d 的类名是 %s",i,class_getName(class));
        }
        free(buffer);
    }
}

+ (void)getRandomClassListWithCount:(int)count{
    Class *buffer = (Class *)realloc(NULL, sizeof(Class) * count); //分配内存空间
    objc_getClassList(buffer, count);//将类写入分配好的内存空间buffer
    for (int i = 0; i < count; i ++) {
        Class class = buffer[i];
        NSLog(@"%d 的类名是 %s",i,class_getName(class));
    }
    free(buffer);
}

//获取指定类的所有子类
+ (void)getAllSubclassWithSupercalss:(Class)superclass{
    unsigned int outCount = 0;
    Class *list = objc_copyClassList(&outCount);
    for (int i = 0; i < outCount; i ++) {
        Class class = list[i];
        if (class_getSuperclass(class) == superclass) {
            NSLog(@"%s 的第 %d 个子类的类名是 %s",class_getName(superclass),i,class_getName(class));
        }
    }
    free(list);
}

#pragma mark - 获取类的变量

/* class_getInstanceVariable() 函数 与 class_getClassVariable() 函数 会去获取父类的变量
 * class_copyIvarList() 函数 不会去获取父类的变量
 */

+ (void)class_getInstanceVariable:(NSString *)ivarName{
    Ivar theIvar = class_getInstanceVariable(self.class, ivarName.UTF8String);
    NSLog(@"%s 的变量是 %s",class_getName(self.class),ivar_getName(theIvar));
}

+ (void)class_getClassVariable:(NSString *)ivarName{
    Ivar theIvar = class_getClassVariable(self.class, ivarName.UTF8String);
    NSLog(@"%s 的变量是 %s",class_getName(self.class),ivar_getName(theIvar));
}

+ (void)getAllIvarList{
    unsigned int outCount = 0;
    Ivar *ivarList = class_copyIvarList(self.class, &outCount);
    for (int i = 0; i < outCount; i ++) {
        Ivar ivar = ivarList[i];
        NSLog(@"%s 的 %d 的变量名是 %s",class_getName(self.class),i,ivar_getName(ivar));
    }
    free(ivarList);
}


@end
