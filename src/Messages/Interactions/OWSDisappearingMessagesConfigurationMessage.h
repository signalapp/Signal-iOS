//  Created by Michael Kirk on 9/25/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDisappearingMessagesConfiguration;

@interface OWSDisappearingMessagesConfigurationMessage : TSOutgoingMessage

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration thread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
