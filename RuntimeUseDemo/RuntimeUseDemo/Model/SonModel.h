//
//  SonModel.h
//  RuntimeUseDemo
//
//  Created by 苏沫离 on 2019/1/9.
//  Copyright © 2019 苏沫离. All rights reserved.
//

#import "FatherModel.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SonModelDelegate <FatherModelDelegate>

- (void)logSonModelDelegate;

+ (void)logSonModelDelegate1;

@end


@interface SonModel : FatherModel
@property (nonatomic ,strong) NSString *age;
@property (nonatomic ,strong ,class) NSString *classAge;

@end

NS_ASSUME_NONNULL_END
