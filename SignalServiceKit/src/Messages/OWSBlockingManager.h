//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SignalServiceAddress;
@class TSGroupModel;
@class TSThread;

extern NSString *const kNSNotificationName_BlockListDidChange;

extern NSString *const kOWSBlockingManager_BlockListCollection;

// This class can be safely accessed and used from any thread.
@interface OWSBlockingManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

- (void)addBlockedAddress:(SignalServiceAddress *)address;

- (void)removeBlockedAddress:(SignalServiceAddress *)address;

// When updating the block list from a sync message, we don't
// want to fire a sync message.
- (void)setBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers sendSyncMessage:(BOOL)sendSyncMessage;

@property (readonly) NSSet<SignalServiceAddress *> *blockedAddresses;
@property (readonly) NSArray<NSString *> *blockedPhoneNumbers;
@property (readonly) NSArray<NSString *> *blockedUUIDs;

@property (readonly) NSArray<NSData *> *blockedGroupIds;
@property (readonly) NSArray<TSGroupModel *> *blockedGroups;

- (void)addBlockedGroup:(TSGroupModel *)group;
- (void)removeBlockedGroupId:(NSData *)groupId;
- (nullable TSGroupModel *)cachedGroupDetailsWithGroupId:(NSData *)groupId;

- (BOOL)isAddressBlocked:(SignalServiceAddress *)address;
- (BOOL)isGroupIdBlocked:(NSData *)groupId;
- (BOOL)isThreadBlocked:(TSThread *)thread;

- (void)syncBlockList;

@end

NS_ASSUME_NONNULL_END
