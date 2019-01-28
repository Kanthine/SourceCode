//
//  MyModel.h
//  objc-test
//
//  Created by 苏沫离 on 2019/1/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MyModel : NSObject
{
    NSString *_name;
}

@property (nonatomic ,strong) NSString *name;

- (void)logName;

@end

NS_ASSUME_NONNULL_END
