//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileManager.h"
#import "Environment.h"
#import "OWSUserProfile.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import "UIUtil.h"
#import <SessionUtilitiesKit/AppContext.h>
#import <SessionMessagingKit/AppReadiness.h>
#import <SessionUtilitiesKit/MIMETypeUtil.h>
#import <SessionUtilitiesKit/NSData+Image.h>
#import <SessionUtilitiesKit/NSNotificationCenter+OWS.h>
#import <SessionUtilitiesKit/NSString+SSK.h>
#import <SessionMessagingKit/OWSBlockingManager.h>
#import <SessionUtilitiesKit/OWSFileSystem.h>
#import <SignalUtilitiesKit/OWSPrimaryStorage+Loki.h>
#import <SessionMessagingKit/SSKEnvironment.h>
#import <SessionMessagingKit/TSAccountManager.h>
#import <SessionMessagingKit/TSGroupThread.h>
#import <SessionMessagingKit/TSThread.h>
#import <SessionUtilitiesKit/TSYapDatabaseObject.h>
#import <SessionUtilitiesKit/UIImage+OWS.h>
#import <SessionMessagingKit/YapDatabaseConnection+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_ProfileWhitelistDidChange = @"kNSNotificationName_ProfileWhitelistDidChange";

NSString *const kOWSProfileManager_UserWhitelistCollection = @"kOWSProfileManager_UserWhitelistCollection";
NSString *const kOWSProfileManager_GroupWhitelistCollection = @"kOWSProfileManager_GroupWhitelistCollection";

NSString *const kNSNotificationName_ProfileKeyDidChange = @"kNSNotificationName_ProfileKeyDidChange";

// The max bytes for a user's profile name, encoded in UTF8.
// Before encrypting and submitting we NULL pad the name data to this length.
const NSUInteger kOWSProfileManager_NameDataLength = 26;
const NSUInteger kOWSProfileManager_MaxAvatarDiameter = 640;

typedef void (^ProfileManagerFailureBlock)(NSError *error);

@interface OWSProfileManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSCache<NSString *, UIImage *> *profileAvatarImageCache;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSMutableSet<NSString *> *currentAvatarDownloads;

@end

#pragma mark -

// Access to most state should happen while synchronized on the profile manager.
// Writes should happen off the main thread, wherever possible.
@implementation OWSProfileManager

+ (instancetype)sharedManager
{
    return SSKEnvironment.shared.profileManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSAssertDebug(primaryStorage);

    _dbConnection = primaryStorage.newDatabaseConnection;

    _profileAvatarImageCache = [NSCache new];
    _currentAvatarDownloads = [NSMutableSet new];

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

- (OWSIdentityManager *)identityManager
{
    return SSKEnvironment.shared.identityManager;
}

- (OWSBlockingManager *)blockingManager
{
    return SSKEnvironment.shared.blockingManager;
}

- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)(void))successBlockParameter
                       failure:(void (^)(NSError *))failureBlockParameter
                  requiresSync:(BOOL)requiresSync
{
    OWSAssertDebug(successBlockParameter);
    OWSAssertDebug(failureBlockParameter);

    // Ensure that the success and failure blocks are called on the main thread.
    void (^failureBlock)(NSError *) = ^(NSError *error) {
        OWSLogError(@"Updating service with profile failed.");

        dispatch_async(dispatch_get_main_queue(), ^{
            failureBlockParameter(error);
        });
    };
    void (^successBlock)(void) = ^{
        OWSLogInfo(@"Successfully updated service with profile.");

        dispatch_async(dispatch_get_main_queue(), ^{
            successBlockParameter();
        });
    };

    // The final steps are to:
    //
    // * Try to update the service.
    // * Update client state on success.
    void (^tryToUpdateService)(NSString *_Nullable, NSString *_Nullable) = ^(
        NSString *_Nullable avatarUrlPath, NSString *_Nullable avatarFileName) {
        [self updateServiceWithProfileName:profileName
                                 avatarUrl:avatarUrlPath
            success:^{
                SNContact *userProfile = [LKStorage.shared getUser];
                OWSAssertDebug(userProfile);

                userProfile.name = profileName;
                userProfile.profilePictureURL = avatarUrlPath;
                userProfile.profilePictureFileName = avatarFileName;
                
                [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [LKStorage.shared setContact:userProfile usingTransaction:transaction];
                } completion:^{
                    if (avatarFileName != nil) {
                        [self updateProfileAvatarCache:avatarImage filename:avatarFileName];
                    }
                    
                    successBlock();
                }];
            }
            failure:^(NSError *error) {
                failureBlock(error);
            }];
    };

    SNContact *userProfile = [LKStorage.shared getUser];
    OWSAssertDebug(userProfile);
    
    if (avatarImage) {
        // If we have a new avatar image, we must first:
        //
        // * Encode it to JPEG.
        // * Write it to disk.
        // * Encrypt it
        // * Upload it to asset service
        // * Send asset service info to Signal Service
        OWSLogVerbose(@"Updating local profile on service with new avatar.");
        [self writeAvatarToDisk:avatarImage
            success:^(NSData *data, NSString *fileName) {
                [self uploadAvatarToService:data
                    success:^(NSString *_Nullable avatarUrlPath) {
                        tryToUpdateService(avatarUrlPath, fileName);
                    }
                    failure:^(NSError *error) {
                        failureBlock(error);
                    }];
            }
            failure:^(NSError *error) {
                failureBlock(error);
            }];
    } else if (userProfile.profilePictureURL) {
        OWSLogVerbose(@"Updating local profile on service with cleared avatar.");
        [self uploadAvatarToService:nil
            success:^(NSString *_Nullable avatarUrlPath) {
                tryToUpdateService(nil, nil);
            }
            failure:^(NSError *error) {
                failureBlock(error);
            }];
    } else {
        OWSLogVerbose(@"Updating local profile on service with no avatar.");
        tryToUpdateService(nil, nil);
    }
}

- (void)writeAvatarToDisk:(UIImage *)avatar
                  success:(void (^)(NSData *data, NSString *fileName))successBlock
                  failure:(ProfileManagerFailureBlock)failureBlock {
    OWSAssertDebug(avatar);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (avatar) {
            NSData *data = [self processedImageDataForRawAvatar:avatar];
            OWSAssertDebug(data);
            if (data) {
                NSString *fileName = [self generateAvatarFilename];
                NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];
                BOOL success = [data writeToFile:filePath atomically:YES];
                OWSAssertDebug(success);
                if (success) {
                    return successBlock(data, fileName);
                }
            }
        }
        failureBlock(OWSErrorWithCodeDescription(OWSErrorCodeAvatarWriteFailed, @"Avatar write failed."));
    });
}

- (NSData *)processedImageDataForRawAvatar:(UIImage *)image
{
    NSUInteger kMaxAvatarBytes = 5 * 1000 * 1000;

    if (image.size.width != kOWSProfileManager_MaxAvatarDiameter
        || image.size.height != kOWSProfileManager_MaxAvatarDiameter) {
        // To help ensure the user is being shown the same cropping of their avatar as
        // everyone else will see, we want to be sure that the image was resized before this point.
        OWSFailDebug(@"Avatar image should have been resized before trying to upload");
        image = [image resizedImageToFillPixelSize:CGSizeMake(kOWSProfileManager_MaxAvatarDiameter,
                                                       kOWSProfileManager_MaxAvatarDiameter)];
    }

    NSData *_Nullable data = UIImageJPEGRepresentation(image, 0.95f);
    if (data.length > kMaxAvatarBytes) {
        // Our avatar dimensions are so small that it's incredibly unlikely we wouldn't be able to fit our profile
        // photo. e.g. generating pure noise at our resolution compresses to ~200k.
        OWSFailDebug(@"Suprised to find profile avatar was too large. Was it scaled properly? image: %@", image);
    }

    return data;
}

// If avatarData is nil, we are clearing the avatar.
- (void)uploadAvatarToService:(NSData *_Nullable)avatarData
                      success:(void (^)(NSString *_Nullable avatarUrlPath))successBlock
                      failure:(ProfileManagerFailureBlock)failureBlock {
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);
    OWSAssertDebug(avatarData == nil || avatarData.length > 0);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // We always want to encrypt a profile with a new profile key
        // This ensures that other users know that our profile picture was updated
        OWSAES256Key *newProfileKey = [OWSAES256Key generateRandomKey];
        
        if (avatarData) {
            NSData *encryptedAvatarData = [self encryptProfileData:avatarData profileKey:newProfileKey];
            OWSAssertDebug(encryptedAvatarData.length > 0);
            
            AnyPromise *promise = [SNFileServerAPIV2 upload:encryptedAvatarData];
            
            [promise.thenOn(dispatch_get_main_queue(), ^(NSString *fileID) {
                NSString *downloadURL = [NSString stringWithFormat:@"%@/files/%@", SNFileServerAPIV2.server, fileID];
                [NSUserDefaults.standardUserDefaults setObject:[NSDate new] forKey:@"lastProfilePictureUpload"];
                
                SNContact *user = [LKStorage.shared getUser];
                user.profileEncryptionKey = newProfileKey;
                [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [LKStorage.shared setContact:user usingTransaction:transaction];
                } completion:^{
                    successBlock(downloadURL);
                }];
            })
            .catchOn(dispatch_get_main_queue(), ^(id result) {
                // There appears to be a bug in PromiseKit that sometimes causes catchOn
                // to be invoked with the fulfilled promise's value as the error. The below
                // is a quick and dirty workaround.
                if ([result isKindOfClass:NSString.class]) {
                    SNContact *user = [LKStorage.shared getUser];
                    user.profileEncryptionKey = newProfileKey;
                    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        [LKStorage.shared setContact:user usingTransaction:transaction];
                    } completion:^{
                        successBlock(result);
                    }];
                } else {
                    failureBlock(result);
                }
            }) retainUntilComplete];
        } else {
            // Update our profile key and set the url to nil if avatar data is nil
            SNContact *user = [LKStorage.shared getUser];
            user.profileEncryptionKey = newProfileKey;
            user.profilePictureURL = nil;
            user.profilePictureFileName = nil;
            [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [LKStorage.shared setContact:user usingTransaction:transaction];
            } completion:^{
                successBlock(nil);
            }];
        }
    });
}

- (void)updateServiceWithProfileName:(nullable NSString *)localProfileName
                           avatarUrl:(nullable NSString *)avatarURL
                             success:(void (^)(void))successBlock
                             failure:(ProfileManagerFailureBlock)failureBlock {
    successBlock();
}

- (void)updateServiceWithProfileName:(nullable NSString *)localProfileName avatarURL:(nullable NSString *)avatarURL {
    [self updateServiceWithProfileName:localProfileName avatarUrl:avatarURL success:^{} failure:^(NSError * _Nonnull error) {}];
}

#pragma mark - Profile Key Rotation

- (nullable NSString *)groupKeyForGroupId:(NSData *)groupId {
    NSString *groupIdKey = [groupId hexadecimalString];
    return groupIdKey;
}

- (nullable NSData *)groupIdForGroupKey:(NSString *)groupKey {
    NSMutableData *groupId = [NSMutableData new];

    if (groupKey.length % 2 != 0) {
        OWSFailDebug(@"Group key has unexpected length: %@ (%lu)", groupKey, (unsigned long)groupKey.length);
        return nil;
    }
    for (NSUInteger i = 0; i + 2 <= groupKey.length; i += 2) {
        NSString *_Nullable byteString = [groupKey substringWithRange:NSMakeRange(i, 2)];
        if (!byteString) {
            OWSFailDebug(@"Couldn't slice group key.");
            return nil;
        }
        unsigned byteValue;
        if (![[NSScanner scannerWithString:byteString] scanHexInt:&byteValue]) {
            OWSFailDebug(@"Couldn't parse hex byte: %@.", byteString);
            return nil;
        }
        if (byteValue > 0xff) {
            OWSFailDebug(@"Invalid hex byte: %@ (%d).", byteString, byteValue);
            return nil;
        }
        uint8_t byte = (uint8_t)(0xff & byteValue);
        [groupId appendBytes:&byte length:1];
    }
    return [groupId copy];
}

- (void)regenerateLocalProfile
{
    NSString *userPublicKey = [SNGeneralUtilities getUserPublicKey];
    SNContact *contact = [LKStorage.shared getContactWithSessionID:userPublicKey];
    contact.profileEncryptionKey = [OWSAES256Key generateRandomKey];
    contact.profilePictureURL = nil;
    contact.profilePictureFileName = nil;
    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [LKStorage.shared setContact:contact usingTransaction:transaction];
    } completion:^{
        [[self.tsAccountManager updateAccountAttributes] retainUntilComplete];
    }];
}

#pragma mark - Other Users' Profiles

- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId avatarURL:(nullable NSString *)avatarURL
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSAES256Key *_Nullable profileKey = [OWSAES256Key keyWithData:profileKeyData];
        if (profileKey == nil) {
            OWSFailDebug(@"Failed to make profile key for key data");
            return;
        }
        
        SNContact *contact = [LKStorage.shared getContactWithSessionID:recipientId];
        
        OWSAssertDebug(contact);
        if (contact.profileEncryptionKey != nil && [contact.profileEncryptionKey.keyData isEqual:profileKey.keyData]) {
            // Ignore redundant update.
            return;
        }
        
        contact.profileEncryptionKey = profileKey;
        contact.profilePictureURL = nil;
        contact.profilePictureFileName = nil;
        
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [LKStorage.shared setContact:contact usingTransaction:transaction];
        } completion:^{
            contact.profilePictureURL = avatarURL;
            [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                [LKStorage.shared setContact:contact usingTransaction:transaction];
            } completion:^{
                [self downloadAvatarForUserProfile:contact];
            }];
        }];
    });
}

- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId
{
    [self setProfileKeyData:profileKeyData forRecipientId:recipientId avatarURL:nil];
}

- (nullable NSData *)profileKeyDataForRecipientId:(NSString *)recipientId
{
    return [self profileKeyForRecipientId:recipientId].keyData;
}

- (nullable OWSAES256Key *)profileKeyForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);
    
    SNContact *contact = [LKStorage.shared getContactWithSessionID:recipientId];
    OWSAssertDebug(contact);

    return contact.profileEncryptionKey;
}

- (nullable UIImage *)profileAvatarForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    SNContact *contact = [LKStorage.shared getContactWithSessionID:recipientId];
    
    if (contact.profilePictureFileName != nil && contact.profilePictureFileName.length > 0) {
        return [self loadProfileAvatarWithFilename:contact.profilePictureFileName];
    }

    if (contact.profilePictureURL != nil && contact.profilePictureURL.length > 0) {
        [self downloadAvatarForUserProfile:contact];
    }

    return nil;
}

- (nullable NSData *)profileAvatarDataForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    SNContact *contact = [LKStorage.shared getContactWithSessionID:recipientId];

    if (contact.profilePictureFileName != nil && contact.profilePictureFileName.length > 0) {
        return [self loadProfileDataWithFilename:contact.profilePictureFileName];
    }

    return nil;
}

- (NSString *)generateAvatarFilename
{
    return [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
}

- (void)downloadAvatarForUserProfile:(SNContact *)contact
{
    OWSAssertDebug(contact);

    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL hasProfilePictureURL = (contact.profilePictureURL != nil && contact.profilePictureURL.length > 0);
        if (!hasProfilePictureURL) {
            OWSLogDebug(@"Skipping downloading avatar for %@ because url is not set", contact.sessionID);
            return;
        }
        NSString *_Nullable avatarUrlPathAtStart = contact.profilePictureURL;

        BOOL hasProfileEncryptionKey = (contact.profileEncryptionKey != nil && contact.profileEncryptionKey.keyData.length > 0);
        if (!hasProfileEncryptionKey || !hasProfilePictureURL) {
            return;
        }
        
        OWSAES256Key *profileKeyAtStart = contact.profileEncryptionKey;

        NSString *fileName = [self generateAvatarFilename];
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];

        @synchronized(self.currentAvatarDownloads)
        {
            if ([self.currentAvatarDownloads containsObject:contact.sessionID]) {
                // Download already in flight; ignore.
                return;
            }
            [self.currentAvatarDownloads addObject:contact.sessionID];
        }

        OWSLogVerbose(@"downloading profile avatar: %@", contact.sessionID);

        NSString *profilePictureURL = contact.profilePictureURL;
        
        NSString *file = [profilePictureURL lastPathComponent];
        BOOL useOldServer = [profilePictureURL containsString:SNFileServerAPIV2.oldServer];
        AnyPromise *promise = [SNFileServerAPIV2 download:file useOldServer:useOldServer];
        
        [promise.then(^(NSData *data) {
            @synchronized(self.currentAvatarDownloads)
            {
                [self.currentAvatarDownloads removeObject:contact.sessionID];
            }
            NSData *_Nullable encryptedData = data;
            NSData *_Nullable decryptedData = [self decryptProfileData:encryptedData profileKey:profileKeyAtStart];
            UIImage *_Nullable image = nil;
            if (decryptedData) {
                BOOL success = [decryptedData writeToFile:filePath atomically:YES];
                if (success) {
                    image = [UIImage imageWithContentsOfFile:filePath];
                }
            }
            
            SNContact *latestContact = [LKStorage.shared getContactWithSessionID:contact.sessionID];

            BOOL hasProfileEncryptionKey = (latestContact.profileEncryptionKey != nil
                && latestContact.profileEncryptionKey.keyData.length > 0);
            if (!hasProfileEncryptionKey || ![latestContact.profileEncryptionKey isEqual:contact.profileEncryptionKey]) {
                OWSLogWarn(@"Ignoring avatar download for obsolete user profile.");
            } else if (![avatarUrlPathAtStart isEqualToString:latestContact.profilePictureURL]) {
                OWSLogInfo(@"avatar url has changed during download");
                if (latestContact.profilePictureURL != nil && latestContact.profilePictureURL.length > 0) {
                    [self downloadAvatarForUserProfile:latestContact];
                }
            } else if (!encryptedData) {
                OWSLogError(@"avatar encrypted data for %@ could not be read.", contact.sessionID);
            } else if (!decryptedData) {
                OWSLogError(@"avatar data for %@ could not be decrypted.", contact.sessionID);
            } else if (!image) {
                OWSLogError(@"avatar image for %@ could not be loaded.", contact.sessionID);
            } else {
                latestContact.profilePictureFileName = fileName;
                [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    [LKStorage.shared setContact:latestContact usingTransaction:transaction];
                }];
                [self updateProfileAvatarCache:image filename:fileName];
            }

            OWSAssertDebug(backgroundTask);
            backgroundTask = nil;
        }) retainUntilComplete];
    });
}

- (void)updateProfileForRecipientId:(NSString *)recipientId
               profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                      avatarUrlPath:(nullable NSString *)avatarUrlPath
{
    OWSAssertDebug(recipientId.length > 0);

    OWSLogDebug(@"update profile for: %@ name: %@ avatar: %@", recipientId, profileNameEncrypted, avatarUrlPath);

    // Ensure decryption, etc. off main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SNContact *contact = [LKStorage.shared getContactWithSessionID:recipientId];

        if (!contact.profileEncryptionKey) { return; }

        NSString *_Nullable profileName =
            [self decryptProfileNameData:profileNameEncrypted profileKey:contact.profileEncryptionKey];
        
        contact.name = profileName;
        contact.profilePictureURL = avatarUrlPath;
        
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [LKStorage.shared setContact:contact usingTransaction:transaction];
        }];

        // Whenever we change avatarUrlPath, OWSUserProfile clears avatarFileName.
        // So if avatarUrlPath is set and avatarFileName is not set, we should to
        // download this avatar. downloadAvatarForUserProfile will de-bounce
        // downloads.
        BOOL hasProfilePictureURL = (contact.profilePictureURL != nil && contact.profilePictureURL.length > 0);
        BOOL hasProfilePictureFileName = (contact.profilePictureFileName != nil && contact.profilePictureFileName.length > 0);
        if (hasProfilePictureURL && !hasProfilePictureFileName) {
            [self downloadAvatarForUserProfile:contact];
        }
    });
}

- (BOOL)isNullableDataEqual:(NSData *_Nullable)left toData:(NSData *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqual:right];
    }
}

- (BOOL)isNullableStringEqual:(NSString *_Nullable)left toString:(NSString *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqualToString:right];
    }
}

#pragma mark - Profile Encryption

- (nullable NSData *)encryptProfileData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssertDebug(profileKey.keyData.length == kAES256_KeyByteLength);

    if (!encryptedData) {
        return nil;
    }

    return [Cryptography encryptAESGCMWithProfileData:encryptedData key:profileKey];
}

- (nullable NSData *)decryptProfileData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssertDebug(profileKey.keyData.length == kAES256_KeyByteLength);

    if (!encryptedData) {
        return nil;
    }

    return [Cryptography decryptAESGCMWithProfileData:encryptedData key:profileKey];
}

- (nullable NSString *)decryptProfileNameData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssertDebug(profileKey.keyData.length == kAES256_KeyByteLength);

    NSData *_Nullable decryptedData = [self decryptProfileData:encryptedData profileKey:profileKey];
    if (decryptedData.length < 1) {
        return nil;
    }


    // Unpad profile name.
    NSUInteger unpaddedLength = 0;
    const char *bytes = decryptedData.bytes;

    // Work through the bytes until we encounter our first
    // padding byte (our padding scheme is NULL bytes)
    for (NSUInteger i = 0; i < decryptedData.length; i++) {
        if (bytes[i] == 0x00) {
            break;
        }
        unpaddedLength = i + 1;
    }

    NSData *unpaddedData = [decryptedData subdataWithRange:NSMakeRange(0, unpaddedLength)];

    return [[NSString alloc] initWithData:unpaddedData encoding:NSUTF8StringEncoding];
}

- (nullable NSData *)encryptProfileData:(nullable NSData *)data
{
    OWSAES256Key *localProfileKey = [LKStorage.shared getUser].profileEncryptionKey;
    
    return [self encryptProfileData:data profileKey:localProfileKey];
}

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName
{
    OWSAssertIsOnMainThread();

    NSData *nameData = [profileName dataUsingEncoding:NSUTF8StringEncoding];
    return nameData.length > kOWSProfileManager_NameDataLength;
}

- (nullable NSData *)encryptProfileNameWithUnpaddedName:(NSString *)name
{
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (nameData.length > kOWSProfileManager_NameDataLength) {
        OWSFailDebug(@"name data is too long with length:%lu", (unsigned long)nameData.length);
        return nil;
    }

    NSUInteger paddingByteCount = kOWSProfileManager_NameDataLength - nameData.length;

    NSMutableData *paddedNameData = [nameData mutableCopy];
    // Since we want all encrypted profile names to be the same length on the server, we use `increaseLengthBy`
    // to pad out any remaining length with 0 bytes.
    [paddedNameData increaseLengthBy:paddingByteCount];
    OWSAssertDebug(paddedNameData.length == kOWSProfileManager_NameDataLength);

    OWSAES256Key *localProfileKey = [LKStorage.shared getUser].profileEncryptionKey;
    
    return [self encryptProfileData:[paddedNameData copy] profileKey:localProfileKey];
}

#pragma mark - Avatar Disk Cache

- (nullable NSData *)loadProfileDataWithFilename:(NSString *)filename
{
    if (filename.length <= 0) { return nil; };

    NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:filename];
    return [NSData dataWithContentsOfFile:filePath];
}

- (nullable UIImage *)loadProfileAvatarWithFilename:(NSString *)filename
{
    if (filename.length == 0) {
        return nil;
    }

    UIImage *_Nullable image = nil;
    @synchronized(self.profileAvatarImageCache)
    {
        image = [self.profileAvatarImageCache objectForKey:filename];
    }
    if (image) {
        return image;
    }

    NSData *data = [self loadProfileDataWithFilename:filename];
    if (![data ows_isValidImage]) {
        return nil;
    }
    image = [UIImage imageWithData:data];
    [self updateProfileAvatarCache:image filename:filename];
    return image;
}

- (void)updateProfileAvatarCache:(nullable UIImage *)image filename:(NSString *)filename
{
    if (filename.length <= 0) { return; };

    @synchronized(self.profileAvatarImageCache)
    {
        if (image) {
            [self.profileAvatarImageCache setObject:image forKey:filename];
        } else {
            [self.profileAvatarImageCache removeObjectForKey:filename];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
