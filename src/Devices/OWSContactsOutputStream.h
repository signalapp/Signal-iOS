//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSChunkedOutputStream.h"

NS_ASSUME_NONNULL_BEGIN

@class SignalAccount;
@class OWSRecipientIdentity;

@interface OWSContactsOutputStream : OWSChunkedOutputStream

- (void)writeSignalAccount:(SignalAccount *)signalAccount
         recipientIdentity:(OWSRecipientIdentity *)recipientIdentity;

@end

NS_ASSUME_NONNULL_END
