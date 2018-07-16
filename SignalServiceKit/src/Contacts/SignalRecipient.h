//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

// We hang the "known device list" for signal accounts on this entity.
@interface SignalRecipient : TSYapDatabaseObject

@property (nonatomic, readonly) NSOrderedSet *devices;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)selfRecipient;

+ (nullable instancetype)registeredRecipientForRecipientId:(NSString *)recipientId
                                               transaction:(YapDatabaseReadTransaction *)transaction;
+ (instancetype)getOrCreatedUnsavedRecipientForRecipientId:(NSString *)recipientId
                                               transaction:(YapDatabaseReadTransaction *)transaction;

- (void)addDevices:(NSSet *)set;
- (void)removeDevices:(NSSet *)set;

- (NSString *)recipientId;

- (NSComparisonResult)compare:(SignalRecipient *)other;

// TODO: Replace with cache of known signal account ids.
+ (BOOL)isRegisteredSignalAccount:(NSString *)recipientId transaction:(YapDatabaseReadTransaction *)transaction;

+ (SignalRecipient *)markAccountAsRegistered:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (void)markAccountAsRegistered:(NSString *)recipientId
                       deviceId:(UInt32)deviceId
                    transaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (void)markAccountAsNotRegistered:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
