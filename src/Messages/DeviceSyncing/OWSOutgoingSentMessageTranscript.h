//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;

/**
 * Notifies your other registered devices (if you have any) that you've sent a message.
 * This way the message you just sent can appear on all your devices.
 */
@interface OWSOutgoingSentMessageTranscript : OWSOutgoingSyncMessage

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message;

@end

NS_ASSUME_NONNULL_END
