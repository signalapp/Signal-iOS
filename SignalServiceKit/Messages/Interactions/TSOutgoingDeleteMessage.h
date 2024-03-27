//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class StoryMessage;

@interface TSOutgoingDeleteMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSOutgoingMessage *)message
                   transaction:(SDSAnyReadTransaction *)transaction;

- (instancetype)initWithThread:(TSThread *)thread
                  storyMessage:(StoryMessage *)storyMessage
             skippedRecipients:(nullable NSSet<SignalServiceAddress *> *)skippedRecipients
                   transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
