//
//  PeopleModel.h
//  objc-test
//
//  Created by 苏沫离 on 2019/1/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PeopleModelDelegate <NSObject>

- (void)PeopleModelTestProtocol;

@end

@interface PeopleModel : NSObject

@end

@interface ManModel : NSObject

@end


@interface WomanModel : NSObject

@end


@interface WomanModel(WomanCategory)<PeopleModelDelegate>

@end


NS_ASSUME_NONNULL_END
