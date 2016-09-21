//  Created by Michael Kirk on 9/26/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSAvatarBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@class TSGroupThread;

@interface OWSGroupAvatarBuilder : OWSAvatarBuilder

- (instancetype)initWithThread:(TSGroupThread *)thread;

@end

NS_ASSUME_NONNULL_END
