//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SSKProtoSyncMessageBlocked;
@class SignalServiceAddress;
@class TSGroupModel;
@class TSThread;

extern NSString *const kNSNotificationName_BlockListDidChange;

// This class can be safely accessed and used from any thread.
@interface OWSBlockingManager : NSObject

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

- (void)addBlockedAddress:(SignalServiceAddress *)address;
- (void)addBlockedAddress:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removeBlockedAddress:(SignalServiceAddress *)address;
- (void)removeBlockedAddress:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction;

- (void)processIncomingBlockedSyncMessage:(SSKProtoSyncMessageBlocked *)syncMessage
                              transaction:(SDSAnyWriteTransaction *)transaction;

@property (readonly) NSSet<SignalServiceAddress *> *blockedAddresses;
@property (readonly) NSArray<NSString *> *blockedPhoneNumbers;
@property (readonly) NSArray<NSString *> *blockedUUIDs;

@property (readonly) NSArray<NSData *> *blockedGroupIds;
@property (readonly) NSArray<TSGroupModel *> *blockedGroups;

- (void)addBlockedGroup:(TSGroupModel *)group;
- (void)removeBlockedGroupId:(NSData *)groupId;
- (nullable TSGroupModel *)cachedGroupDetailsWithGroupId:(NSData *)groupId;

- (void)addBlockedThread:(TSThread *)thread;
- (void)removeBlockedThread:(TSThread *)thread;
- (BOOL)isThreadBlocked:(TSThread *)thread;

- (BOOL)isAddressBlocked:(SignalServiceAddress *)address;
- (BOOL)isGroupIdBlocked:(NSData *)groupId;

- (void)syncBlockList;

- (void)warmCaches;

@end

NS_ASSUME_NONNULL_END
