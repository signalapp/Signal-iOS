//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SessionUtilitiesKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kNSNotificationName_LocalProfileDidChange;
extern NSString *const kNSNotificationName_OtherUsersProfileDidChange;
extern NSString *const kNSNotificationKey_ProfileRecipientId;

@interface OWSUserProfile : TSYapDatabaseObject

+ (NSString *)profileAvatarFilepathWithFilename:(NSString *)filename;
+ (nullable NSError *)migrateToSharedData;
+ (NSString *)legacyProfileAvatarsDirPath;
+ (NSString *)sharedDataProfileAvatarsDirPath;
+ (NSString *)profileAvatarsDirPath;
+ (void)resetProfileStorage;
+ (NSSet<NSString *> *)allProfileAvatarFilePaths;

@end

NS_ASSUME_NONNULL_END
