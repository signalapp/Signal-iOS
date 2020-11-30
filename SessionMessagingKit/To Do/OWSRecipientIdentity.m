//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage.h"
#import <SignalCoreKit/Cryptography.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>
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

SNProtoVerifiedState OWSVerificationStateToProtoState(OWSVerificationState verificationState)
{
    switch (verificationState) {
        case OWSVerificationStateDefault:
            return SNProtoVerifiedStateDefault;
        case OWSVerificationStateVerified:
            return SNProtoVerifiedStateVerified;
        case OWSVerificationStateNoLongerVerified:
            return SNProtoVerifiedStateUnverified;
    }
}

SNProtoVerified *_Nullable BuildVerifiedProtoWithRecipientId(NSString *destinationRecipientId,
    NSData *identityKey,
    OWSVerificationState verificationState,
    NSUInteger paddingBytesLength)
{

    SNProtoVerifiedBuilder *verifiedBuilder = [SNProtoVerified builderWithDestination:destinationRecipientId];
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
    SNProtoVerified *_Nullable verifiedProto = [verifiedBuilder buildAndReturnError:&error];
    if (error || !verifiedProto) {
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
    // Ensure changes are persisted without clobbering any work done on another thread or instance.
    [self updateWithChangeBlock:^(OWSRecipientIdentity *_Nonnull obj) {
        obj.verificationState = verificationState;
    }
                    transaction:transaction];
}

- (void)updateWithChangeBlock:(void (^)(OWSRecipientIdentity *obj))changeBlock
                  transaction:(YapDatabaseReadWriteTransaction *)transaction
{
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

    [LKStorage writeSyncWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        OWSRecipientIdentity *latest = [[self class] fetchObjectWithUniqueID:self.uniqueId transaction:transaction];
        if (latest == nil) {
            [self saveWithTransaction:transaction];
            return;
        }
        
        changeBlock(latest);
        [latest saveWithTransaction:transaction];
    }];
}

@end

NS_ASSUME_NONNULL_END
