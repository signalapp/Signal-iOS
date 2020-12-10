//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSBlockingManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "MessageSender.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBlockedPhoneNumbersMessage.h"
#import "SSKEnvironment.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const kNSNotificationNameBlockListDidChange = @"kNSNotificationNameBlockListDidChange";
NSNotificationName const OWSBlockingManagerBlockedSyncDidComplete = @"OWSBlockingManagerBlockedSyncDidComplete";

// These keys are used to persist the current local "block list" state.
NSString *const kOWSBlockingManager_BlockedPhoneNumbersKey = @"kOWSBlockingManager_BlockedPhoneNumbersKey";
NSString *const kOWSBlockingManager_BlockedUUIDsKey = @"kOWSBlockingManager_BlockedUUIDsKey";
NSString *const kOWSBlockingManager_BlockedGroupMapKey = @"kOWSBlockingManager_BlockedGroupMapKey";

// These keys are used to persist the most recently synced remote "block list" state.
NSString *const kOWSBlockingManager_SyncedBlockedPhoneNumbersKey = @"kOWSBlockingManager_SyncedBlockedPhoneNumbersKey";
NSString *const kOWSBlockingManager_SyncedBlockedUUIDsKey = @"kOWSBlockingManager_SyncedBlockedUUIDsKey";
NSString *const kOWSBlockingManager_SyncedBlockedGroupIdsKey = @"kOWSBlockingManager_SyncedBlockedGroupIdsKey";

@interface OWSBlockingManager ()

// We don't store the phone numbers as instances of PhoneNumber to avoid
// consistency issues between clients, but these should all be valid e164
// phone numbers.
@property (atomic, readonly) NSMutableSet<NSString *> *blockedPhoneNumberSet;
@property (atomic, readonly) NSMutableSet<NSString *> *blockedUUIDSet;
@property (atomic, readonly) NSMutableDictionary<NSData *, TSGroupModel *> *blockedGroupMap;

@end

#pragma mark -

@implementation OWSBlockingManager

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (id<StorageServiceManagerProtocol>)storageServiceManager
{
    return SSKEnvironment.shared.storageServiceManager;
}

- (id<GroupsV2>)groupsV2
{
    return SSKEnvironment.shared.groupsV2;
}

#pragma mark -

+ (SDSKeyValueStore *)keyValueStore
{
    NSString *const kOWSBlockingManager_BlockListCollection = @"kOWSBlockingManager_BlockedPhoneNumbersCollection";
    return [[SDSKeyValueStore alloc] initWithCollection:kOWSBlockingManager_BlockListCollection];
}

#pragma mark -

+ (instancetype)shared
{
    OWSAssertDebug(SSKEnvironment.shared.blockingManager);

    return SSKEnvironment.shared.blockingManager;
}

- (instancetype)init
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();
    
    [AppReadiness runNowOrWhenAppWillBecomeReady:^{
        [self ensureLazyInitializationOnLaunch];
    }];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (MessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (void)warmCaches
{
    [self ensureLazyInitializationOnLaunch];
}

- (void)ensureLazyInitializationOnLaunch
{
    @synchronized(self)
    {
        // Clear out so we re-initialize if we ever re-run the "on launch" logic,
        // such as after a completed database transfer.
        _blockedPhoneNumberSet = nil;

        [self ensureLazyInitialization];
    }
}

- (BOOL)wasLocallyInitiatedWithBlockMode:(BlockMode)blockMode
{
    return blockMode != BlockMode_Remote;
}

#pragma mark -

- (BOOL)isThreadBlocked:(TSThread *)thread
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isAddressBlocked:contactThread.contactAddress];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return [self isGroupIdBlocked:groupThread.groupModel.groupId];
    } else {
        OWSFailDebug(@"%@ failure unexpected thread type", self.logTag);
        return NO;
    }
}

#pragma mark - Contact Blocking

- (NSSet<SignalServiceAddress *> *)blockedAddresses
{
    NSMutableSet *blockedAddresses = [NSMutableSet new];
    for (NSString *phoneNumber in self.blockedPhoneNumbers) {
        [blockedAddresses addObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
    }
    for (NSString *uuid in self.blockedUUIDs) {
        [blockedAddresses addObject:[[SignalServiceAddress alloc] initWithUuidString:uuid phoneNumber:nil]];
    }
    // TODO UUID - optimize this. Maybe blocking manager should store a SignalServiceAddressSet as
    // it's state instead of the two separate sets.
    return blockedAddresses;
}

- (BOOL)addBlockedAddressLocally:(SignalServiceAddress *)address blockMode:(BlockMode)blockMode;
{
    OWSAssertDebug(address.isValid);

    OWSLogInfo(@"addBlockedAddress: %@", address);

    BOOL wasBlocked = [self isAddressBlocked:address];
    BOOL didChange = NO;

    @synchronized(self)
    {
        [self ensureLazyInitialization];

        if (address.phoneNumber && ![_blockedPhoneNumberSet containsObject:address.phoneNumber]) {
            didChange = YES;
            [_blockedPhoneNumberSet addObject:address.phoneNumber];
        }

        if (address.uuidString && ![_blockedUUIDSet containsObject:address.uuidString]) {
            didChange = YES;
            [_blockedUUIDSet addObject:address.uuidString];
        }
    }

    BOOL wasLocallyInitiated = [self wasLocallyInitiatedWithBlockMode:blockMode];
    if (wasLocallyInitiated && wasBlocked != [self isAddressBlocked:address]) {
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAddresses:@[ address ]];
    }

    return didChange;
}

- (void)addBlockedAddress:(SignalServiceAddress *)address blockMode:(BlockMode)blockMode;
{
    if ([self addBlockedAddressLocally:address blockMode:blockMode]) {
        BOOL wasLocallyInitiated = [self wasLocallyInitiatedWithBlockMode:blockMode];
        [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
    }
}

- (void)addBlockedAddress:(SignalServiceAddress *)address
                blockMode:(BlockMode)blockMode
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if ([self addBlockedAddressLocally:address blockMode:blockMode]) {
        BOOL wasLocallyInitiated = [self wasLocallyInitiatedWithBlockMode:blockMode];
        [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
    }
}

- (BOOL)removeBlockedAddressLocally:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    OWSAssertDebug(address.isValid);

    OWSLogInfo(@"removeBlockedAddress: %@", address);

    BOOL wasBlocked = [self isAddressBlocked:address];
    BOOL didChange = NO;

    @synchronized(self)
    {
        [self ensureLazyInitialization];

        if (address.phoneNumber && [_blockedPhoneNumberSet containsObject:address.phoneNumber]) {
            didChange = YES;
            [_blockedPhoneNumberSet removeObject:address.phoneNumber];
        }

        if (address.uuidString && [_blockedUUIDSet containsObject:address.uuidString]) {
            didChange = YES;
            [_blockedUUIDSet removeObject:address.uuidString];
        }
    }

    // The block state changed, schedule a backup with the storage service
    if (wasLocallyInitiated && wasBlocked != [self isAddressBlocked:address]) {
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAddresses:@[ address ]];
    }

    return didChange;
}

- (void)removeBlockedAddress:(SignalServiceAddress *)address wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    if ([self removeBlockedAddressLocally:address wasLocallyInitiated:wasLocallyInitiated]) {
        [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
    }
}

- (void)removeBlockedAddress:(SignalServiceAddress *)address
         wasLocallyInitiated:(BOOL)wasLocallyInitiated
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if ([self removeBlockedAddressLocally:address wasLocallyInitiated:wasLocallyInitiated]) {
        [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
    }
}

- (void)processIncomingSyncWithBlockedPhoneNumbers:(nullable NSSet<NSString *> *)blockedPhoneNumbers
                                      blockedUUIDs:(nullable NSSet<NSUUID *> *)blockedUUIDs
                                   blockedGroupIds:(nullable NSSet<NSData *> *)blockedGroupIds
                                       transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);

    OWSLogInfo(@"");

    [transaction addAsyncCompletion:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:OWSBlockingManagerBlockedSyncDidComplete object:nil];
    }];

    BOOL hasGroupChanges = NO;
    NSDictionary<NSData *, TSGroupModel *> *oldGroupMap;

    @synchronized(self)
    {
        // this could deadlock
        [self ensureLazyInitialization];

        BOOL hasChanges = NO;

        if (blockedPhoneNumbers != nil && ![_blockedPhoneNumberSet isEqualToSet:blockedPhoneNumbers]) {
            hasChanges = YES;
            _blockedPhoneNumberSet = [blockedPhoneNumbers mutableCopy];
        }

        if (blockedUUIDs != nil) {
            NSMutableSet<NSString *> *blockedUUIDstrings = [NSMutableSet new];
            for (NSUUID *uuid in blockedUUIDs) {
                // since we store uuidStrings, rather than UUIDs, we need to
                // be sure to round-trip any foreign input to ensure consistent
                // serialization.
                OWSAssertDebug([uuid isKindOfClass:[NSUUID class]]);
                [blockedUUIDstrings addObject:uuid.UUIDString];
            }
            if (![_blockedUUIDSet isEqualToSet:blockedUUIDstrings]) {
                hasChanges = YES;
                _blockedUUIDSet = blockedUUIDstrings;
            }
        }

        if (blockedGroupIds != nil && ![[NSSet setWithArray:_blockedGroupMap.allKeys] isEqualToSet:blockedGroupIds]) {
            hasChanges = YES;
            hasGroupChanges = YES;
        }

        if (!hasChanges) {
            return;
        }

        oldGroupMap = [self.blockedGroupMap copy];
    }

    // Re-generate the group map only if the groupIds have changed.
    if (hasGroupChanges) {
        NSMutableDictionary<NSData *, TSGroupModel *> *newGroupMap = [NSMutableDictionary new];

        for (NSData *groupId in blockedGroupIds) {
            // We store the list of blocked groups as GroupModels (not group ids)
            // so that we can display the group names in the block list UI, if
            // possible.
            //
            // * If we have an existing group model, we use it to preserve the group name.
            // * If we can find the group thread, we use it to preserve the group name.
            // * If we only know the group id, we use a "fake" group model with only the group id.
            TSGroupModel *_Nullable oldGroupModel = oldGroupMap[groupId];
            if (oldGroupModel != nil) {
                newGroupMap[groupId] = oldGroupModel;
                continue;
            }

            [TSGroupThread ensureGroupIdMappingForGroupId:groupId transaction:transaction];
            TSGroupThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
            if (groupThread != nil) {
                newGroupMap[groupId] = groupThread.groupModel;
                continue;
            }

            TSGroupModel *_Nullable groupModel = [GroupManager fakeGroupModelWithGroupId:groupId
                                                                             transaction:transaction];
            if (groupModel != nil) {
                newGroupMap[groupId] = groupModel;
            } else {
                OWSFailDebug(@"Couldn't block group: %@", groupId);
            }
        }

        @synchronized(self) {
            _blockedGroupMap = newGroupMap;
        }
    }

    [self handleUpdateAndSendSyncMessage:NO transaction:transaction];
}

- (NSArray<NSString *> *)blockedPhoneNumbers
{
    @synchronized(self)
    {
        [self ensureLazyInitialization];

        return [_blockedPhoneNumberSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
}

- (NSArray<NSString *> *)blockedUUIDs
{
    @synchronized(self) {
        [self ensureLazyInitialization];

        return [_blockedUUIDSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
}

- (BOOL)isAddressBlocked:(SignalServiceAddress *)address
{
    OWSAssertDebug(self.isInitialized);

    return [self.blockedPhoneNumbers containsObject:address.phoneNumber] ||
        [self.blockedUUIDs containsObject:address.uuidString];
}

#pragma mark - Group Blocking

- (NSArray<NSData *> *)blockedGroupIds
{
    @synchronized(self) {
        [self ensureLazyInitialization];
        return self.blockedGroupMap.allKeys;
    }
}

- (NSArray<TSGroupModel *> *)blockedGroups
{
    @synchronized(self) {
        [self ensureLazyInitialization];
        return self.blockedGroupMap.allValues;
    }
}

- (BOOL)isGroupIdBlocked:(NSData *)groupId
{
    OWSAssertDebug(self.isInitialized);

    return self.blockedGroupMap[groupId] != nil;
}

- (nullable TSGroupModel *)cachedGroupDetailsWithGroupId:(NSData *)groupId
{
    @synchronized(self) {
        return self.blockedGroupMap[groupId];
    }
}

- (void)addBlockedGroup:(TSGroupModel *)groupModel blockMode:(BlockMode)blockMode
{
    NSData *groupId = groupModel.groupId;
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if ([self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }

        self.blockedGroupMap[groupId] = groupModel;
    }

    // Open a sneaky transaction and quit the group if we're a member
    if ([groupModel.groupMembers containsObject:TSAccountManager.localAddress]) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [TSGroupThread ensureGroupIdMappingForGroupId:groupId transaction:transaction];
            TSGroupThread *groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];
            [GroupManager leaveGroupOrDeclineInviteAsyncWithoutUIWithGroupThread:groupThread
                                                                     transaction:transaction
                                                                         success:nil];
        });
    }

    BOOL wasLocallyInitiated = [self wasLocallyInitiatedWithBlockMode:blockMode];
    [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
}

- (void)addBlockedGroup:(TSGroupModel *)groupModel
              blockMode:(BlockMode)blockMode
            transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupModel);
    [self addBlockedGroupId:groupModel.groupId blockMode:blockMode transaction:transaction];
}

- (void)addBlockedGroupId:(NSData *)groupId
                blockMode:(BlockMode)blockMode
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    BOOL wasLocallyInitiated = [self wasLocallyInitiatedWithBlockMode:blockMode];

    @synchronized(self) {
        [self ensureLazyInitialization];

        if ([self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }

        [TSGroupThread ensureGroupIdMappingForGroupId:groupId transaction:transaction];
        TSGroupThread *_Nullable groupThread = [TSGroupThread fetchWithGroupId:groupId transaction:transaction];

        // Quit the group if we're a member
        BOOL isInGroup = groupThread.isLocalUserMemberOfAnyKind;
        if (blockMode == BlockMode_LocalShouldLeaveGroups && isInGroup) {
            [GroupManager leaveGroupOrDeclineInviteAsyncWithoutUIWithGroupThread:groupThread
                                                                     transaction:transaction
                                                                         success:nil];
        }

        if (groupThread != nil) {
            self.blockedGroupMap[groupId] = groupThread.groupModel;
        } else {
            OWSFailDebug(@"missing group thread");
        }

        if (wasLocallyInitiated) {
            [self.storageServiceManager recordPendingUpdatesWithGroupModel:groupThread.groupModel];
        }
    }

    [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
}

- (void)removeBlockedGroupId:(NSData *)groupId wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if (![self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }

        TSGroupModel *_Nullable groupModel = self.blockedGroupMap[groupId];

        [self.blockedGroupMap removeObjectForKey:groupId];

        if (wasLocallyInitiated && groupModel != nil) {
            [self.storageServiceManager recordPendingUpdatesWithGroupModel:groupModel];
        }
    }

    [self handleUpdateWithSneakyTransactionAndSendSyncMessage:wasLocallyInitiated];
}

- (void)removeBlockedGroupId:(NSData *)groupId
         wasLocallyInitiated:(BOOL)wasLocallyInitiated
                 transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    OWSLogInfo(@"groupId: %@", groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if (![self isGroupIdBlocked:groupId]) {
            // Ignore redundant changes.
            return;
        }

        [self.blockedGroupMap removeObjectForKey:groupId];
    }

    [self handleUpdateAndSendSyncMessage:wasLocallyInitiated transaction:transaction];
}


#pragma mark - Thread Blocking

- (void)addBlockedThread:(TSThread *)thread
               blockMode:(BlockMode)blockMode
             transaction:(SDSAnyWriteTransaction *)transaction
{
    if (thread.isGroupThread) {
        OWSAssertDebug([thread isKindOfClass:[TSGroupThread class]]);
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self addBlockedGroup:groupThread.groupModel blockMode:blockMode transaction:transaction];
    } else {
        OWSAssertDebug([thread isKindOfClass:[TSContactThread class]]);
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addBlockedAddress:contactThread.contactAddress blockMode:blockMode transaction:transaction];
    }
}

- (void)addBlockedThread:(TSThread *)thread blockMode:(BlockMode)blockMode
{
    if ([self isThreadBlocked:thread]) {
        return;
    }
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self addBlockedThread:thread blockMode:blockMode transaction:transaction];
    });
}

- (void)removeBlockedThread:(TSThread *)thread
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction
{
    if (thread.isGroupThread) {
        OWSAssertDebug([thread isKindOfClass:[TSGroupThread class]]);
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self removeBlockedGroupId:groupThread.groupModel.groupId
               wasLocallyInitiated:wasLocallyInitiated
                       transaction:transaction];
    } else {
        OWSAssertDebug([thread isKindOfClass:[TSContactThread class]]);
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self removeBlockedAddress:contactThread.contactAddress
               wasLocallyInitiated:wasLocallyInitiated
                       transaction:transaction];
    }
}

- (void)removeBlockedThread:(TSThread *)thread wasLocallyInitiated:(BOOL)wasLocallyInitiated
{
    if (![self isThreadBlocked:thread]) {
        return;
    }
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self removeBlockedThread:thread wasLocallyInitiated:wasLocallyInitiated transaction:transaction];
    });
}

#pragma mark - Updates

// This should be called every time the block list changes.

- (void)handleUpdateWithSneakyTransactionAndSendSyncMessage:(BOOL)sendSyncMessage
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self handleUpdateAndSendSyncMessage:sendSyncMessage transaction:transaction];
    });
}

- (void)handleUpdateAndSendSyncMessage:(BOOL)sendSyncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    NSArray<NSString *> *blockedPhoneNumbers = [self blockedPhoneNumbers];
    NSArray<NSString *> *blockedUUIDs = [self blockedUUIDs];

    NSDictionary<NSData *, TSGroupModel *> *blockedGroupMap;
    @synchronized(self) {
        blockedGroupMap = [self.blockedGroupMap copy];
    }
    NSArray<NSData *> *blockedGroupIds = blockedGroupMap.allKeys;

    [OWSBlockingManager.keyValueStore setObject:blockedPhoneNumbers
                                            key:kOWSBlockingManager_BlockedPhoneNumbersKey
                                    transaction:transaction];
    [OWSBlockingManager.keyValueStore setObject:blockedUUIDs
                                            key:kOWSBlockingManager_BlockedUUIDsKey
                                    transaction:transaction];
    [OWSBlockingManager.keyValueStore setObject:blockedGroupMap
                                            key:kOWSBlockingManager_BlockedGroupMapKey
                                    transaction:transaction];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (sendSyncMessage) {
            [self sendBlockListSyncMessageWithPhoneNumbers:blockedPhoneNumbers
                                                     uuids:blockedUUIDs
                                                  groupIds:blockedGroupIds];
        } else {
            // If this update came from an incoming block list sync message,
            // update the "synced blocked list" state immediately,
            // since we're now in sync.
            //
            // There could be data loss if both clients modify the block list
            // at the same time, but:
            //
            // a) Block list changes will be rare.
            // b) Conflicting block list changes will be even rarer.
            // c) It's unlikely a user will make conflicting changes on two
            //    devices around the same time.
            // d) There isn't a good way to avoid this.
            [self saveSyncedBlockListWithPhoneNumbers:blockedPhoneNumbers uuids:blockedUUIDs groupIds:blockedGroupIds];
        }

        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationNameBlockListDidChange
                                                                 object:nil
                                                               userInfo:nil];
    });
}

// This method should only be called from within a synchronized block.
- (BOOL)isInitialized
{
    @synchronized(self) {
        return _blockedPhoneNumberSet != nil;
    }
}

// This method should only be called from within a synchronized block.
- (void)ensureLazyInitialization
{
    if (_blockedPhoneNumberSet != nil) {
        OWSAssertDebug(_blockedGroupMap);
        OWSAssertDebug(_blockedUUIDSet);

        // already loaded
        return;
    }

    OWSLogVerbose(@"");
    __block NSArray<NSString *> *_Nullable blockedPhoneNumbers;
    __block NSArray<NSString *> *blockedUUIDs;
    __block NSDictionary<NSData *, TSGroupModel *> *storedBlockedGroupMap;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        blockedPhoneNumbers =
            [OWSBlockingManager.keyValueStore getObjectForKey:kOWSBlockingManager_BlockedPhoneNumbersKey
                                                  transaction:transaction];
        blockedUUIDs = [OWSBlockingManager.keyValueStore getObjectForKey:kOWSBlockingManager_BlockedUUIDsKey
                                                             transaction:transaction];
        storedBlockedGroupMap = [OWSBlockingManager.keyValueStore getObjectForKey:kOWSBlockingManager_BlockedGroupMapKey
                                                                      transaction:transaction];
    }];
    _blockedPhoneNumberSet = [[NSMutableSet alloc] initWithArray:(blockedPhoneNumbers ?: @[])];
    _blockedUUIDSet = [[NSMutableSet alloc] initWithArray:(blockedUUIDs ?: @[])];

    if ([storedBlockedGroupMap isKindOfClass:[NSDictionary class]]) {
        _blockedGroupMap = [storedBlockedGroupMap mutableCopy];
    } else {
        _blockedGroupMap = [NSMutableDictionary new];
    }

    [self syncBlockListIfNecessary];
    [self observeNotifications];
}

- (void)syncBlockList
{
    OWSAssertDebug(_blockedPhoneNumberSet);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self sendBlockListSyncMessageWithPhoneNumbers:self.blockedPhoneNumbers
                                                 uuids:self.blockedUUIDs
                                              groupIds:self.blockedGroupIds];
    });
}

// This method should only be called from within a synchronized block.
- (void)syncBlockListIfNecessary
{
    OWSAssertDebug(_blockedPhoneNumberSet);

    // If we haven't yet successfully synced the current "block list" changes,
    // try again to sync now.
    __block NSArray<NSString *> *syncedBlockedPhoneNumbers;
    __block NSArray<NSString *> *syncedBlockedUUIDs;
    __block NSArray<NSData *> *syncedBlockedGroupIds;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        syncedBlockedPhoneNumbers =
            [OWSBlockingManager.keyValueStore getObjectForKey:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                                                  transaction:transaction];
        syncedBlockedUUIDs = [OWSBlockingManager.keyValueStore getObjectForKey:kOWSBlockingManager_SyncedBlockedUUIDsKey
                                                                   transaction:transaction];
        syncedBlockedGroupIds =
            [OWSBlockingManager.keyValueStore getObjectForKey:kOWSBlockingManager_SyncedBlockedGroupIdsKey
                                                  transaction:transaction];
    }];

    NSSet<NSString *> *syncedBlockedPhoneNumberSet = [[NSSet alloc] initWithArray:(syncedBlockedPhoneNumbers ?: @[])];
    NSSet<NSString *> *syncedBlockedUUIDsSet = [[NSSet alloc] initWithArray:(syncedBlockedUUIDs ?: @[])];
    NSSet<NSData *> *syncedBlockedGroupIdSet = [[NSSet alloc] initWithArray:(syncedBlockedGroupIds ?: @[])];

    NSArray<NSData *> *localBlockedGroupIds = self.blockedGroupIds;
    NSSet<NSData *> *localBlockedGroupIdSet = [[NSSet alloc] initWithArray:localBlockedGroupIds];

    if ([self.blockedPhoneNumberSet isEqualToSet:syncedBlockedPhoneNumberSet] &&
        [self.blockedUUIDSet isEqualToSet:syncedBlockedUUIDsSet] &&
        [localBlockedGroupIdSet isEqualToSet:syncedBlockedGroupIdSet]) {
        OWSLogVerbose(@"Ignoring redundant block list sync");
        return;
    }

    OWSLogInfo(@"retrying sync of block list");
    [self sendBlockListSyncMessageWithPhoneNumbers:self.blockedPhoneNumbers
                                             uuids:self.blockedUUIDs
                                          groupIds:localBlockedGroupIds];
}

- (void)sendBlockListSyncMessageWithPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
                                           uuids:(NSArray<NSString *> *)blockedUUIDs
                                        groupIds:(NSArray<NSData *> *)blockedGroupIds
{
    OWSAssertDebug(blockedPhoneNumbers);
    OWSAssertDebug(blockedUUIDs);
    OWSAssertDebug(blockedGroupIds);

    __block TSThread *_Nullable thread;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        thread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction];
    });
    if (thread == nil) {
        OWSFailDebug(@"Missing thread.");
        return;
    }

    OWSBlockedPhoneNumbersMessage *message = [[OWSBlockedPhoneNumbersMessage alloc] initWithThread:thread
                                                                                      phoneNumbers:blockedPhoneNumbers
                                                                                             uuids:blockedUUIDs
                                                                                          groupIds:blockedGroupIds];

    [self.messageSender sendMessage:message.asPreparer
        success:^{
            OWSLogInfo(@"Successfully sent blocked phone numbers sync message");

            // DURABLE CLEANUP - we could replace the custom durability logic in this class
            // with a durable JobQueue.
            [self saveSyncedBlockListWithPhoneNumbers:blockedPhoneNumbers uuids:blockedUUIDs groupIds:blockedGroupIds];
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to send blocked phone numbers sync message with error: %@", error);
        }];
}

/// Records the last block list which we successfully synced.
- (void)saveSyncedBlockListWithPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
                                      uuids:(NSArray<NSString *> *)blockedUUIDs
                                   groupIds:(NSArray<NSData *> *)blockedGroupIds
{
    OWSAssertDebug(blockedPhoneNumbers);
    OWSAssertDebug(blockedUUIDs);
    OWSAssertDebug(blockedGroupIds);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [OWSBlockingManager.keyValueStore setObject:blockedPhoneNumbers
                                                key:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                                        transaction:transaction];
        [OWSBlockingManager.keyValueStore setObject:blockedUUIDs
                                                key:kOWSBlockingManager_SyncedBlockedUUIDsKey
                                        transaction:transaction];
        [OWSBlockingManager.keyValueStore setObject:blockedGroupIds
                                                key:kOWSBlockingManager_SyncedBlockedGroupIdsKey
                                        transaction:transaction];
    });
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        @synchronized(self)
        {
            [self syncBlockListIfNecessary];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
