//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@class TSGroupThread;

@interface OWSGroupAvatarBuilder : OWSAvatarBuilder

- (instancetype)initWithThread:(TSGroupThread *)thread diameter:(NSUInteger)diameter;

+ (nullable UIImage *)defaultAvatarForGroupId:(NSData *)groupId
                                  avatarColor:(UIColor *)avatarColor
                                     diameter:(NSUInteger)diameter;

@end

NS_ASSUME_NONNULL_END
