//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSThread;
@class OWSAES128Key;

@protocol ProfileManagerProtocol <NSObject>

- (OWSAES128Key *)localProfileKey;

- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId;

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread;

- (void)addUserToProfileWhitelist:(NSString *)recipientId;

@end
