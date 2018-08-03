//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, OWSVerificationState) {
    OWSVerificationStateDefault,
    OWSVerificationStateVerified,
    OWSVerificationStateNoLongerVerified,
};

@class SSKProtoVerified;

NSString *OWSVerificationStateToString(OWSVerificationState verificationState);
SSKProtoVerified *_Nullable BuildVerifiedProtoWithRecipientId(NSString *destinationRecipientId,
    NSData *identityKey,
    OWSVerificationState verificationState,
    NSUInteger paddingBytesLength);

@interface OWSRecipientIdentity : TSYapDatabaseObject

@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) NSData *identityKey;
@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly) BOOL isFirstKnownKey;

#pragma mark - Verification State

@property (atomic, readonly) OWSVerificationState verificationState;

- (void)updateWithVerificationState:(OWSVerificationState)verificationState
                        transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Initializers

- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId NS_UNAVAILABLE;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithRecipientId:(NSString *)recipientId
                        identityKey:(NSData *)identityKey
                    isFirstKnownKey:(BOOL)isFirstKnownKey
                          createdAt:(NSDate *)createdAt
                  verificationState:(OWSVerificationState)verificationState NS_DESIGNATED_INITIALIZER;

#pragma mark - debug

+ (void)printAllIdentities;

@end

NS_ASSUME_NONNULL_END
