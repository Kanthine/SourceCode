//
//  UIButton+DoubleHit.h
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/14.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIButton (DoubleHit)
/* 设置点击时间间隔
 * 默认为 0 ，没有防暴击效果
 */
@property (nonatomic, assign) NSTimeInterval hitTimeInterval;

/* 记录是否刚点击的状态
 */
@property (nonatomic, assign) BOOL isIgnoreEvent;
@end

NS_ASSUME_NONNULL_END
