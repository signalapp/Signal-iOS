//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;

/**
 * Notifies your other registered devices (if you have any) that you've sent a message.
 * This way the message you just sent can appear on all your devices.
 */
@interface OWSOutgoingSentMessageTranscript : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
