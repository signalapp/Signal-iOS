//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class OWSAES256Key;
@class TSThread;
@class YapDatabaseReadWriteTransaction;
@class OWSUserProfile;

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol <NSObject>

#pragma mark - Local Profile

- (void)ensureLocalProfileCached;
- (void)updateServiceWithProfileName:(nullable NSString *)localProfileName avatarURL:(nullable NSString *)avatarURL;

#pragma mark - Other User's Profiles

- (nullable NSData *)profileKeyDataForRecipientId:(NSString *)recipientId;
- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId;
- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId avatarURL:(nullable NSString *)avatarURL;
- (void)updateProfileForContactWithID:(NSString *)contactID displayName:(NSString *)displayName with:(YapDatabaseReadWriteTransaction *)transaction;
- (void)ensureProfileCachedForContactWithID:(NSString *)contactID with:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Other

- (void)downloadAvatarForUserProfile:(OWSUserProfile *)userProfile;

@end

NS_ASSUME_NONNULL_END
