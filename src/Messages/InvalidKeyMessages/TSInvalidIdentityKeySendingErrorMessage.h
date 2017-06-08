//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class PreKeyBundle;
@class TSOutgoingMessage;
@class TSThread;

extern NSString *TSInvalidPreKeyBundleKey;
extern NSString *TSInvalidRecipientKey;

@interface TSInvalidIdentityKeySendingErrorMessage : TSInvalidIdentityKeyErrorMessage

@property (nonatomic, readonly) NSString *messageId;

@end

NS_ASSUME_NONNULL_END
