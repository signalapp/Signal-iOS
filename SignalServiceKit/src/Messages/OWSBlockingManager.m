//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBlockingManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSBlockedPhoneNumbersMessage.h"
#import "OWSMessageSender.h"
#import "OWSPrimaryStorage.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TextSecureKitEnv.h"
#import "YapDatabaseConnection+OWS.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_BlockListDidChange = @"kNSNotificationName_BlockListDidChange";

NSString *const kOWSBlockingManager_BlockListCollection = @"kOWSBlockingManager_BlockedPhoneNumbersCollection";

// These keys are used to persist the current local "block list" state.
NSString *const kOWSBlockingManager_BlockedPhoneNumbersKey = @"kOWSBlockingManager_BlockedPhoneNumbersKey";
NSString *const kOWSBlockingManager_BlockedGroupIdsKey = @"kOWSBlockingManager_BlockedGroupIdsKey";

// These keys are used to persist the most recently synced remote "block list" state.
NSString *const kOWSBlockingManager_SyncedBlockedPhoneNumbersKey = @"kOWSBlockingManager_SyncedBlockedPhoneNumbersKey";
NSString *const kOWSBlockingManager_SyncedBlockedGroupIdsKey = @"kOWSBlockingManager_SyncedBlockedGroupIdsKey";

@interface OWSBlockingManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

// We don't store the phone numbers as instances of PhoneNumber to avoid
// consistency issues between clients, but these should all be valid e164
// phone numbers.
@property (atomic, readonly) NSMutableSet<NSString *> *blockedPhoneNumberSet;
@property (atomic, readonly) NSMutableSet<NSData *> *blockedGroupIdSet;

@end

#pragma mark -

@implementation OWSBlockingManager

+ (instancetype)sharedManager
{
    static OWSBlockingManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;

    return [self initWithPrimaryStorage:primaryStorage messageSender:messageSender];
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
                         messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(primaryStorage);
    OWSAssert(messageSender);

    _dbConnection = primaryStorage.newDatabaseConnection;
    _messageSender = messageSender;

    OWSSingletonAssert();

    // Register this manager with the message sender.
    // This is a circular dependency.
    [messageSender setBlockingManager:self];

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

#pragma mark -


- (BOOL)isThreadBlocked:(TSThread *)thread
{
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        return [self isRecipientIdBlocked:contactThread.contactIdentifier];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        return [self isGroupIdBlocked:groupThread.groupModel.groupId];
    } else {
        OWSFail(@"%@ failure unexpected thread type", self.logTag);
        return NO;
    }
}

#pragma mark - Contact Blocking

- (void)addBlockedPhoneNumber:(NSString *)phoneNumber
{
    OWSAssert(phoneNumber.length > 0);

    DDLogInfo(@"%@ addBlockedPhoneNumber: %@", self.logTag, phoneNumber);

    @synchronized(self)
    {
        [self ensureLazyInitialization];

        if ([_blockedPhoneNumberSet containsObject:phoneNumber]) {
            // Ignore redundant changes.
            return;
        }

        [_blockedPhoneNumberSet addObject:phoneNumber];
    }

    [self handleUpdate];
}

- (void)removeBlockedPhoneNumber:(NSString *)phoneNumber
{
    OWSAssert(phoneNumber.length > 0);

    DDLogInfo(@"%@ removeBlockedPhoneNumber: %@", self.logTag, phoneNumber);

    @synchronized(self)
    {
        [self ensureLazyInitialization];

        if (![_blockedPhoneNumberSet containsObject:phoneNumber]) {
            // Ignore redundant changes.
            return;
        }

        [_blockedPhoneNumberSet removeObject:phoneNumber];
    }

    [self handleUpdate];
}

- (void)setBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers sendSyncMessage:(BOOL)sendSyncMessage
{
    OWSAssert(blockedPhoneNumbers != nil);

    DDLogInfo(@"%@ setBlockedPhoneNumbers: %d", self.logTag, (int)blockedPhoneNumbers.count);

    @synchronized(self)
    {
        [self ensureLazyInitialization];

        NSSet *newSet = [NSSet setWithArray:blockedPhoneNumbers];
        if ([_blockedPhoneNumberSet isEqualToSet:newSet]) {
            return;
        }

        _blockedPhoneNumberSet = [newSet mutableCopy];
    }

    [self handleUpdate:sendSyncMessage];
}

- (NSArray<NSString *> *)blockedPhoneNumbers
{
    @synchronized(self)
    {
        [self ensureLazyInitialization];

        return [_blockedPhoneNumberSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
}

- (BOOL)isRecipientIdBlocked:(NSString *)recipientId
{
    return [self.blockedPhoneNumbers containsObject:recipientId];
}

#pragma mark - Group Blocking

- (NSArray<NSData *> *)blockedGroupIds
{
    @synchronized(self) {
        [self ensureLazyInitialization];

        return _blockedGroupIdSet.allObjects;
    }
}

- (BOOL)isGroupIdBlocked:(NSData *)groupId
{
    return [self.blockedGroupIds containsObject:groupId];
}

- (void)addBlockedGroupId:(NSData *)groupId
{
    OWSAssert(groupId.length > 0);

    DDLogInfo(@"%@ addBlockedGroupId: %@", self.logTag, groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if ([_blockedGroupIdSet containsObject:groupId]) {
            // Ignore redundant changes.
            return;
        }

        [_blockedGroupIdSet addObject:groupId];
    }

    [self handleUpdate];
}

- (void)removeBlockedGroupId:(NSData *)groupId
{
    OWSAssert(groupId.length > 0);

    DDLogInfo(@"%@ removeBlockedGroupId: %@", self.logTag, groupId);

    @synchronized(self) {
        [self ensureLazyInitialization];

        if (![_blockedGroupIdSet containsObject:groupId]) {
            // Ignore redundant changes.
            return;
        }

        [_blockedGroupIdSet removeObject:groupId];
    }

    [self handleUpdate];
}


#pragma mark - Updates

// This should be called every time the block list changes.

- (void)handleUpdate
{
    // By default, always send a sync message when the block list changes.
    [self handleUpdate:YES];
}

// TODO label the `sendSyncMessage` param
- (void)handleUpdate:(BOOL)sendSyncMessage
{
    NSArray<NSString *> *blockedPhoneNumbers = [self blockedPhoneNumbers];

    [self.dbConnection setObject:blockedPhoneNumbers
                          forKey:kOWSBlockingManager_BlockedPhoneNumbersKey
                    inCollection:kOWSBlockingManager_BlockListCollection];

    NSArray<NSData *> *blockedGroupIds = [self blockedGroupIds];

    [self.dbConnection setObject:blockedGroupIds
                          forKey:kOWSBlockingManager_BlockedGroupIdsKey
                    inCollection:kOWSBlockingManager_BlockListCollection];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (sendSyncMessage) {
            [self sendBlockListSyncMessageWithPhoneNumbers:blockedPhoneNumbers groupIds:blockedGroupIds];
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
            [self saveSyncedBlockListWithPhoneNumbers:blockedPhoneNumbers groupIds:blockedGroupIds];
        }

        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_BlockListDidChange
                                                                 object:nil
                                                               userInfo:nil];
    });
}

// This method should only be called from within a synchronized block.
- (void)ensureLazyInitialization
{
    if (_blockedPhoneNumberSet) {
        OWSAssert(_blockedGroupIdSet);

        // already loaded
        return;
    }

    NSArray<NSString *> *blockedPhoneNumbers =
        [self.dbConnection objectForKey:kOWSBlockingManager_BlockedPhoneNumbersKey
                           inCollection:kOWSBlockingManager_BlockListCollection];
    _blockedPhoneNumberSet = [[NSMutableSet alloc] initWithArray:(blockedPhoneNumbers ?: [NSArray new])];

    NSArray<NSData *> *blockedGroupIds = [self.dbConnection objectForKey:kOWSBlockingManager_BlockedGroupIdsKey
                                                            inCollection:kOWSBlockingManager_BlockListCollection];
    _blockedGroupIdSet = [[NSMutableSet alloc] initWithArray:(blockedGroupIds ?: [NSArray new])];

    [self syncBlockListIfNecessary];
    [self observeNotifications];
}

- (void)syncBlockList
{
    OWSAssert(_blockedPhoneNumberSet);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self sendBlockListSyncMessageWithPhoneNumbers:self.blockedPhoneNumbers groupIds:self.blockedGroupIds];
    });
}

// This method should only be called from within a synchronized block.
- (void)syncBlockListIfNecessary
{
    OWSAssert(_blockedPhoneNumberSet);

    // If we haven't yet successfully synced the current "block list" changes,
    // try again to sync now.
    NSArray<NSString *> *syncedBlockedPhoneNumbers =
        [self.dbConnection objectForKey:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                           inCollection:kOWSBlockingManager_BlockListCollection];
    NSSet<NSString *> *syncedBlockedPhoneNumberSet =
        [[NSSet alloc] initWithArray:(syncedBlockedPhoneNumbers ?: [NSArray new])];

    NSArray<NSData *> *syncedBlockedGroupIds =
        [self.dbConnection objectForKey:kOWSBlockingManager_SyncedBlockedGroupIdsKey
                           inCollection:kOWSBlockingManager_BlockListCollection];
    NSSet<NSData *> *syncedBlockedGroupIdSet = [[NSSet alloc] initWithArray:(syncedBlockedGroupIds ?: [NSArray new])];

    if ([self.blockedPhoneNumberSet isEqualToSet:syncedBlockedPhoneNumberSet] &&
        [self.blockedGroupIdSet isEqualToSet:syncedBlockedGroupIdSet]) {
        DDLogVerbose(@"Ignoring redundant block list sync");
        return;
    }

    DDLogInfo(@"%@ retrying sync of block list", self.logTag);
    [self sendBlockListSyncMessageWithPhoneNumbers:self.blockedPhoneNumbers groupIds:self.blockedGroupIds];
}

- (void)sendBlockListSyncMessageWithPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
                                        groupIds:(NSArray<NSData *> *)blockedGroupIds
{
    OWSAssert(blockedPhoneNumbers);
    OWSAssert(blockedGroupIds);

    OWSBlockedPhoneNumbersMessage *message =
        [[OWSBlockedPhoneNumbersMessage alloc] initWithPhoneNumbers:blockedPhoneNumbers groupIds:blockedGroupIds];

    [self.messageSender enqueueMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully sent blocked phone numbers sync message", self.logTag);

            // Record the last set of "blocked phone numbers" which we successfully synced.
            [self saveSyncedBlockListWithPhoneNumbers:blockedPhoneNumbers groupIds:blockedGroupIds];
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send blocked phone numbers sync message with error: %@", self.logTag, error);
        }];
}

/// Records the last block list which we successfully synced.
- (void)saveSyncedBlockListWithPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
                                   groupIds:(NSArray<NSData *> *)blockedGroupIds
{
    OWSAssert(blockedPhoneNumbers);
    OWSAssert(blockedGroupIds);

    [self.dbConnection setObject:blockedPhoneNumbers
                          forKey:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                    inCollection:kOWSBlockingManager_BlockListCollection];

    [self.dbConnection setObject:blockedGroupIds
                          forKey:kOWSBlockingManager_SyncedBlockedGroupIdsKey
                    inCollection:kOWSBlockingManager_BlockListCollection];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppIsReady:^{
        @synchronized(self)
        {
            [self syncBlockListIfNecessary];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
