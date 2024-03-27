//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSReaction;

@interface OWSOutgoingReactionMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSMessage *)message
                         emoji:(NSString *)emoji
                    isRemoving:(BOOL)isRemoving
              expiresInSeconds:(uint32_t)expiresInSeconds
                   transaction:(SDSAnyReadTransaction *)transaction;

@property (nonatomic, readonly) NSString *messageUniqueId;
@property (nonatomic, readonly) NSString *emoji;
@property (nonatomic, readonly) BOOL isRemoving;
@property (nonatomic, nullable) OWSReaction *createdReaction;
@property (nonatomic, nullable) OWSReaction *previousReaction;

@end

NS_ASSUME_NONNULL_END
