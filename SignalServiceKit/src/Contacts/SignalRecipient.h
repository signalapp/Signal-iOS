//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

// We hang the "known device list" for signal accounts on this entity.
@interface SignalRecipient : TSYapDatabaseObject

@property (readonly) NSOrderedSet *devices;

@property (nonatomic) BOOL mayBeUnregistered;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)selfRecipient;

+ (SignalRecipient *)ensureRecipientExistsWithRegisteredRecipientId:(NSString *)recipientId
                                                        transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (SignalRecipient *)ensureRecipientExistsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (void)ensureRecipientExistsWithRecipientId:(NSString *)recipientId
                                    deviceId:(UInt32)deviceId
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction;

// TODO: Replace with cache of known signal account ids.
+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier;
+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                           withTransaction:(YapDatabaseReadTransaction *)transaction;

- (void)addDevices:(NSSet *)set;
- (void)removeDevices:(NSSet *)set;

- (NSString *)recipientId;

- (NSComparisonResult)compare:(SignalRecipient *)other;

@end

NS_ASSUME_NONNULL_END
