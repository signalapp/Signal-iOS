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
#import "TextSecureKitEnv.h"
#import "YapDatabaseConnection+OWS.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_BlockedPhoneNumbersDidChange = @"kNSNotificationName_BlockedPhoneNumbersDidChange";
extern NSString *const kNSNotificationName_BlockedPhoneNumbersDidChange;

NSString *const kOWSBlockingManager_BlockedPhoneNumbersCollection = @"kOWSBlockingManager_BlockedPhoneNumbersCollection";
// This key is used to persist the current "blocked phone numbers" state.
NSString *const kOWSBlockingManager_BlockedPhoneNumbersKey = @"kOWSBlockingManager_BlockedPhoneNumbersKey";
// This key is used to persist the most recently synced "blocked phone numbers" state.
NSString *const kOWSBlockingManager_SyncedBlockedPhoneNumbersKey = @"kOWSBlockingManager_SyncedBlockedPhoneNumbersKey";

@interface OWSBlockingManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

// We don't store the phone numbers as instances of PhoneNumber to avoid
// consistency issues between clients, but these should all be valid e164
// phone numbers.
@property (atomic, readonly) NSMutableSet<NSString *> *blockedPhoneNumberSet;

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

// This should be called every time the block list changes.

- (void)handleUpdate
{
    // By default, always send a sync message when the block list changes.
    [self handleUpdate:YES];
}

- (void)handleUpdate:(BOOL)sendSyncMessage
{
    NSArray<NSString *> *blockedPhoneNumbers = [self blockedPhoneNumbers];

    [self.dbConnection setObject:blockedPhoneNumbers
                          forKey:kOWSBlockingManager_BlockedPhoneNumbersKey
                    inCollection:kOWSBlockingManager_BlockedPhoneNumbersCollection];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (sendSyncMessage) {
            [self sendBlockedPhoneNumbersMessage:blockedPhoneNumbers];
        } else {
            // If this update came from an incoming block list sync message,
            // update the "synced blocked phone numbers" state immediately,
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
            [self saveSyncedBlockedPhoneNumbers:blockedPhoneNumbers];
        }

        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_BlockedPhoneNumbersDidChange
                                                                 object:nil
                                                               userInfo:nil];
    });
}

// This method should only be called from within a synchronized block.
- (void)ensureLazyInitialization
{
    if (_blockedPhoneNumberSet) {
        // _blockedPhoneNumberSet has already been loaded, abort.
        return;
    }

    NSArray<NSString *> *blockedPhoneNumbers =
        [self.dbConnection objectForKey:kOWSBlockingManager_BlockedPhoneNumbersKey
                           inCollection:kOWSBlockingManager_BlockedPhoneNumbersCollection];
    _blockedPhoneNumberSet = [[NSMutableSet alloc] initWithArray:(blockedPhoneNumbers ?: [NSArray new])];

    [self syncBlockedPhoneNumbersIfNecessary];
    [self observeNotifications];
}

- (void)syncBlockedPhoneNumbers
{
    OWSAssert(_blockedPhoneNumberSet);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self sendBlockedPhoneNumbersMessage:self.blockedPhoneNumbers];
    });
}

// This method should only be called from within a synchronized block.
- (void)syncBlockedPhoneNumbersIfNecessary
{
    OWSAssert(_blockedPhoneNumberSet);

    // If we haven't yet successfully synced the current "blocked phone numbers" changes,
    // try again to sync now.
    NSArray<NSString *> *syncedBlockedPhoneNumbers =
        [self.dbConnection objectForKey:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                           inCollection:kOWSBlockingManager_BlockedPhoneNumbersCollection];
    NSSet *syncedBlockedPhoneNumberSet = [[NSSet alloc] initWithArray:(syncedBlockedPhoneNumbers ?: [NSArray new])];
    if (![_blockedPhoneNumberSet isEqualToSet:syncedBlockedPhoneNumberSet]) {
        DDLogInfo(@"%@ retrying sync of blocked phone numbers", self.logTag);
        [self sendBlockedPhoneNumbersMessage:self.blockedPhoneNumbers];
    }
}

- (void)sendBlockedPhoneNumbersMessage:(NSArray<NSString *> *)blockedPhoneNumbers
{
    OWSAssert(blockedPhoneNumbers);

    OWSBlockedPhoneNumbersMessage *message =
        [[OWSBlockedPhoneNumbersMessage alloc] initWithPhoneNumbers:blockedPhoneNumbers];

    [self.messageSender enqueueMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully sent blocked phone numbers sync message", self.logTag);

            // Record the last set of "blocked phone numbers" which we successfully synced.
            [self saveSyncedBlockedPhoneNumbers:blockedPhoneNumbers];
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send blocked phone numbers sync message with error: %@", self.logTag, error);
        }];
}

- (void)saveSyncedBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
{
    OWSAssert(blockedPhoneNumbers);

    // Record the last set of "blocked phone numbers" which we successfully synced.
    [self.dbConnection setObject:blockedPhoneNumbers
                          forKey:kOWSBlockingManager_SyncedBlockedPhoneNumbersKey
                    inCollection:kOWSBlockingManager_BlockedPhoneNumbersCollection];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppIsReady:^{
        @synchronized(self)
        {
            [self syncBlockedPhoneNumbersIfNecessary];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
