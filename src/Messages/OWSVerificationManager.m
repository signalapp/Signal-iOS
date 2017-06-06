//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationManager.h"
#import "OWSMessageSender.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_VerificationStateDidChange = @"kNSNotificationName_VerificationStateDidChange";

NSString *const kOWSVerificationManager_Collection = @"kOWSVerificationManager_Collection";
// This key is used to persist the current "verification map" state.
NSString *const kOWSVerificationManager_VerificationMapKey = @"kOWSVerificationManager_VerificationMapKey";
//// This key is used to persist the most recently synced "blocked phone numbers" state.
//NSString *const kOWSVerificationManager_SyncedBlockedPhoneNumbersKey = @"kOWSVerificationManager_SyncedBlockedPhoneNumbersKey";

NSString *OWSVerificationStateToString(OWSVerificationState verificationState)
{
    switch (verificationState) {
        case OWSVerificationStateDefault:
            return @"OWSVerificationStateDefault";
        case OWSVerificationStateVerified:
            return @"OWSVerificationStateVerified";
        case OWSVerificationStateNoLongerVerified:
            return @"OWSVerificationStateNoLongerVerified";
    }
}

@interface OWSVerificationManager ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

// We don't store the phone numbers as instances of PhoneNumber to avoid
// consistency issues between clients, but these should all be valid e164
// phone numbers.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *verificationMap;

@end

#pragma mark -

@implementation OWSVerificationManager

+ (instancetype)sharedManager
{
    static OWSVerificationManager *sharedMyManager = nil;
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

    return [self initWithStorageManager:storageManager messageSender:messageSender];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(storageManager);
    OWSAssert(messageSender);

    _storageManager = storageManager;
    _messageSender = messageSender;

    OWSSingletonAssert();

//    // Register this manager with the message sender.
//    // This is a circular dependency.
//    [messageSender setBlockingManager:self];

    return self;
}

- (void)setVerificationState:(OWSVerificationState)verificationState
              forPhoneNumber:(NSString *)phoneNumber
       isUserInitiatedChange:(BOOL)isUserInitiatedChange
{
    OWSAssert(phoneNumber.length > 0);
    
    DDLogInfo(@"%@ setVerificationState: %@ forPhoneNumber: %@", self.tag, OWSVerificationStateToString(verificationState), phoneNumber);
    
    NSDictionary<NSString *, NSNumber *> *verificationMapCopy = nil;
    
    @synchronized(self)
    {
        [self lazyLoadStateIfNecessary];
        OWSAssert(self.verificationMap);
        
        NSNumber * _Nullable existingValue = self.verificationMap[phoneNumber];
        if (existingValue && existingValue.intValue == (int) verificationState) {
            // Ignore redundant changes.
            return;
        }
        
        self.verificationMap[phoneNumber] = @(verificationState);
        
        verificationMapCopy = [self.verificationMap copy];
    }
    
    [self handleUpdate:verificationMapCopy
       sendSyncMessage:isUserInitiatedChange];
}

- (OWSVerificationState)verificationStateForPhoneNumber:(NSString *)phoneNumber
{
    OWSAssert(phoneNumber.length > 0);
    
    @synchronized(self)
    {
        [self lazyLoadStateIfNecessary];
        OWSAssert(self.verificationMap);

        NSNumber * _Nullable existingValue = self.verificationMap[phoneNumber];
        
        return (existingValue
                ? (OWSVerificationState) existingValue.intValue
                : OWSVerificationStateDefault);
    }
}

//- (void)removeBlockedPhoneNumber:(NSString *)phoneNumber
//{
//    OWSAssert(phoneNumber.length > 0);
//
//    DDLogInfo(@"%@ removeBlockedPhoneNumber: %@", self.tag, phoneNumber);
//
//    @synchronized(self)
//    {
//        [self lazyLoadStateIfNecessary];
//
//        if (![_blockedPhoneNumberSet containsObject:phoneNumber]) {
//            // Ignore redundant changes.
//            return;
//        }
//
//        [_blockedPhoneNumberSet removeObject:phoneNumber];
//    }
//
//    [self handleUpdate];
//}
//
//- (void)setBlockedPhoneNumbers:(NSArray<NSString *> *)blockedPhoneNumbers sendSyncMessage:(BOOL)sendSyncMessage
//{
//    OWSAssert(blockedPhoneNumbers != nil);
//
//    DDLogInfo(@"%@ setBlockedPhoneNumbers: %d", self.tag, (int)blockedPhoneNumbers.count);
//
//    @synchronized(self)
//    {
//        [self lazyLoadStateIfNecessary];
//
//        NSSet *newSet = [NSSet setWithArray:blockedPhoneNumbers];
//        if ([_blockedPhoneNumberSet isEqualToSet:newSet]) {
//            return;
//        }
//
//        _blockedPhoneNumberSet = [newSet mutableCopy];
//    }
//
//    [self handleUpdate:sendSyncMessage];
//}
//
//- (NSArray<NSString *> *)blockedPhoneNumbers
//{
//    @synchronized(self)
//    {
//        [self lazyLoadStateIfNecessary];
//
//        return [_blockedPhoneNumberSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
//    }
//}

//// This should be called every time the block list changes.
//
//- (void)handleUpdate
//{
//    // By default, always send a sync message when the block list changes.
//    [self handleUpdate:YES];
//}

- (void)handleUpdate:(NSDictionary<NSString *, NSNumber *> *)verificationMap
            sendSyncMessage:(BOOL)sendSyncMessage
{
    OWSAssert(verificationMap);
    
//    NSArray<NSString *> *blockedPhoneNumbers = [self blockedPhoneNumbers];

    [_storageManager setObject:verificationMap
                        forKey:kOWSVerificationManager_VerificationMapKey
                  inCollection:kOWSVerificationManager_Collection];

    dispatch_async(dispatch_get_main_queue(), ^{
//        if (sendSyncMessage) {
//            [self sendBlockedPhoneNumbersMessage:blockedPhoneNumbers];
//        } else {
//            // If this update came from an incoming block list sync message,
//            // update the "synced blocked phone numbers" state immediately,
//            // since we're now in sync.
//            //
//            // There could be data loss if both clients modify the block list
//            // at the same time, but:
//            //
//            // a) Block list changes will be rare.
//            // b) Conflicting block list changes will be even rarer.
//            // c) It's unlikely a user will make conflicting changes on two
//            //    devices around the same time.
//            // d) There isn't a good way to avoid this.
//            [self saveVerificationMap:blockedPhoneNumbers];
//        }

        [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationName_VerificationStateDidChange
                                                            object:nil
                                                          userInfo:nil];
    });
}

// This method should only be called from within a synchronized block.
- (void)lazyLoadStateIfNecessary
{
    if (self.verificationMap) {
        // verificationMap has already been loaded, abort.
        return;
    }

    NSDictionary<NSString *, NSNumber *> *verificationMap =
        [_storageManager objectForKey:kOWSVerificationManager_VerificationMapKey
                         inCollection:kOWSVerificationManager_Collection];
    _verificationMap = (verificationMap ? [verificationMap mutableCopy] : [NSMutableDictionary new]);

//    // If we haven't yet successfully synced the current "blocked phone numbers" changes,
//    // try again to sync now.
//    NSArray<NSString *> *syncedBlockedPhoneNumbers =
//        [_storageManager objectForKey:kOWSVerificationManager_SyncedBlockedPhoneNumbersKey
//                         inCollection:kOWSVerificationManager_BlockedPhoneNumbersCollection];
//    NSSet *syncedBlockedPhoneNumberSet = [[NSSet alloc] initWithArray:(syncedBlockedPhoneNumbers ?: [NSArray new])];
//    if (![_blockedPhoneNumberSet isEqualToSet:syncedBlockedPhoneNumberSet]) {
//        DDLogInfo(@"%@ retrying sync of blocked phone numbers", self.tag);
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [self sendBlockedPhoneNumbersMessage:blockedPhoneNumbers];
//        });
//    }
}

//- (void)sendBlockedPhoneNumbersMessage:(NSArray<NSString *> *)blockedPhoneNumbers
//{
//    OWSAssert(blockedPhoneNumbers);
//
//    OWSBlockedPhoneNumbersMessage *message =
//        [[OWSBlockedPhoneNumbersMessage alloc] initWithPhoneNumbers:blockedPhoneNumbers];
//
//    [self.messageSender sendMessage:message
//        success:^{
//            DDLogInfo(@"%@ Successfully sent blocked phone numbers sync message", self.tag);
//
//            // Record the last set of "blocked phone numbers" which we successfully synced.
//            [self saveVerificationMap:blockedPhoneNumbers];
//        }
//        failure:^(NSError *error) {
//            DDLogError(@"%@ Failed to send blocked phone numbers sync message with error: %@", self.tag, error);
//
//            // TODO: We might want to retry more often than just app launch.
//        }];
//}

//- (void)saveSyncedVerificationMap:(NSArray<NSString *> *)verificationMap
//{
//    OWSAssert(blockedPhoneNumbers);
//
//    // Record the last set of "blocked phone numbers" which we successfully synced.
//    [_storageManager setObject:verificationMap
//                        forKey:kOWSVerificationManager_VerificationMapKey
//                  inCollection:kOWSVerificationManager_Collection];
//}

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
