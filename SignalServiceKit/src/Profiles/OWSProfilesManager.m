//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSProfilesManager.h"
#import "OWSMessageSender.h"
#import "SecurityUtils.h"
#import "TSStorageManager.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_LocalProfileDidChange = @"kNSNotificationName_LocalProfileDidChange";

NSString *const kOWSProfilesManager_Collection = @"kOWSProfilesManager_Collection";
// This key is used to persist the local user's profile key.
NSString *const kOWSProfilesManager_LocalProfileKey = @"kOWSProfilesManager_LocalProfileKey";
NSString *const kOWSProfilesManager_LocalProfileNameKey = @"kOWSProfilesManager_LocalProfileNameKey";
NSString *const kOWSProfilesManager_LocalProfileAvatarFilenameKey
    = @"kOWSProfilesManager_LocalProfileAvatarFilenameKey";

// TODO:
static const NSInteger kProfileKeyLength = 16;

@interface OWSProfilesManager ()

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

@property (atomic, readonly, nullable) NSData *localProfileKey;

@property (atomic, nullable) NSString *localProfileName;
@property (atomic, nullable) UIImage *localProfileAvatarImage;
@property (atomic) BOOL hasLoadedLocalProfile;

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

    [self loadLocalProfileAsync];

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

#pragma mark - Local Profile

- (void)loadLocalProfileAsync
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *_Nullable localProfileName = [self.storageManager objectForKey:kOWSProfilesManager_LocalProfileNameKey
                                                                    inCollection:kOWSProfilesManager_Collection];
        NSString *_Nullable localProfileAvatarFilename =
            [self.storageManager objectForKey:kOWSProfilesManager_LocalProfileAvatarFilenameKey
                                 inCollection:kOWSProfilesManager_Collection];
        UIImage *_Nullable localProfileAvatar = nil;
        if (localProfileAvatarFilename) {
            localProfileAvatar = [self loadProfileAvatarsWithFilename:localProfileAvatarFilename];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.localProfileName = localProfileName;
            self.localProfileAvatarImage = localProfileAvatar;
            self.hasLoadedLocalProfile = YES;

            if (localProfileAvatar || localProfileName) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationName_LocalProfileDidChange
                                                                    object:nil
                                                                  userInfo:nil];
            }
        });
    });
}

#pragma mark - Avatar Disk Cache

- (nullable UIImage *)loadProfileAvatarsWithFilename:(NSString *)filename
{
    NSString *filePath = [self.profileAvatarsDirPath stringByAppendingPathComponent:filename];
    UIImage *_Nullable image = [UIImage imageWithContentsOfFile:filePath];
    return image;
}

- (NSString *)profileAvatarsDirPath
{
    static NSString *profileAvatarsDirPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *documentsPath =
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        profileAvatarsDirPath = [documentsPath stringByAppendingPathComponent:@"ProfileAvatars"];

        BOOL isDirectory;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:profileAvatarsDirPath isDirectory:&isDirectory];
        if (exists) {
            OWSAssert(isDirectory);

            DDLogInfo(@"Profile avatars directory already exists");
        } else {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:profileAvatarsDirPath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
            if (error) {
                DDLogError(@"Failed to create profile avatars directory: %@", error);
            }
        }
    });
    return profileAvatarsDirPath;
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
