//
//  Model.m
//  RuntimeUseDemo
//
//  Created by 王苏沫离龙 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import "Model.h"
#import <objc/runtime.h>


//消息转发辅助类
@interface ModelHelper : NSObject
- (void)eatFood;
@end

@implementation ModelHelper

- (void)eatFood{
    NSLog(@"%s",__func__);
}

- (void)playGames{
    NSLog(@"%s",__func__);
}


@end

@implementation SuperModel

- (instancetype)init{
    self = [super init];
    if (self) {
        id self_object = self.class;
        id super_object = super.class;
        NSLog(@"1  ---- %@ : %p",self_object,self_object);
        NSLog(@"2  ---- %@ : %p",super_object,super_object);
    }
    return self;
}
@end

@interface Model ()
@property (nonatomic ,strong) ModelHelper *helper;
@end

@implementation Model

- (instancetype)init{
    self = [super init];
    if (self) {
        id self_object = self.class;
        id super_object = super.class;
        NSLog(@"3  ==== %@ : %p",self_object,self_object);
        NSLog(@"4  ==== %@ : %p",super_object,super_object);
    }
    return self;
}

- (void)logModel{
    NSLog(@"%s",__func__);
}

#pragma mark - 第一步：动态方法决议

void drinkingMethodIMP(id self ,SEL _cmd){
    NSLog(@"为指定的选择器 SEL : %@ 提供函数指针 IMP , 根据 IMP 执行具体的实现",NSStringFromSelector(_cmd));
}

/* 以动态方式为实例方法的指定选择器提供IMP。
 * 函数指针IMP 指向实现代码。
 */
+ (BOOL)resolveInstanceMethod:(SEL)sel{
    
    if (sel == NSSelectorFromString(@"drinking")){
        //为指定的选择器 SEL 提供函数指针 IMP
        return class_addMethod(self.class, sel, (IMP)drinkingMethodIMP, "v@:@");
    }
    
    //去父类判断：是否父类提供了 IMP
    BOOL superResult = [super resolveInstanceMethod:sel];
    NSLog(@"step_1 : %s  |  selector : %@   |  superResult : %d",__func__,NSStringFromSelector(sel),superResult);
    return superResult;
}

#pragma mark - 第二步：重定向接收者

/* 重定向接收者：当一个对象无法找到消息时，为该消息提供一个能够处理它的对象
 *
 * 如果动态方法决议没有提供实现的函数或者提供失败，就会执行该方法重定向接收者；
 * 注意：不能提供 self，否则进入死循环
 */
- (id)forwardingTargetForSelector:(SEL)aSelector{
    
    //检查消息 aSelector 能否由 ModelHelper 实例处理
    //如果能处理，那么返回 ModelHelper 实例
    //    if ([self.helper respondsToSelector:aSelector]) {
    //        return self.helper;
    //    }
    
    //如果不能处理，那么去父类判断：是否父类重定向接收者
    id superResult = [super forwardingTargetForSelector:aSelector];
    NSLog(@"step_2 : %s  |  selector : %@   |  superResult : %@",__func__,NSStringFromSelector(aSelector),superResult);
    return superResult;
}

#pragma mark - 第三步：完整消息转发

//获取方法签名
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector{
    if ([ModelHelper instancesRespondToSelector:aSelector]){
        //从消息转发辅助类 获取 方法签名
        NSMethodSignature *helperSign = [ModelHelper instanceMethodSignatureForSelector:aSelector];
        NSLog(@"step_3_1 : %s  |  selector : %@   |  helperSign : %@",__func__,NSStringFromSelector(aSelector),helperSign);
        return helperSign;
    }
    
    //尝试从父类获取方法签名：如果父类没有实现该方法，则返回 null
    NSMethodSignature *superSign = [super methodSignatureForSelector:aSelector];
    NSLog(@"step_3_2 : %s  |  selector : %@   |  superResult : %@",__func__,NSStringFromSelector(aSelector),superSign);
    return superSign;
}

/* 未知消息分发中心，将未知消息转发给其它对象
 * 只有在消息接收对象无法正常响应消息时才被调用
 */
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"step_3_3 : %s  |  target : %@  |  selector : %@",__func__,anInvocation.target,NSStringFromSelector(anInvocation.selector));
    NSLog(@"step_3_3 : NSMethodSignature : %@",anInvocation.methodSignature);
    
    if ([ModelHelper instancesRespondToSelector:anInvocation.selector]){
        [anInvocation invokeWithTarget:self.helper];
    }
}


//懒加载一个消息转发辅助类
- (ModelHelper *)helper{
    if (_helper == nil) {
        _helper = [[ModelHelper alloc] init];
    }
    return _helper;
}

@end


@implementation ModelChild


@end








@protocol ObjectDelegate <NSObject>
- (void)logObjectInfo;
@end


@interface SuperModel (Test)
<ObjectDelegate>
@property (nonatomic ,strong) NSString *nickName;
- (void)logNickName;
+ (void)logHello;
@end


@implementation SuperModel (Test)



- (void)logNickName{
    NSLog(@"class_getName  ==== %s",class_getName(self.class));
}

+ (void)logHello{
    NSLog(@"class_getName  ---- %s",class_getName(self.class));
}

- (void)setNickName:(NSString *)nickName{
    objc_setAssociatedObject(self, @selector(nickName), nickName, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)nickName{
    return objc_getAssociatedObject(self, _cmd);
}

#pragma mark - ObjectDelegate

- (void)logObjectInfo{
    NSLog(@"实现协议 ObjectDelegate 的 -logObjectInfo 方法");
}

@end
