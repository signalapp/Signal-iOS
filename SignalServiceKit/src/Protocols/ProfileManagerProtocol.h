//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

@class OWSAES256Key;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignalServiceAddress;
@class TSThread;
@class UserProfileReadCache;

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol <NSObject>

- (OWSAES256Key *)localProfileKey;

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction;
- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)address
              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
                 forAddress:(SignalServiceAddress *)address
                transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

- (void)addThreadToProfileWhitelist:(TSThread *)thread;

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address;
- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;

- (void)fetchAndUpdateLocalUsersProfile;

- (void)updateProfileForAddress:(SignalServiceAddress *)address;

- (BOOL)recipientAddressIsUuidCapable:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (void)warmCaches;

@property (nonatomic, readonly) UserProfileReadCache *userProfileReadCache;

@end

NS_ASSUME_NONNULL_END
