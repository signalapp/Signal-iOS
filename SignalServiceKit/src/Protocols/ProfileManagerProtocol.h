//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@class OWSAES256Key;
@class SignalServiceAddress;
@class TSThread;

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol <NSObject>

- (OWSAES256Key *)localProfileKey;

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address;
- (void)setProfileKeyData:(NSData *)profileKeyData forAddress:(SignalServiceAddress *)address;

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread;

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;

- (void)fetchLocalUsersProfile;

- (void)fetchProfileForAddress:(SignalServiceAddress *)address;

@end

NS_ASSUME_NONNULL_END
