//
//  FatherModel.m
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import "FatherModel.h"

@implementation FatherModel

#pragma mark - 根据类名称获取指定的类

/* 获取指定名称的类：
 * @param name 要查找的类的名称。
 * @return 返回指定名称的类；
 * @note 如果类没有在Objective-C运行时注册，则返回 nil。
 * @note 如果该类不存在,调用 _objc_classLoader() 函数，然后调用objc_classHandler() 函数，两者都可以创建一个新类。
 * @note objc_getClass() 与objc_lookUpClass() 的不同之处在于，如果类没有注册，objc_getClass() 将调用类处理程序回调，然后再次检查类是否注册。objc_lookUpClass() 不调用类处理程序回调。
 * @Warning: 如果aClassName是为类的 isa 设置的名称，则无法执行!
 */
Class _Nullable objc_getClass(const char * _Nonnull name);

/* 获取指定名称的类：
 * @note 该函数功能基于 objc_getClass() 函数，内部首先调用 objc_getClass() 函数获取返回值；
 *       然后判断返回值是否为空，如果返回值为空，则终止进程；
 * @note 此函数由 ZeroLink 使用，如果没有 ZeroLink，则无法找到类将是编译时链接错误。
 */
Class _Nonnull objc_getRequiredClass(const char * _Nonnull name);

/* 获取指定名称的类
 * @note 如果类没有在Objective-C运行时注册，则返回 nil。
 *       如果该类不存在, 调用_objc_classLoader() 函数，它可以创建一个新类。
 * @note objc_getClass() 与这个函数的不同之处在于，如果类没有注册，objc_getClass() 将调用类处理程序回调函数，然后第二次检查类是否注册。这个函数不调用类处理程序回调。
 */
Class _Nullable objc_lookUpClass(const char * _Nonnull name);

/* 获取指定名称的类的元类
 * @note 如果指定名称的类不存在，则返回 nil 并且打印日志 objc[3966]: class `aClassName' not linked into application
 * @note 如果命名类的定义未注册，则此函数调用类处理程序回调，然后再次检查类是否注册。但是，每个类定义都必须有一个有效的元类定义，因此无论元类定义是否有效，它总是返回。
 */
Class _Nullable objc_getMetaClass(const char * _Nonnull name);

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
