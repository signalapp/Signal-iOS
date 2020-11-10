//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class PreKeyBundle;
@class TSOutgoingMessage;
@class TSThread;

extern NSString *TSInvalidPreKeyBundleKey;
extern NSString *TSInvalidRecipientKey;

// DEPRECATED - we no longer create new instances of this class (as of  mid-2017); However, existing instances may
// exist, so we should keep this class around to honor their old behavior.
__attribute__((deprecated)) @interface TSInvalidIdentityKeySendingErrorMessage : TSInvalidIdentityKeyErrorMessage

@property (nonatomic, readonly) NSString *messageId;

@end

NS_ASSUME_NONNULL_END
