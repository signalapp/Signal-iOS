//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSOutgoingMessage.h>

@class TSGroupThread;

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingGroupCallMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSGroupThread *)thread
                         eraId:(nullable NSString *)eraId
                   transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
