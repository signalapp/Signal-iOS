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
- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
              wasLocallyInitiated:(BOOL)wasLocallyInitiated
                      transaction:(SDSAnyWriteTransaction *)transaction;
- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address;
- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
                   wasLocallyInitiated:(BOOL)wasLocallyInitiated
                           transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
                 wasLocallyInitiated:(BOOL)wasLocallyInitiated
                         transaction:(SDSAnyWriteTransaction *)transaction;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
                      wasLocallyInitiated:(BOOL)wasLocallyInitiated
                              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)fetchAndUpdateLocalUsersProfile;

- (void)updateProfileForAddress:(SignalServiceAddress *)address;

- (void)warmCaches;

@property (nonatomic, readonly) UserProfileReadCache *userProfileReadCache;
@property (nonatomic, readonly) BOOL hasProfileName;

@end

NS_ASSUME_NONNULL_END
