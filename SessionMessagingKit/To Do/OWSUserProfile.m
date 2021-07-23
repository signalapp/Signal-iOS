//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUserProfile.h"
#import <PromiseKit/AnyPromise.h>
#import <SessionMessagingKit/OWSPrimaryStorage.h>
#import <SessionMessagingKit/SSKEnvironment.h>
#import <SessionMessagingKit/TSAccountManager.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSObject+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <Curve25519Kit/Curve25519.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_LocalProfileDidChange = @"kNSNotificationName_LocalProfileDidChange";
NSString *const kNSNotificationName_OtherUsersProfileDidChange = @"kNSNotificationName_OtherUsersProfileDidChange";
NSString *const kNSNotificationKey_ProfileRecipientId = @"kNSNotificationKey_ProfileRecipientId";

@interface OWSUserProfile ()

@end

@implementation OWSUserProfile

+ (NSString *)profileAvatarFilepathWithFilename:(NSString *)filename
{
    if (filename.length <= 0) { return @""; };

    return [self.profileAvatarsDirPath stringByAppendingPathComponent:filename];
}

+ (NSString *)legacyProfileAvatarsDirPath
{
    return [[OWSFileSystem appDocumentDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (NSString *)sharedDataProfileAvatarsDirPath
{
    return [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (nullable NSError *)migrateToSharedData
{
    return [OWSFileSystem moveAppFilePath:self.legacyProfileAvatarsDirPath
                       sharedDataFilePath:self.sharedDataProfileAvatarsDirPath];
}

+ (NSString *)profileAvatarsDirPath
{
    static NSString *profileAvatarsDirPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileAvatarsDirPath = self.sharedDataProfileAvatarsDirPath;

        [OWSFileSystem ensureDirectoryExists:profileAvatarsDirPath];
    });
    return profileAvatarsDirPath;
}

+ (void)resetProfileStorage
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self profileAvatarsDirPath] error:&error];
}

+ (NSSet<NSString *> *)allProfileAvatarFilePaths
{
    NSString *profileAvatarsDirPath = self.profileAvatarsDirPath;
    NSMutableSet<NSString *> *profileAvatarFilePaths = [NSMutableSet new];

    NSSet<SNContact *> *allContacts = [LKStorage.shared getAllContacts];
    
    for (SNContact *contact in allContacts) {
        if (contact.profilePictureFileName == nil) { continue; }
        NSString *filePath = [profileAvatarsDirPath stringByAppendingPathComponent:contact.profilePictureFileName];
        [profileAvatarFilePaths addObject:filePath];
    }
    
    return [profileAvatarFilePaths copy];
}

@end

NS_ASSUME_NONNULL_END
