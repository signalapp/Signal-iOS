//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

// SignalRecipient serves two purposes:
//
// a) It serves as a cache of "known" Signal accounts.  When the service indicates
//    that an account exists, we make sure that an instance of SignalRecipient exists
//    for that recipient id (using mark as registered).
//    When the service indicates that an account does not exist, we remove any
//    SignalRecipient.
// b) We hang the "known device list" for known signal accounts on this entity.
@interface SignalRecipient : TSYapDatabaseObject

@property (nonatomic, readonly) NSOrderedSet *devices;

- (instancetype)init NS_UNAVAILABLE;

+ (nullable instancetype)registeredRecipientForRecipientId:(NSString *)recipientId
                                               transaction:(YapDatabaseReadTransaction *)transaction;
+ (instancetype)getOrBuildUnsavedRecipientForRecipientId:(NSString *)recipientId
                                             transaction:(YapDatabaseReadTransaction *)transaction;

- (void)addDevicesToRegisteredRecipient:(NSSet *)devices
                            transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)removeDevicesFromRecipient:(NSSet *)devices transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (NSString *)recipientId;

- (NSComparisonResult)compare:(SignalRecipient *)other;

+ (BOOL)isRegisteredRecipient:(NSString *)recipientId transaction:(YapDatabaseReadTransaction *)transaction;

+ (SignalRecipient *)markRecipientAsRegisteredAndGet:(NSString *)recipientId
                                         transaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (void)markRecipientAsRegistered:(NSString *)recipientId
                         deviceId:(UInt32)deviceId
                      transaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (void)removeUnregisteredRecipient:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
