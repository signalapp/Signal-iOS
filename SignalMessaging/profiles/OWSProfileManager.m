//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileManager.h"
#import "Environment.h"
#import "NSString+OWS.h"
#import "OWSUserProfile.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/Cryptography.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/NSData+OWS.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/OWSRequestBuilder.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/TSYapDatabaseObject.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_ProfileWhitelistDidChange = @"kNSNotificationName_ProfileWhitelistDidChange";

NSString *const kOWSProfileManager_UserWhitelistCollection = @"kOWSProfileManager_UserWhitelistCollection";
NSString *const kOWSProfileManager_GroupWhitelistCollection = @"kOWSProfileManager_GroupWhitelistCollection";

// The max bytes for a user's profile name, encoded in UTF8.
// Before encrypting and submitting we NULL pad the name data to this length.
const NSUInteger kOWSProfileManager_NameDataLength = 26;
const NSUInteger kOWSProfileManager_MaxAvatarDiameter = 640;

@interface OWSProfileManager ()

@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) OWSUserProfile *localUserProfile;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSCache<NSString *, UIImage *> *profileAvatarImageCache;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSMutableSet<NSString *> *currentAvatarDownloads;

@end

#pragma mark -

// Access to most state should happen while synchronized on the profile manager.
// Writes should happen off the main thread, wherever possible.
@implementation OWSProfileManager

@synthesize localUserProfile = _localUserProfile;

+ (instancetype)sharedManager
{
    return SSKEnvironment.shared.profileManager;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
                         messageSender:(OWSMessageSender *)messageSender
                        networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSAssertDebug(primaryStorage);
    OWSAssertDebug(messageSender);
    OWSAssertDebug(messageSender);

    _messageSender = messageSender;
    _dbConnection = primaryStorage.newDatabaseConnection;
    _networkManager = networkManager;

    _profileAvatarImageCache = [NSCache new];
    _currentAvatarDownloads = [NSMutableSet new];

    OWSSingletonAssert();

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

- (AFHTTPSessionManager *)avatarHTTPManager
{
    return [OWSSignalService sharedInstance].CDNSessionManager;
}

- (OWSIdentityManager *)identityManager
{
    return [OWSIdentityManager sharedManager];
}

#pragma mark - User Profile Accessor

- (void)ensureLocalProfileCached
{
    // Since localUserProfile can create a transaction, we want to make sure it's not called for the first
    // time unexpectedly (e.g. in a nested transaction.)
    __unused OWSUserProfile *profile = [self localUserProfile];
}

#pragma mark - Local Profile

- (OWSUserProfile *)localUserProfile
{
    @synchronized(self)
    {
        if (!_localUserProfile) {
            _localUserProfile = [OWSUserProfile getOrBuildUserProfileForRecipientId:kLocalProfileUniqueId
                                                                       dbConnection:self.dbConnection];
        }
    }

    OWSAssertDebug(_localUserProfile.profileKey);

    return _localUserProfile;
}

- (BOOL)localProfileExists
{
    return [OWSUserProfile localUserProfileExists:self.dbConnection];
}

- (OWSAES256Key *)localProfileKey
{
    OWSAssertDebug(self.localUserProfile.profileKey.keyData.length == kAES256_KeyByteLength);

    return self.localUserProfile.profileKey;
}

- (BOOL)hasLocalProfile
{
    return (self.localProfileName.length > 0 || self.localProfileAvatarImage != nil);
}

- (nullable NSString *)localProfileName
{
    return self.localUserProfile.profileName;
}

- (nullable UIImage *)localProfileAvatarImage
{
    return [self loadProfileAvatarWithFilename:self.localUserProfile.avatarFileName];
}

- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)(void))successBlockParameter
                       failure:(void (^)(void))failureBlockParameter
{
    OWSAssertDebug(successBlockParameter);
    OWSAssertDebug(failureBlockParameter);

    // Ensure that the success and failure blocks are called on the main thread.
    void (^failureBlock)(void) = ^{
        OWSLogError(@"Updating service with profile failed.");

        dispatch_async(dispatch_get_main_queue(), ^{
            failureBlockParameter();
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
            success:^{
                OWSUserProfile *userProfile = self.localUserProfile;
                OWSAssertDebug(userProfile);

                [userProfile updateWithProfileName:profileName
                                     avatarUrlPath:avatarUrlPath
                                    avatarFileName:avatarFileName
                                      dbConnection:self.dbConnection
                                        completion:^{
                                            if (avatarFileName) {
                                                [self updateProfileAvatarCache:avatarImage filename:avatarFileName];
                                            }

                                            successBlock();
                                        }];
            }
            failure:^{
                failureBlock();
            }];
    };

    OWSUserProfile *userProfile = self.localUserProfile;
    OWSAssertDebug(userProfile);

    if (avatarImage) {
        // If we have a new avatar image, we must first:
        //
        // * Encode it to JPEG.
        // * Write it to disk.
        // * Encrypt it
        // * Upload it to asset service
        // * Send asset service info to Signal Service
        if (self.localProfileAvatarImage == avatarImage) {
            OWSAssertDebug(userProfile.avatarUrlPath.length > 0);
            OWSAssertDebug(userProfile.avatarFileName.length > 0);

            OWSLogVerbose(@"Updating local profile on service with unchanged avatar.");
            // If the avatar hasn't changed, reuse the existing metadata.
            tryToUpdateService(userProfile.avatarUrlPath, userProfile.avatarFileName);
        } else {
            OWSLogVerbose(@"Updating local profile on service with new avatar.");
            [self writeAvatarToDisk:avatarImage
                success:^(NSData *data, NSString *fileName) {
                    [self uploadAvatarToService:data
                        success:^(NSString *_Nullable avatarUrlPath) {
                            tryToUpdateService(avatarUrlPath, fileName);
                        }
                        failure:^{
                            failureBlock();
                        }];
                }
                failure:^{
                    failureBlock();
                }];
        }
    } else if (userProfile.avatarUrlPath) {
        OWSLogVerbose(@"Updating local profile on service with cleared avatar.");
        [self uploadAvatarToService:nil
            success:^(NSString *_Nullable avatarUrlPath) {
                tryToUpdateService(nil, nil);
            }
            failure:^{
                failureBlock();
            }];
    } else {
        OWSLogVerbose(@"Updating local profile on service with no avatar.");
        tryToUpdateService(nil, nil);
    }
}

- (void)writeAvatarToDisk:(UIImage *)avatar
                  success:(void (^)(NSData *data, NSString *fileName))successBlock
                  failure:(void (^)(void))failureBlock
{
    OWSAssertDebug(avatar);
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (avatar) {
            NSData *data = [self processedImageDataForRawAvatar:avatar];
            OWSAssertDebug(data);
            if (data) {
                NSString *fileName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
                NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];
                BOOL success = [data writeToFile:filePath atomically:YES];
                OWSAssertDebug(success);
                if (success) {
                    successBlock(data, fileName);
                    return;
                }
            }
        }
        failureBlock();
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
                      failure:(void (^)(void))failureBlock
{
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);
    OWSAssertDebug(avatarData == nil || avatarData.length > 0);

    // We want to clear the local user's profile avatar as soon as
    // we request the upload form, since that request clears our
    // avatar on the service.
    //
    // TODO: Revisit this so that failed profile updates don't leave
    // the profile avatar blank, etc.
    void (^clearLocalAvatar)(void) = ^{
        OWSUserProfile *userProfile = self.localUserProfile;
        [userProfile updateWithAvatarUrlPath:nil avatarFileName:nil dbConnection:self.dbConnection completion:nil];
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // See: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-UsingHTTPPOST.html
        TSRequest *formRequest = [OWSRequestFactory profileAvatarUploadFormRequest];

        // TODO: Since this form request causes the server to reset my avatar URL, if the update fails
        // at some point from here on out, we want the user to understand they probably no longer have
        // a profile avatar on the server.

        [self.networkManager makeRequest:formRequest
            success:^(NSURLSessionDataTask *task, id formResponseObject) {
                clearLocalAvatar();

                if (avatarData == nil) {
                    OWSLogDebug(@"successfully cleared avatar");
                    successBlock(nil);
                    return;
                }

                if (![formResponseObject isKindOfClass:[NSDictionary class]]) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidResponse]);
                    failureBlock();
                    return;
                }
                NSDictionary *responseMap = formResponseObject;
                OWSLogError(@"responseObject: %@", formResponseObject);

                NSString *formAcl = responseMap[@"acl"];
                if (![formAcl isKindOfClass:[NSString class]] || formAcl.length < 1) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidAcl]);
                    failureBlock();
                    return;
                }
                NSString *formKey = responseMap[@"key"];
                if (![formKey isKindOfClass:[NSString class]] || formKey.length < 1) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidKey]);
                    failureBlock();
                    return;
                }
                NSString *formPolicy = responseMap[@"policy"];
                if (![formPolicy isKindOfClass:[NSString class]] || formPolicy.length < 1) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidPolicy]);
                    failureBlock();
                    return;
                }
                NSString *formAlgorithm = responseMap[@"algorithm"];
                if (![formAlgorithm isKindOfClass:[NSString class]] || formAlgorithm.length < 1) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidAlgorithm]);
                    failureBlock();
                    return;
                }
                NSString *formCredential = responseMap[@"credential"];
                if (![formCredential isKindOfClass:[NSString class]] || formCredential.length < 1) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidCredential]);
                    failureBlock();
                    return;
                }
                NSString *formDate = responseMap[@"date"];
                if (![formDate isKindOfClass:[NSString class]] || formDate.length < 1) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidDate]);
                    failureBlock();
                    return;
                }
                NSString *formSignature = responseMap[@"signature"];
                if (![formSignature isKindOfClass:[NSString class]] || formSignature.length < 1) {
                    OWSProdFail([OWSAnalyticsEvents profileManagerErrorAvatarUploadFormInvalidSignature]);
                    failureBlock();
                    return;
                }

                [self.avatarHTTPManager POST:@""
                    parameters:nil
                    constructingBodyWithBlock:^(id<AFMultipartFormData> _Nonnull formData) {
                        NSData * (^formDataForString)(NSString *formString) = ^(NSString *formString) {
                            return [formString dataUsingEncoding:NSUTF8StringEncoding];
                        };

                        // We have to build up the form manually vs. simply passing in a paramaters dict
                        // because AWS is sensitive to the order of the form params (at least the "key"
                        // field must occur early on).
                        // For consistency, all fields are ordered here in a known working order.
                        [formData appendPartWithFormData:formDataForString(formKey) name:@"key"];
                        [formData appendPartWithFormData:formDataForString(formAcl) name:@"acl"];
                        [formData appendPartWithFormData:formDataForString(formAlgorithm) name:@"x-amz-algorithm"];
                        [formData appendPartWithFormData:formDataForString(formCredential) name:@"x-amz-credential"];
                        [formData appendPartWithFormData:formDataForString(formDate) name:@"x-amz-date"];
                        [formData appendPartWithFormData:formDataForString(formPolicy) name:@"policy"];
                        [formData appendPartWithFormData:formDataForString(formSignature) name:@"x-amz-signature"];
                        [formData appendPartWithFormData:formDataForString(OWSMimeTypeApplicationOctetStream)
                                                    name:@"Content-Type"];
                        NSData *encryptedAvatarData = [self encryptProfileData:avatarData];
                        OWSAssertDebug(encryptedAvatarData.length > 0);
                        [formData appendPartWithFormData:encryptedAvatarData name:@"file"];

                        OWSLogVerbose(@"constructed body");
                    }
                    progress:^(NSProgress *_Nonnull uploadProgress) {
                        OWSLogVerbose(@"avatar upload progress: %.2f%%", uploadProgress.fractionCompleted * 100);
                    }
                    success:^(NSURLSessionDataTask *_Nonnull uploadTask, id _Nullable responseObject) {
                        OWSLogInfo(@"successfully uploaded avatar with key: %@", formKey);
                        successBlock(formKey);
                    }
                    failure:^(NSURLSessionDataTask *_Nullable uploadTask, NSError *_Nonnull error) {
                        OWSLogError(@"uploading avatar failed with error: %@", error);
                        failureBlock();
                    }];
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                // Only clear the local avatar if we have a response. Otherwise, we
                // had a network failure and probably didn't reach the service.
                if (task.response != nil) {
                    clearLocalAvatar();
                }

                OWSLogError(@"Failed to get profile avatar upload form: %@", error);
                failureBlock();
            }];
    });
}

- (void)updateServiceWithProfileName:(nullable NSString *)localProfileName
                             success:(void (^)(void))successBlock
                             failure:(void (^)(void))failureBlock
{
    OWSAssertDebug(successBlock);
    OWSAssertDebug(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *_Nullable encryptedPaddedName = [self encryptProfileNameWithUnpaddedName:localProfileName];

        TSRequest *request = [OWSRequestBuilder profileNameSetRequestWithEncryptedPaddedName:encryptedPaddedName];
        [self.networkManager makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                successBlock();
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                OWSLogError(@"Failed to update profile with error: %@", error);
                failureBlock();
            }];
    });
}

- (void)fetchLocalUsersProfile
{
    OWSAssertIsOnMainThread();

    NSString *_Nullable localNumber = [TSAccountManager sharedInstance].localNumber;
    if (!localNumber) {
        return;
    }
    [ProfileFetcherJob runWithRecipientId:localNumber networkManager:self.networkManager ignoreThrottling:YES];
}

#pragma mark - Profile Whitelist

- (void)clearProfileWhitelist
{
    OWSLogWarn(@"Clearing the profile whitelist.");

    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:kOWSProfileManager_UserWhitelistCollection];
        [transaction removeAllObjectsInCollection:kOWSProfileManager_GroupWhitelistCollection];
        OWSAssertDebug(0 == [transaction numberOfKeysInCollection:kOWSProfileManager_UserWhitelistCollection]);
        OWSAssertDebug(0 == [transaction numberOfKeysInCollection:kOWSProfileManager_GroupWhitelistCollection]);
    }];
}

- (void)logProfileWhitelist
{
    [self.dbConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        OWSLogError(@"kOWSProfileManager_UserWhitelistCollection: %lu",
            (unsigned long)[transaction numberOfKeysInCollection:kOWSProfileManager_UserWhitelistCollection]);
        [transaction enumerateKeysInCollection:kOWSProfileManager_UserWhitelistCollection
                                    usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                        OWSLogError(@"\t profile whitelist user: %@", key);
                                    }];
        OWSLogError(@"kOWSProfileManager_GroupWhitelistCollection: %lu",
            (unsigned long)[transaction numberOfKeysInCollection:kOWSProfileManager_GroupWhitelistCollection]);
        [transaction enumerateKeysInCollection:kOWSProfileManager_GroupWhitelistCollection
                                    usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                        OWSLogError(@"\t profile whitelist group: %@", key);
                                    }];
    }];
}

- (void)regenerateLocalProfile
{
    OWSUserProfile *userProfile = self.localUserProfile;
    [userProfile clearWithProfileKey:[OWSAES256Key generateRandomKey] dbConnection:self.dbConnection completion:nil];
}

- (void)addUserToProfileWhitelist:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    [self addUsersToProfileWhitelist:@[ recipientId ]];
}

- (void)addUsersToProfileWhitelist:(NSArray<NSString *> *)recipientIds
{
    OWSAssertDebug(recipientIds);

    NSMutableSet<NSString *> *newRecipientIds = [NSMutableSet new];
    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (NSString *recipientId in recipientIds) {
            NSNumber *_Nullable oldValue =
                [transaction objectForKey:recipientId inCollection:kOWSProfileManager_UserWhitelistCollection];
            if (oldValue && oldValue.boolValue) {
                continue;
            }
            [transaction setObject:@(YES) forKey:recipientId inCollection:kOWSProfileManager_UserWhitelistCollection];
            [newRecipientIds addObject:recipientId];
        }
    }
        completionBlock:^{
            for (NSString *recipientId in newRecipientIds) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationNameAsync:kNSNotificationName_ProfileWhitelistDidChange
                                       object:nil
                                     userInfo:@{
                                         kNSNotificationKey_ProfileRecipientId : recipientId,
                                     }];
            }
        }];
}

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    __block BOOL result = NO;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSNumber *_Nullable oldValue =
            [transaction objectForKey:recipientId inCollection:kOWSProfileManager_UserWhitelistCollection];
        result = (oldValue && oldValue.boolValue);
    }];
    return result;
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [groupId hexadecimalString];

    __block BOOL didChange = NO;
    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSNumber *_Nullable oldValue =
            [transaction objectForKey:groupIdKey inCollection:kOWSProfileManager_GroupWhitelistCollection];
        if (oldValue && oldValue.boolValue) {
            // Do nothing.
        } else {
            [transaction setObject:@(YES) forKey:groupIdKey inCollection:kOWSProfileManager_GroupWhitelistCollection];
            didChange = YES;
        }
    }
        completionBlock:^{
            if (didChange) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationNameAsync:kNSNotificationName_ProfileWhitelistDidChange
                                       object:nil
                                     userInfo:@{
                                         kNSNotificationKey_ProfileGroupId : groupId,
                                     }];
            }
        }];
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId];

        // When we add a group to the profile whitelist, we might as well
        // also add all current members to the profile whitelist
        // individually as well just in case delivery of the profile key
        // fails.
        for (NSString *recipientId in groupThread.recipientIdentifiers) {
            [self addUserToProfileWhitelist:recipientId];
        }
    } else {
        NSString *recipientId = thread.contactIdentifier;
        [self addUserToProfileWhitelist:recipientId];
    }
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    NSString *groupIdKey = [groupId hexadecimalString];

    __block BOOL result = NO;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSNumber *_Nullable oldValue =
            [transaction objectForKey:groupIdKey inCollection:kOWSProfileManager_GroupWhitelistCollection];
        result = (oldValue && oldValue.boolValue);
    }];
    return result;
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread
{
    OWSAssertDebug(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        return [self isGroupIdInProfileWhitelist:groupId];
    } else {
        NSString *recipientId = thread.contactIdentifier;
        return [self isUserInProfileWhitelist:recipientId];
    }
}

- (void)setContactRecipientIds:(NSArray<NSString *> *)contactRecipientIds
{
    OWSAssertDebug(contactRecipientIds);

    [self addUsersToProfileWhitelist:contactRecipientIds];
}

#pragma mark - Other User's Profiles

- (void)logUserProfiles
{
    [self.dbConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        OWSLogError(@"logUserProfiles: %zd", [transaction numberOfKeysInCollection:OWSUserProfile.collection]);
        [transaction
            enumerateKeysAndObjectsInCollection:OWSUserProfile.collection
                                     usingBlock:^(NSString *_Nonnull key, id _Nonnull object, BOOL *_Nonnull stop) {
                                         OWSAssertDebug([object isKindOfClass:[OWSUserProfile class]]);
                                         OWSUserProfile *userProfile = object;
                                         OWSLogError(@"\t [%@]: has profile key: %d, has avatar URL: %d, has "
                                                     @"avatar file: %d, name: %@",
                                             userProfile.recipientId,
                                             userProfile.profileKey != nil,
                                             userProfile.avatarUrlPath != nil,
                                             userProfile.avatarFileName != nil,
                                             userProfile.profileName);
                                     }];
    }];
}

- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSAES256Key *_Nullable profileKey = [OWSAES256Key keyWithData:profileKeyData];
        if (profileKey == nil) {
            OWSFailDebug(@"Failed to make profile key for key data");
            return;
        }

        OWSUserProfile *userProfile =
            [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

        OWSAssertDebug(userProfile);
        if (userProfile.profileKey && [userProfile.profileKey.keyData isEqual:profileKey.keyData]) {
            // Ignore redundant update.
            return;
        }

        [userProfile clearWithProfileKey:profileKey
                            dbConnection:self.dbConnection
                              completion:^{
                                  dispatch_async(dispatch_get_main_queue(), ^(void) {
                                      [ProfileFetcherJob runWithRecipientId:recipientId
                                                             networkManager:self.networkManager
                                                           ignoreThrottling:YES];
                                  });
                              }];
    });
}

- (nullable NSData *)profileKeyDataForRecipientId:(NSString *)recipientId
{
    return [self profileKeyForRecipientId:recipientId].keyData;
}

- (nullable OWSAES256Key *)profileKeyForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];
    OWSAssertDebug(userProfile);

    return userProfile.profileKey;
}

- (nullable NSString *)profileNameForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

    return userProfile.profileName;
}

- (nullable UIImage *)profileAvatarForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileAvatarWithFilename:userProfile.avatarFileName];
    }

    if (userProfile.avatarUrlPath.length > 0) {
        [self downloadAvatarForUserProfile:userProfile];
    }

    return nil;
}

- (nullable NSData *)profileAvatarDataForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileDataWithFilename:userProfile.avatarFileName];
    }

    return nil;
}

- (void)downloadAvatarForUserProfile:(OWSUserProfile *)userProfile
{
    OWSAssertDebug(userProfile);

    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (userProfile.avatarUrlPath.length < 1) {
            OWSFailDebug(@"Malformed avatar URL: %@", userProfile.avatarUrlPath);
            return;
        }
        NSString *_Nullable avatarUrlPathAtStart = userProfile.avatarUrlPath;

        if (userProfile.profileKey.keyData.length < 1 || userProfile.avatarUrlPath.length < 1) {
            return;
        }

        OWSAES256Key *profileKeyAtStart = userProfile.profileKey;

        NSString *fileName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
        NSString *filePath = [OWSUserProfile profileAvatarFilepathWithFilename:fileName];

        @synchronized(self.currentAvatarDownloads)
        {
            if ([self.currentAvatarDownloads containsObject:userProfile.recipientId]) {
                // Download already in flight; ignore.
                return;
            }
            [self.currentAvatarDownloads addObject:userProfile.recipientId];
        }

        OWSLogVerbose(@"downloading profile avatar: %@", userProfile.uniqueId);

        NSString *tempDirectory = OWSTemporaryDirectory();
        NSString *tempFilePath = [tempDirectory stringByAppendingPathComponent:fileName];

        void (^completionHandler)(NSURLResponse *_Nonnull, NSURL *_Nullable, NSError *_Nullable) = ^(
            NSURLResponse *_Nonnull response, NSURL *_Nullable filePathParam, NSError *_Nullable error) {
            // Ensure disk IO and decryption occurs off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *_Nullable encryptedData = (error ? nil : [NSData dataWithContentsOfFile:tempFilePath]);
                NSData *_Nullable decryptedData = [self decryptProfileData:encryptedData profileKey:profileKeyAtStart];
                UIImage *_Nullable image = nil;
                if (decryptedData) {
                    BOOL success = [decryptedData writeToFile:filePath atomically:YES];
                    if (success) {
                        image = [UIImage imageWithContentsOfFile:filePath];
                    }
                }

                @synchronized(self.currentAvatarDownloads)
                {
                    [self.currentAvatarDownloads removeObject:userProfile.recipientId];
                }

                OWSUserProfile *latestUserProfile =
                    [OWSUserProfile getOrBuildUserProfileForRecipientId:userProfile.recipientId
                                                           dbConnection:self.dbConnection];
                if (latestUserProfile.profileKey.keyData.length < 1
                    || ![latestUserProfile.profileKey isEqual:userProfile.profileKey]) {
                    OWSLogWarn(@"Ignoring avatar download for obsolete user profile.");
                } else if (![avatarUrlPathAtStart isEqualToString:latestUserProfile.avatarUrlPath]) {
                    OWSLogInfo(@"avatar url has changed during download");
                    if (latestUserProfile.avatarUrlPath.length > 0) {
                        [self downloadAvatarForUserProfile:latestUserProfile];
                    }
                } else if (error) {
                    OWSLogError(@"avatar download failed: %@", error);
                } else if (!encryptedData) {
                    OWSLogError(@"avatar encrypted data could not be read.");
                } else if (!decryptedData) {
                    OWSLogError(@"avatar data could not be decrypted.");
                } else if (!image) {
                    OWSLogError(@"avatar image could not be loaded: %@", error);
                } else {
                    [self updateProfileAvatarCache:image filename:fileName];

                    [latestUserProfile updateWithAvatarFileName:fileName dbConnection:self.dbConnection completion:nil];
                }

                // If we're updating the profile that corresponds to our local number,
                // update the local profile as well.
                NSString *_Nullable localNumber = [TSAccountManager sharedInstance].localNumber;
                if (localNumber && [localNumber isEqualToString:userProfile.recipientId]) {
                    OWSUserProfile *localUserProfile = self.localUserProfile;
                    OWSAssertDebug(localUserProfile);

                    [localUserProfile updateWithAvatarFileName:fileName dbConnection:self.dbConnection completion:nil];
                    [self updateProfileAvatarCache:image filename:fileName];
                }

                OWSAssertDebug(backgroundTask);
                backgroundTask = nil;
            });
        };

        NSURL *avatarUrlPath =
            [NSURL URLWithString:userProfile.avatarUrlPath relativeToURL:self.avatarHTTPManager.baseURL];
        NSURLRequest *request = [NSURLRequest requestWithURL:avatarUrlPath];
        NSURLSessionDownloadTask *downloadTask = [self.avatarHTTPManager downloadTaskWithRequest:request
            progress:^(NSProgress *_Nonnull downloadProgress) {
                OWSLogVerbose(
                    @"Downloading avatar for %@ %f", userProfile.recipientId, downloadProgress.fractionCompleted);
            }
            destination:^NSURL *_Nonnull(NSURL *_Nonnull targetPath, NSURLResponse *_Nonnull response) {
                return [NSURL fileURLWithPath:tempFilePath];
            }
            completionHandler:completionHandler];
        [downloadTask resume];
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
        OWSUserProfile *userProfile =
            [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

        if (!userProfile.profileKey) {
            return;
        }

        NSString *_Nullable profileName =
            [self decryptProfileNameData:profileNameEncrypted profileKey:userProfile.profileKey];

        [userProfile updateWithProfileName:profileName
                             avatarUrlPath:avatarUrlPath
                              dbConnection:self.dbConnection
                                completion:nil];

        // If we're updating the profile that corresponds to our local number,
        // update the local profile as well.
        NSString *_Nullable localNumber = [TSAccountManager sharedInstance].localNumber;
        if (localNumber && [localNumber isEqualToString:recipientId]) {
            OWSUserProfile *localUserProfile = self.localUserProfile;
            OWSAssertDebug(localUserProfile);

            [localUserProfile updateWithProfileName:profileName
                                      avatarUrlPath:avatarUrlPath
                                       dbConnection:self.dbConnection
                                         completion:nil];
        }

        // Whenever we change avatarUrlPath, OWSUserProfile clears avatarFileName.
        // So if avatarUrlPath is set and avatarFileName is not set, we should to
        // download this avatar. downloadAvatarForUserProfile will de-bounce
        // downloads.
        if (userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length < 1) {
            [self downloadAvatarForUserProfile:userProfile];
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
    return [self encryptProfileData:data profileKey:self.localProfileKey];
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

    return [self encryptProfileData:[paddedNameData copy] profileKey:self.localProfileKey];
}

#pragma mark - Avatar Disk Cache

- (nullable NSData *)loadProfileDataWithFilename:(NSString *)filename
{
    OWSAssertDebug(filename.length > 0);

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
    OWSAssertDebug(filename.length > 0);
    OWSAssertDebug(image);

    @synchronized(self.profileAvatarImageCache)
    {
        if (image) {
            [self.profileAvatarImageCache setObject:image forKey:filename];
        } else {
            [self.profileAvatarImageCache removeObjectForKey:filename];
        }
    }
}

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *shareTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE",
        @"Button to confirm that user wants to share their profile with a user or group.");
    [alertController addAction:[UIAlertAction actionWithTitle:shareTitle
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *_Nonnull action) {
                                                          [self userAddedThreadToProfileWhitelist:thread
                                                                                          success:successHandler];
                                                      }]];
    [alertController addAction:[OWSAlerts cancelAction]];

    [fromViewController presentViewController:alertController animated:YES completion:nil];
}

- (void)userAddedThreadToProfileWhitelist:(TSThread *)thread success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    OWSProfileKeyMessage *message =
        [[OWSProfileKeyMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread];

    BOOL isFeatureEnabled = NO;
    if (!isFeatureEnabled) {
        OWSLogWarn(@"skipping sending profile-key message because the feature is not yet fully available.");
        [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];
        successHandler();
        return;
    }

    [self.messageSender enqueueMessage:message
        success:^{
            OWSLogInfo(@"Successfully sent profile key message to thread: %@", thread);
            [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];

            dispatch_async(dispatch_get_main_queue(), ^{
                successHandler();
            });
        }
        failure:^(NSError *_Nonnull error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OWSLogError(@"Failed to send profile key message to thread: %@", thread);
            });
        }];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // TODO: Sync if necessary.
}

@end

NS_ASSUME_NONNULL_END
