//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSRecipientIdentity : TSYapDatabaseObject

@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) NSData *identityKey;
@property (nonatomic, readonly) NSDate *createdAt;
@property (atomic, readonly) BOOL wasSeen;
@property (nonatomic, readonly) BOOL isFirstKnownKey;
@property (atomic) BOOL approvedForBlockingUse;
@property (atomic) BOOL approvedForNonBlockingUse;

- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;

- (instancetype)initWithRecipientId:(NSString *)recipientId
                        identityKey:(NSData *)identityKey
                    isFirstKnownKey:(BOOL)isFirstKnownKey
                          createdAt:(NSDate *)createdAt
             approvedForBlockingUse:(BOOL)approvedForBlockingUse
          approvedForNonBlockingUse:(BOOL)approvedForNonBlockingUse NS_DESIGNATED_INITIALIZER;

- (void)markAsSeen;

#pragma mark - debug

+ (void)printAllIdentities;

@end

NS_ASSUME_NONNULL_END
