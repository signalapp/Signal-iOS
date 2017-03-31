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
    
    [self handleUpdate];
}

- (void)removeBlockedPhoneNumber:(NSString *)phoneNumber {
    OWSAssert(phoneNumber.length > 0);
    
    @synchronized (self) {
        if (![_blockedPhoneNumberSet containsObject:phoneNumber]) {
            return;
        }
        
        [_blockedPhoneNumberSet removeObject:phoneNumber];
    }
    
    [self handleUpdate];
}

- (void)setBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers {
    OWSAssert(blockedPhoneNumbers != nil);

    @synchronized (self) {
        NSSet *newSet = [NSSet setWithArray:blockedPhoneNumbers];
        if ([_blockedPhoneNumberSet isEqualToSet:newSet]) {
            return;
        }
        
        _blockedPhoneNumberSet = [newSet mutableCopy];
    }
    
    [self handleUpdate];
}

- (NSArray<NSString *> *)blockedPhoneNumbers {
    @synchronized (self) {
        return [_blockedPhoneNumberSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    }
}

// This should be called every time the block list changes.
- (void)handleUpdate {
    NSArray<NSString *> *blockedPhoneNumbers = [self blockedPhoneNumbers];
    
    [self saveBlockedPhoneNumbers:blockedPhoneNumbers];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self sendBlockedPhoneNumbersMessage:blockedPhoneNumbers];
        
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
            [_storageManager setObject:blockedPhoneNumbers
                                forKey:kTSStorageManager_SyncedBlockedPhoneNumbersKey
                          inCollection:kTSStorageManager_BlockedPhoneNumbersCollection];
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send blocked phone numbers with error: %@", self.tag, error);
        }];
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
