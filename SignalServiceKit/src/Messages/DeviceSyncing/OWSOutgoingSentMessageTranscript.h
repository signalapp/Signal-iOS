//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
                      isRecipientUpdate:(BOOL)isRecipientUpdate NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
