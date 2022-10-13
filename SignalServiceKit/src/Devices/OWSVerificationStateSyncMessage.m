//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSVerificationStateSyncMessage.h"
#import "OWSIdentityManager.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface OWSVerificationStateSyncMessage ()

@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) NSData *identityKey;

@end

#pragma mark -

@implementation OWSVerificationStateSyncMessage

- (instancetype)initWithThread:(TSThread *)thread
                  verificationState:(OWSVerificationState)verificationState
                        identityKey:(NSData *)identityKey
    verificationForRecipientAddress:(SignalServiceAddress *)address
                        transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == kIdentityKeyLength);
    OWSAssertDebug(address.isValid);

    // we only sync user's marking as un/verified. Never sync the conflicted state, the sibling device
    // will figure that out on it's own.
    OWSAssertDebug(verificationState != OWSVerificationStateNoLongerVerified);

    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _verificationState = verificationState;
    _identityKey = identityKey;
    _verificationForRecipientAddress = address;

    // This sync message should be 1-512 bytes longer than the corresponding NullMessage
    // we store this values so the corresponding NullMessage can subtract it from the total length.
    _paddingBytesLength = arc4random_uniform(512) + 1;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_verificationForRecipientAddress == nil) {
        _verificationForRecipientAddress =
            [[SignalServiceAddress alloc] initWithPhoneNumber:[coder decodeObjectForKey:@"verificationForRecipientId"]];
        OWSAssertDebug(_verificationForRecipientAddress.isValid);
    }

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(self.identityKey.length == kIdentityKeyLength);
    OWSAssertDebug(self.verificationForRecipientAddress.isValid);

    // we only sync user's marking as un/verified. Never sync the conflicted state, the sibling device
    // will figure that out on it's own.
    OWSAssertDebug(self.verificationState != OWSVerificationStateNoLongerVerified);

    // We add the same amount of padding in the VerificationStateSync message and it's corresponding NullMessage so that
    // the sync message is indistinguishable from an outgoing Sent transcript corresponding to the NullMessage. We pad
    // the NullMessage so as to obscure it's content. The sync message (like all sync messages) will be *additionally*
    // padded by the superclass while being sent. The end result is we send a NullMessage of a non-distinct size, and a
    // verification sync which is ~1-512 bytes larger then that.
    OWSAssertDebug(self.paddingBytesLength != 0);

    SSKProtoVerified *_Nullable verifiedProto = BuildVerifiedProtoWithAddress(
        self.verificationForRecipientAddress, self.identityKey, self.verificationState, self.paddingBytesLength);
    if (!verifiedProto) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setVerified:verifiedProto];
    return syncMessageBuilder;
}

- (size_t)unpaddedVerifiedLength
{
    OWSAssertDebug(self.identityKey.length == kIdentityKeyLength);
    OWSAssertDebug(self.verificationForRecipientAddress.isValid);

    // we only sync user's marking as un/verified. Never sync the conflicted state, the sibling device
    // will figure that out on it's own.
    OWSAssertDebug(self.verificationState != OWSVerificationStateNoLongerVerified);

    SSKProtoVerified *_Nullable verifiedProto = BuildVerifiedProtoWithAddress(
        self.verificationForRecipientAddress, self.identityKey, self.verificationState, 0);
    if (!verifiedProto) {
        OWSFailDebug(@"could not build protobuf.");
        return 0;
    }
    NSError *error;
    NSData *_Nullable verifiedData = [verifiedProto serializedDataAndReturnError:&error];
    if (error || !verifiedData) {
        OWSFailDebug(@"could not serialize protobuf.");
        return 0;
    }
    return verifiedData.length;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
