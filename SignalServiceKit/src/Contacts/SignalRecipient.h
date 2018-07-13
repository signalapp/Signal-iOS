//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

// This class serves two purposes:
//
// * We only _persist_ SignalRecipient instances when we know
//   that it corresponds to an account on the Signal service.
//   So SignalRecipient serves as a defacto cache of "known
//   Signal users."
// * We hang the "known device list" for signal accounts on
//   this entity.
@interface SignalRecipient : TSYapDatabaseObject

@property (readonly) NSOrderedSet *devices;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)selfRecipient;

+ (SignalRecipient *)ensureRecipientExistsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (void)ensureRecipientExistsWithRecipientId:(NSString *)recipientId
                                    deviceId:(UInt32)deviceId
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier;
+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                           withTransaction:(YapDatabaseReadTransaction *)transaction;

- (void)addDevices:(NSSet *)set;
- (void)removeDevices:(NSSet *)set;

- (NSString *)recipientId;

- (NSComparisonResult)compare:(SignalRecipient *)other;

@end

NS_ASSUME_NONNULL_END
