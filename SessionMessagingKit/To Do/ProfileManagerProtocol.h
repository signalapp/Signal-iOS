//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class OWSAES256Key;
@class TSThread;
@class YapDatabaseReadWriteTransaction;
@class SNContact;

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol <NSObject>

#pragma mark - Local Profile

- (void)updateServiceWithProfileName:(nullable NSString *)localProfileName avatarURL:(nullable NSString *)avatarURL;

#pragma mark - Other User's Profiles

- (nullable NSData *)profileKeyDataForRecipientId:(NSString *)recipientId;
- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId;
- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId avatarURL:(nullable NSString *)avatarURL;

#pragma mark - Other

- (void)downloadAvatarForUserProfile:(SNContact *)userProfile;

@end

NS_ASSUME_NONNULL_END
