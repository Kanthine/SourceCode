//
//  Model.h
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SuperModel : NSObject
@end

@interface Model : SuperModel
- (void)logModel;
@end

@interface ModelChild : Model
@end
//xcrun -sdk iphonesimulator clang -rewrite-objc Model.m


NS_ASSUME_NONNULL_END
