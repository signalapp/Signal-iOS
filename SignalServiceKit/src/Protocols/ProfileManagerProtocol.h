//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSThread;

@protocol ProfileManagerProtocol <NSObject>

- (NSData *)localProfileKey;

- (void)setProfileKey:(NSData *)profileKey forRecipientId:(NSString *)recipientId;

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread;

@end
