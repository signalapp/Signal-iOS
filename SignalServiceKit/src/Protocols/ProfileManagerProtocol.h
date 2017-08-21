//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSThread;
@class OWSAES256Key;

@protocol ProfileManagerProtocol <NSObject>

- (OWSAES256Key *)localProfileKey;

- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId;

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread;

- (void)addUserToProfileWhitelist:(NSString *)recipientId;

@end
