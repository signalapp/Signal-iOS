//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSProfilesManager.h"
#import "OWSMessageSender.h"
#import "SecurityUtils.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSProfilesManager_Collection = @"kOWSProfilesManager_Collection";
// This key is used to persist the local user's profile key.
NSString *const kOWSProfilesManager_LocalProfileKey = @"kOWSProfilesManager_LocalProfileKey";

// TODO:
static const NSInteger kProfileKeyLength = 16;

@interface OWSProfilesManager ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

@property (nonatomic, readonly, nullable) NSData *localProfileKey;

@end

#pragma mark -

@implementation OWSProfilesManager

@synthesize localProfileKey = _localProfileKey;

+ (instancetype)sharedManager
{
    static OWSProfilesManager *sharedMyManager = nil;
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

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                         messageSender:(OWSMessageSender *)messageSender
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

    // Register this manager with the message sender.
    // This is a circular dependency.
    [messageSender setProfilesManager:self];

    // Try to load.
    _localProfileKey = [self.storageManager objectForKey:kOWSProfilesManager_LocalProfileKey
                                            inCollection:kOWSProfilesManager_Collection];
    if (!_localProfileKey) {
        // Generate
        _localProfileKey = [OWSProfilesManager generateLocalProfileKey];
        // Persist
        [self.storageManager setObject:_localProfileKey
                                forKey:kOWSProfilesManager_LocalProfileKey
                          inCollection:kOWSProfilesManager_Collection];
    }
    OWSAssert(_localProfileKey.length == kProfileKeyLength);

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
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

#pragma mark - Local Profile Key

+ (NSData *)generateLocalProfileKey
{
    // TODO:
    OWSFail(@"Profile key generation is not yet implemented.");
    return [SecurityUtils generateRandomBytes:kProfileKeyLength];
}

- (nullable NSData *)localProfileKey
{
    OWSAssert(_localProfileKey.length == kProfileKeyLength);
    return _localProfileKey;
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    @synchronized(self)
    {
        // TODO: Sync if necessary.
    }
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
