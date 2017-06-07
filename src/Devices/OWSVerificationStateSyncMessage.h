//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"
#import "OWSRecipientIdentity.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSVerificationStateSyncMessage : OWSOutgoingSyncMessage

// identityKey should be set IFF verificationState == OWSVerificationStateVerified;
- (void)addVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData * _Nullable)identityKey
                 recipientId:(NSString *)recipientId;

// Returns the list of recipient ids referenced in this message.
- (NSArray<NSString *> *)recipientIds;

@end

NS_ASSUME_NONNULL_END
