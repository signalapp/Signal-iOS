//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

/// Outgoing message we send to the contact who requested we activate payments.
/// NOT rendered in chat; a separate TSInfoMessage is created for that purpose.
@interface OWSPaymentActivationRequestFinishedMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
