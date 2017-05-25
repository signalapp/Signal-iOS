//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSRecipientIdentity : TSYapDatabaseObject

@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) NSData *identityKey;
@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly) BOOL isFirstKnownKey;

#pragma mark - get/set Seen

@property (atomic, readonly) BOOL wasSeen;
- (void)updateAsSeen;

#pragma mark - get/set Approval

@property (atomic, readonly) BOOL approvedForBlockingUse;
@property (atomic, readonly) BOOL approvedForNonBlockingUse;
- (void)updateWithApprovedForBlockingUse:(BOOL)approvedForBlockingUse
               approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse;

#pragma mark - Initializers

- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;

- (instancetype)initWithRecipientId:(NSString *)recipientId
                        identityKey:(NSData *)identityKey
                    isFirstKnownKey:(BOOL)isFirstKnownKey
                          createdAt:(NSDate *)createdAt
             approvedForBlockingUse:(BOOL)approvedForBlockingUse
          approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse NS_DESIGNATED_INITIALIZER;

#pragma mark - debug

+ (void)printAllIdentities;

@end

NS_ASSUME_NONNULL_END
