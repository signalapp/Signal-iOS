//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class OWSAES256Key;
@class TSThread;
@class YapDatabaseReadWriteTransaction;
@class OWSUserProfile;

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol <NSObject>

- (OWSAES256Key *)localProfileKey;

- (nullable NSString *)localProfileName;
- (nullable NSString *)profileNameForRecipientId:(NSString *)recipientId;
- (nullable NSString *)profilePictureURL;

- (nullable NSData *)profileKeyDataForRecipientId:(NSString *)recipientId;
- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId;
- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId avatarURL:(nullable NSString *)avatarURL;

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread;

- (void)addUserToProfileWhitelist:(NSString *)recipientId;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;

- (void)fetchLocalUsersProfile;

- (void)fetchProfileForRecipientId:(NSString *)recipientId;

- (void)updateUserProfileWithDisplayName:(nullable NSString*)displayName transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateUserPofileKeyData:(NSData *)profileKeyData avatarURL:(nullable NSString *)avatarURL transaction:(YapDatabaseReadWriteTransaction *)transaction;
- (void)updateProfileForContactWithID:(NSString *)contactID displayName:(NSString *)displayName with:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
