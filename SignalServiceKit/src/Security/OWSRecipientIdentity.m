//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "Cryptography.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSPrimaryStorage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

NSString *OWSVerificationStateToString(OWSVerificationState verificationState)
{
    switch (verificationState) {
        case OWSVerificationStateDefault:
            return @"OWSVerificationStateDefault";
        case OWSVerificationStateVerified:
            return @"OWSVerificationStateVerified";
        case OWSVerificationStateNoLongerVerified:
            return @"OWSVerificationStateNoLongerVerified";
    }
}

SSKProtoVerifiedState OWSVerificationStateToProtoState(OWSVerificationState verificationState)
{
    switch (verificationState) {
        case OWSVerificationStateDefault:
            return SSKProtoVerifiedStateDefault;
        case OWSVerificationStateVerified:
            return SSKProtoVerifiedStateVerified;
        case OWSVerificationStateNoLongerVerified:
            return SSKProtoVerifiedStateUnverified;
    }
}

SSKProtoVerified *_Nullable BuildVerifiedProtoWithRecipientId(NSString *destinationRecipientId,
    NSData *identityKey,
    OWSVerificationState verificationState,
    NSUInteger paddingBytesLength)
{
    OWSCAssertDebug(identityKey.length == kIdentityKeyLength);
    OWSCAssertDebug(destinationRecipientId.length > 0);
    // we only sync user's marking as un/verified. Never sync the conflicted state, the sibling device
    // will figure that out on it's own.
    OWSCAssertDebug(verificationState != OWSVerificationStateNoLongerVerified);

    SSKProtoVerifiedBuilder *verifiedBuilder = [SSKProtoVerifiedBuilder new];
    verifiedBuilder.destination = destinationRecipientId;
    verifiedBuilder.identityKey = identityKey;
    verifiedBuilder.state = OWSVerificationStateToProtoState(verificationState);

    if (paddingBytesLength > 0) {
        // We add the same amount of padding in the VerificationStateSync message and it's coresponding NullMessage so
        // that the sync message is indistinguishable from an outgoing Sent transcript corresponding to the NullMessage.
        // We pad the NullMessage so as to obscure it's content. The sync message (like all sync messages) will be
        // *additionally* padded by the superclass while being sent. The end result is we send a NullMessage of a
        // non-distinct size, and a verification sync which is ~1-512 bytes larger then that.
        verifiedBuilder.nullMessage = [Cryptography generateRandomBytes:paddingBytesLength];
    }

    NSError *error;
    SSKProtoVerified *_Nullable verifiedProto = [verifiedBuilder buildAndReturnError:&error];
    if (error || !verifiedProto) {
        OWSCFailDebug(@"%@ could not build protobuf: %@", @"[BuildVerifiedProtoWithRecipientId]", error);
        return nil;
    }
    return verifiedProto;
}

@interface OWSRecipientIdentity ()

@property (atomic) OWSVerificationState verificationState;

@end

/**
 * Record for a recipients identity key and some meta data around it used to make trust decisions.
 *
 * NOTE: Instances of this class MUST only be retrieved/persisted via it's internal `dbConnection`,
 *       which makes some special accomodations to enforce consistency.
 */
@implementation OWSRecipientIdentity

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self) {
        if (![coder decodeObjectForKey:@"verificationState"]) {
            _verificationState = OWSVerificationStateDefault;
        }
    }

    return self;
}

- (instancetype)initWithRecipientId:(NSString *)recipientId
                        identityKey:(NSData *)identityKey
                    isFirstKnownKey:(BOOL)isFirstKnownKey
                          createdAt:(NSDate *)createdAt
                  verificationState:(OWSVerificationState)verificationState
{
    self = [super initWithUniqueId:recipientId];
    if (!self) {
        return self;
    }
    
    _recipientId = recipientId;
    _identityKey = identityKey;
    _isFirstKnownKey = isFirstKnownKey;
    _createdAt = createdAt;
    _verificationState = verificationState;

    return self;
}

- (void)updateWithVerificationState:(OWSVerificationState)verificationState
                        transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    // Ensure changes are persisted without clobbering any work done on another thread or instance.
    [self updateWithChangeBlock:^(OWSRecipientIdentity *_Nonnull obj) {
        obj.verificationState = verificationState;
    }
                    transaction:transaction];
}

- (void)updateWithChangeBlock:(void (^)(OWSRecipientIdentity *obj))changeBlock
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    changeBlock(self);

    OWSRecipientIdentity *latest = [[self class] fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
    if (latest == nil) {
        [self saveWithTransaction:transaction];
        return;
    }

    changeBlock(latest);
    [latest saveWithTransaction:transaction];
}

- (void)updateWithChangeBlock:(void (^)(OWSRecipientIdentity *obj))changeBlock
{
    changeBlock(self);

    [[self class].dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSRecipientIdentity *latest = [[self class] fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
        if (latest == nil) {
            [self saveWithTransaction:transaction];
            return;
        }
        
        changeBlock(latest);
        [latest saveWithTransaction:transaction];
    }];
}

#pragma mark - debug

+ (void)printAllIdentities
{
    OWSLogInfo(@"### All Recipient Identities ###");
    __block int count = 0;
    [self enumerateCollectionObjectsUsingBlock:^(id obj, BOOL *stop) {
        count++;
        if (![obj isKindOfClass:[self class]]) {
            OWSFailDebug(@"unexpected object in collection: %@", obj);
            return;
        }
        OWSRecipientIdentity *recipientIdentity = (OWSRecipientIdentity *)obj;

        OWSLogInfo(@"Identity %d: %@", count, recipientIdentity.debugDescription);
    }];
}

@end

NS_ASSUME_NONNULL_END
