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

- (void)handleUpdate:(NSDictionary<NSString *, NSNumber *> *)verificationMap
            sendSyncMessage:(BOOL)sendSyncMessage
{
    OWSAssert(verificationMap);

    [_storageManager setObject:verificationMap
                        forKey:kOWSVerificationManager_VerificationMapKey
                  inCollection:kOWSVerificationManager_Collection];

    dispatch_async(dispatch_get_main_queue(), ^{
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
