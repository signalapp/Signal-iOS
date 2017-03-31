//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSBlockingManager.h"
#import "OWSBlockedPhoneNumbersMessage.h"
#import "OWSMessageSender.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

NSString * const kNSNotificationName_BlockedPhoneNumbersDidChange = @"kNSNotificationName_BlockedPhoneNumbersDidChange";
NSString * const kTSStorageManager_BlockedPhoneNumbersCollection = @"kTSStorageManager_BlockedPhoneNumbersCollection";
// This key is used to persist the current "blocked phone numbers" state.
NSString * const kTSStorageManager_BlockedPhoneNumbersKey = @"kTSStorageManager_BlockedPhoneNumbersKey";
// This key is used to persist the most recently synced "blocked phone numbers" state.
NSString *const kTSStorageManager_SyncedBlockedPhoneNumbersKey = @"kTSStorageManager_SyncedBlockedPhoneNumbersKey";

@interface TSBlockingManager ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

// We don't store the phone numbers as instances of PhoneNumber to avoid
// consistency issues between clients, but these should all be valid e164
// phone numbers.
@property (nonatomic, readonly) NSMutableSet<NSString *> *blockedPhoneNumberSet;

@end

#pragma mark -

@implementation TSBlockingManager

+ (instancetype)sharedManager {
    static TSBlockingManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;

    return [self initStorageManager:storageManager
                      messageSender:messageSender];
}

- (instancetype)initStorageManager:(TSStorageManager *)storageManager messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(storageManager);
    OWSAssert(messageSender);
    
    _storageManager = storageManager;
    _messageSender = messageSender;

    [self loadBlockedPhoneNumbers];

    return self;
}


- (void)addBlockedPhoneNumber:(NSString *)phoneNumber {
    OWSAssert(phoneNumber.length > 0);
    
    @synchronized (self) {
        if ([_blockedPhoneNumberSet containsObject:phoneNumber]) {
            return;
        }
        
        [_blockedPhoneNumberSet addObject:phoneNumber];
    }

    [self handleUpdate:NO];
}

- (void)removeBlockedPhoneNumber:(NSString *)phoneNumber {
    OWSAssert(phoneNumber.length > 0);
    
    @synchronized (self) {
        if (![_blockedPhoneNumberSet containsObject:phoneNumber]) {
            return;
        }
        
        [_blockedPhoneNumberSet removeObject:phoneNumber];
    }

    [self handleUpdate:NO];
}

- (void)setBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers skipSyncMessage:(BOOL)skipSyncMessage
{
    OWSAssert(blockedPhoneNumbers != nil);

    @synchronized (self) {
        NSSet *newSet = [NSSet setWithArray:blockedPhoneNumbers];
        if ([_blockedPhoneNumberSet isEqualToSet:newSet]) {
            return;
        }
        
        _blockedPhoneNumberSet = [newSet mutableCopy];
    }

    [self handleUpdate:skipSyncMessage];
}

- (NSArray<NSString *> *)blockedPhoneNumbers {
    @synchronized (self) {
        return [_blockedPhoneNumberSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
}

// This should be called every time the block list changes.
- (void)handleUpdate:(BOOL)skipSyncMessage
{
    NSArray<NSString *> *blockedPhoneNumbers = [self blockedPhoneNumbers];
    
    [self saveBlockedPhoneNumbers:blockedPhoneNumbers];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!skipSyncMessage) {
            [self sendBlockedPhoneNumbersMessage:blockedPhoneNumbers];
        } else {
            // If this update came from an incoming blocklist sync message,
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

        [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationName_BlockedPhoneNumbersDidChange
                                                            object:nil
                                                          userInfo:nil];
    });
}

- (void)saveBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
{
    OWSAssert(blockedPhoneNumbers);

    [_storageManager setObject:blockedPhoneNumbers
                        forKey:kTSStorageManager_BlockedPhoneNumbersKey
                  inCollection:kTSStorageManager_BlockedPhoneNumbersCollection];
}

// We don't need to synchronize this method since it should only be called by the constructor.
- (void)loadBlockedPhoneNumbers
{
    NSArray<NSString *> *blockedPhoneNumbers = [_storageManager objectForKey:kTSStorageManager_BlockedPhoneNumbersKey
                                                                inCollection:kTSStorageManager_BlockedPhoneNumbersCollection];
    _blockedPhoneNumberSet = [[NSMutableSet alloc] initWithArray:(blockedPhoneNumbers ?: [NSArray new])];

    // If we haven't yet successfully synced the current "blocked phone numbers" changes,
    // try again to sync now.
    NSArray<NSString *> *syncedBlockedPhoneNumbers =
        [_storageManager objectForKey:kTSStorageManager_SyncedBlockedPhoneNumbersKey
                         inCollection:kTSStorageManager_BlockedPhoneNumbersCollection];
    NSSet *syncedBlockedPhoneNumberSet = [[NSSet alloc] initWithArray:(syncedBlockedPhoneNumbers ?: [NSArray new])];
    if (![_blockedPhoneNumberSet isEqualToSet:syncedBlockedPhoneNumberSet]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendBlockedPhoneNumbersMessage:blockedPhoneNumbers];
        });
    }
}

- (void)sendBlockedPhoneNumbersMessage:(NSArray<NSString *> *)blockedPhoneNumbers
{
    OWSAssert(blockedPhoneNumbers);

    OWSBlockedPhoneNumbersMessage *message =
        [[OWSBlockedPhoneNumbersMessage alloc] initWithPhoneNumbers:blockedPhoneNumbers];

    [self.messageSender sendMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully sent blocked phone numbers", self.tag);

            // Record the last set of "blocked phone numbers" which we successfully synced.
            [self saveSyncedBlockedPhoneNumbers:blockedPhoneNumbers];
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send blocked phone numbers with error: %@", self.tag, error);

            // TODO: We might want to retry more often than just app launch.
        }];
}

- (void)saveSyncedBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers
{
    OWSAssert(blockedPhoneNumbers);

    // Record the last set of "blocked phone numbers" which we successfully synced.
    [_storageManager setObject:blockedPhoneNumbers
                        forKey:kTSStorageManager_SyncedBlockedPhoneNumbersKey
                  inCollection:kTSStorageManager_BlockedPhoneNumbersCollection];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
