//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSOutgoingMessage.h>

@class TSGroupThread;

NS_ASSUME_NONNULL_BEGIN

/// A message sent to the other participants of a group call to inform them that
/// some state has changed, such as we have joined or left the call.
///
/// Not to be confused with an ``OWSGroupCallMessage``.
@interface OWSOutgoingGroupCallMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSGroupThread *)thread
                         eraId:(nullable NSString *)eraId
                   transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
