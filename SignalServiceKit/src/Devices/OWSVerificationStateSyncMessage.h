//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>
#import <SignalServiceKit/OWSRecipientIdentity.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@interface OWSVerificationStateSyncMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                  verificationState:(OWSVerificationState)verificationState
                        identityKey:(NSData *)identityKey
    verificationForRecipientAddress:(SignalServiceAddress *)address
                        transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

// This is a clunky name, but we want to differentiate it from `recipientIdentifier` inherited from `TSOutgoingMessage`
@property (nonatomic, readonly) SignalServiceAddress *verificationForRecipientAddress;

@property (nonatomic, readonly) size_t paddingBytesLength;
@property (nonatomic, readonly) size_t unpaddedVerifiedLength;

@end

NS_ASSUME_NONNULL_END
