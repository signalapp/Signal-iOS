//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;
@class SSKProtoSyncMessageBlocked;
@class SignalServiceAddress;
@class TSGroupModel;
@class TSThread;

extern NSNotificationName const kNSNotificationName_BlockListDidChange;
extern NSNotificationName const OWSBlockingManagerBlockedSyncDidComplete;

// This class can be safely accessed and used from any thread.
@interface OWSBlockingManager : NSObject

+ (SDSKeyValueStore *)keyValueStore;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

+ (instancetype)sharedManager;

- (void)addBlockedAddress:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated;

- (void)addBlockedAddress:(SignalServiceAddress *)address
      wasLocallyInitiated:(BOOL)wasLocallyInitiated
              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removeBlockedAddress:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated;

- (void)removeBlockedAddress:(SignalServiceAddress *)address
         wasLocallyInitiated:(BOOL)wasLocallyInitiated
                 transaction:(SDSAnyWriteTransaction *)transaction;

- (void)processIncomingSyncWithBlockedPhoneNumbers:(nullable NSSet<NSString *> *)blockedPhoneNumbers
                                      blockedUUIDs:(nullable NSSet<NSUUID *> *)blockedUUIDs
                                   blockedGroupIds:(nullable NSSet<NSData *> *)blockedGroupIds
                                       transaction:(SDSAnyWriteTransaction *)transaction;

@property (readonly) NSSet<SignalServiceAddress *> *blockedAddresses;
@property (readonly) NSArray<NSString *> *blockedPhoneNumbers;
@property (readonly) NSArray<NSString *> *blockedUUIDs;

@property (readonly) NSArray<NSData *> *blockedGroupIds;
@property (readonly) NSArray<TSGroupModel *> *blockedGroups;

- (void)addBlockedGroup:(TSGroupModel *)groupModel wasLocallyInitiated:(BOOL)wasLocallyInitiated;

- (void)addBlockedGroup:(TSGroupModel *)groupModel
    wasLocallyInitiated:(BOOL)wasLocallyInitiated
            transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addBlockedGroupId:(NSData *)groupId
      wasLocallyInitiated:(BOOL)wasLocallyInitiated
              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removeBlockedGroupId:(NSData *)groupId wasLocallyInitiated:(BOOL)wasLocallyInitiated;

- (void)removeBlockedGroupId:(NSData *)groupId
         wasLocallyInitiated:(BOOL)wasLocallyInitiated
                 transaction:(SDSAnyWriteTransaction *)transaction;

- (nullable TSGroupModel *)cachedGroupDetailsWithGroupId:(NSData *)groupId;

- (void)addBlockedThread:(TSThread *)thread wasLocallyInitiated:(BOOL)wasLocallyInitiated;
- (void)addBlockedThread:(TSThread *)thread
     wasLocallyInitiated:(BOOL)wasLocallyInitiated
             transaction:(SDSAnyWriteTransaction *)transaction;

- (void)removeBlockedThread:(TSThread *)thread wasLocallyInitiated:(BOOL)wasLocallyInitiated;
- (void)removeBlockedThread:(TSThread *)thread
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isThreadBlocked:(TSThread *)thread;

- (BOOL)isAddressBlocked:(SignalServiceAddress *)address;
- (BOOL)isGroupIdBlocked:(NSData *)groupId;

- (void)syncBlockList;

- (void)warmCaches;

@end

NS_ASSUME_NONNULL_END
