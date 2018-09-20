//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class TSGroupModel;
@class TSThread;

extern NSString *const kNSNotificationName_BlockListDidChange;

// This class can be safely accessed and used from any thread.
@interface OWSBlockingManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

- (void)addBlockedPhoneNumber:(NSString *)phoneNumber;

- (void)removeBlockedPhoneNumber:(NSString *)phoneNumber;

// When updating the block list from a sync message, we don't
// want to fire a sync message.
- (void)setBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers sendSyncMessage:(BOOL)sendSyncMessage;

// TODO convert to property
- (NSArray<NSString *> *)blockedPhoneNumbers;

@property (readonly) NSArray<NSData *> *blockedGroupIds;
@property (readonly) NSArray<TSGroupModel *> *blockedGroups;

- (void)addBlockedGroup:(TSGroupModel *)group;
- (void)removeBlockedGroupId:(NSData *)groupId;
- (nullable TSGroupModel *)cachedGroupDetailsWithGroupId:(NSData *)groupId;

- (BOOL)isRecipientIdBlocked:(NSString *)recipientId;
- (BOOL)isGroupIdBlocked:(NSData *)groupId;
- (BOOL)isThreadBlocked:(TSThread *)thread;

- (void)syncBlockList;

@end

NS_ASSUME_NONNULL_END
