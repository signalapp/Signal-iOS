//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSDisappearingMessagesConfiguration;

@interface OWSDisappearingMessagesConfigurationMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;

- (instancetype)initWithConfiguration:(OWSDisappearingMessagesConfiguration *)configuration thread:(TSThread *)thread;

@end

NS_ASSUME_NONNULL_END
