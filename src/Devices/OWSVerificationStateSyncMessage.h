//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"
#import "OWSRecipientIdentity.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSVerificationStateSyncMessage : OWSOutgoingSyncMessage

- (instancetype)initWithVerificationState:(OWSVerificationState)verificationState
                              identityKey:(NSData *)identityKey
                              recipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
