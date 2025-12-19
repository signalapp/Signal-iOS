//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSVerificationStateSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface OWSVerificationStateSyncMessage ()

@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) NSData *identityKey;

@end

#pragma mark -

@implementation OWSVerificationStateSyncMessage

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                  verificationState:(OWSVerificationState)verificationState
                        identityKey:(NSData *)identityKey
    verificationForRecipientAddress:(SignalServiceAddress *)address
                        transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug(identityKey.length == OWSIdentityManagerObjCBridge.identityKeyLength);
    OWSAssertDebug(address.isValid);

    // we only sync user's marking as un/verified. Never sync the conflicted state, the sibling device
    // will figure that out on it's own.
    OWSAssertDebug(verificationState != OWSVerificationStateNoLongerVerified);

    self = [super initWithLocalThread:localThread transaction:transaction];
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

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSData *identityKey = self.identityKey;
    if (identityKey != nil) {
        [coder encodeObject:identityKey forKey:@"identityKey"];
    }
    [coder encodeObject:[self valueForKey:@"paddingBytesLength"] forKey:@"paddingBytesLength"];
    SignalServiceAddress *verificationForRecipientAddress = self.verificationForRecipientAddress;
    if (verificationForRecipientAddress != nil) {
        [coder encodeObject:verificationForRecipientAddress forKey:@"verificationForRecipientAddress"];
    }
    [coder encodeObject:[self valueForKey:@"verificationState"] forKey:@"verificationState"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_identityKey = [coder decodeObjectOfClass:[NSData class] forKey:@"identityKey"];
    self->_paddingBytesLength = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                 forKey:@"paddingBytesLength"] unsignedLongValue];
    self->_verificationForRecipientAddress = [coder decodeObjectOfClass:[SignalServiceAddress class]
                                                                 forKey:@"verificationForRecipientAddress"];
    self->_verificationState = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class]
                                                                forKey:@"verificationState"] unsignedLongLongValue];

    if (_verificationForRecipientAddress == nil) {
        NSString *phoneNumber = [coder decodeObjectForKey:@"verificationForRecipientId"];
        _verificationForRecipientAddress = [SignalServiceAddress legacyAddressWithServiceIdString:nil
                                                                                      phoneNumber:phoneNumber];
        OWSAssertDebug(_verificationForRecipientAddress.isValid);
    }

    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.identityKey.hash;
    result ^= self.paddingBytesLength;
    result ^= self.verificationForRecipientAddress.hash;
    result ^= self.verificationState;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSVerificationStateSyncMessage *typedOther = (OWSVerificationStateSyncMessage *)other;
    if (![NSObject isObject:self.identityKey equalToObject:typedOther.identityKey]) {
        return NO;
    }
    if (self.paddingBytesLength != typedOther.paddingBytesLength) {
        return NO;
    }
    if (![NSObject isObject:self.verificationForRecipientAddress
              equalToObject:typedOther.verificationForRecipientAddress]) {
        return NO;
    }
    if (self.verificationState != typedOther.verificationState) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSVerificationStateSyncMessage *result = [super copyWithZone:zone];
    result->_identityKey = self.identityKey;
    result->_paddingBytesLength = self.paddingBytesLength;
    result->_verificationForRecipientAddress = self.verificationForRecipientAddress;
    result->_verificationState = self.verificationState;
    return result;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(DBReadTransaction *)transaction
{
    // We add the same amount of padding in the VerificationStateSync message and it's corresponding NullMessage so that
    // the sync message is indistinguishable from an outgoing Sent transcript corresponding to the NullMessage. We pad
    // the NullMessage so as to obscure it's content. The sync message (like all sync messages) will be *additionally*
    // padded by the superclass while being sent. The end result is we send a NullMessage of a non-distinct size, and a
    // verification sync which is ~1-512 bytes larger then that.
    OWSAssertDebug(self.paddingBytesLength != 0);

    AciObjC *verificationForRecipientAci = (AciObjC *)self.verificationForRecipientAddress.serviceIdObjC;
    if (![verificationForRecipientAci isKindOfClass:[AciObjC class]]) {
        OWSFailDebug(@"couldn't get verified aci");
        return nil;
    }

    SSKProtoVerified *verifiedProto =
        [OWSRecipientIdentity buildVerifiedProtoWithDestinationAci:verificationForRecipientAci
                                                       identityKey:self.identityKey
                                                 verificationState:self.verificationState
                                                paddingBytesLength:self.paddingBytesLength];

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setVerified:verifiedProto];
    return syncMessageBuilder;
}

- (size_t)unpaddedVerifiedLength
{
    AciObjC *verificationForRecipientAci = (AciObjC *)self.verificationForRecipientAddress.serviceIdObjC;
    if (![verificationForRecipientAci isKindOfClass:[AciObjC class]]) {
        OWSFailDebug(@"couldn't get verified aci");
        return 0;
    }

    SSKProtoVerified *verifiedProto =
        [OWSRecipientIdentity buildVerifiedProtoWithDestinationAci:verificationForRecipientAci
                                                       identityKey:self.identityKey
                                                 verificationState:self.verificationState
                                                paddingBytesLength:0];

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
