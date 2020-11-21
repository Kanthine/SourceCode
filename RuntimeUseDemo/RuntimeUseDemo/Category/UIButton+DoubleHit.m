//
//  UIButton+DoubleHit.m
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/14.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import "UIButton+DoubleHit.h"
#import <objc/runtime.h>
@implementation UIButton (DoubleHit)
+ (void)load{
    NSLog(@"%s",__func__);
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* 根据选择器类型 sendAction:to:forEvent: ，获取该类的实例方法 -sendAction:to:forEvent:
         * 如果该类或者父类实现了该方法，则返回 Method ；否则返回 NULL；
         */
        Method oldMethod = class_getInstanceMethod(self.class,@selector(sendAction:to:forEvent:));
        Method newMethod = class_getInstanceMethod(self.class, @selector(l_sendAction:to:forEvent:));
        
        /** 查询该类的方法列表，寻找与选择器类型 sendAction:to:forEvent: 匹配的方法：
         * 如果找到，则已经实现，添加失败返回 NO；
         * 如果没有找到，则添加一个方法：该方法的选择器类型为 sendAction:to:forEvent: ，持有的函数地址指向它处；
         */
        BOOL addResult = class_addMethod(self.class, @selector(sendAction:to:forEvent:), method_getImplementation(newMethod), method_getTypeEncoding(newMethod));
        if (addResult) {
            /* 方法添加成功，此时：实现函数地址 IMP 指向它处；
             * 还需要将与选择器类型 sendAction:to:forEvent: 匹配的方法的 IMP 指向原有的实现函数地址
             */
            class_replaceMethod(self.class, @selector(l_sendAction:to:forEvent:), method_getImplementation(oldMethod), method_getTypeEncoding(oldMethod));
        }else{
            //方法添加失败，此时：只需将两个方法持有的函数地址 IMP 交换即可；
            method_exchangeImplementations(oldMethod, newMethod);
        }
    });
}

- (void)l_sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event{
    
    if ([NSStringFromClass(self.class) isEqualToString:@"UIButton"] && self.hitTimeInterval > 0){
        //为 UIButton 添加新的功能：防暴击
        //如果在防暴击中，则不执行；否则执行如下代码
        if (self.isIgnoreEvent == NO){
            self.isIgnoreEvent = YES;//设置状态：在防暴击中
            [self performSelector:@selector(resertState) withObject:nil afterDelay:self.hitTimeInterval];//指定时间后重置点击状态
            
            //该行代码很重要：接着执行原始方法的内部逻辑
            [self l_sendAction:action to:target forEvent:event];
        }
    }else{
        [self l_sendAction:action to:target forEvent:event];
    }
}

- (void)resertState{
    [self setIsIgnoreEvent:NO];
}

//记录是否是刚点击的状态
- (BOOL)isIgnoreEvent{
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}

- (void)setIsIgnoreEvent:(BOOL)isIgnoreEvent{
    objc_setAssociatedObject(self, @selector(isIgnoreEvent), @(isIgnoreEvent), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setHitTimeInterval:(NSTimeInterval)hitTimeInterval{
    objc_setAssociatedObject(self, @selector(hitTimeInterval), @(hitTimeInterval), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSTimeInterval)hitTimeInterval{
    return [objc_getAssociatedObject(self, _cmd) doubleValue];
}
@end
