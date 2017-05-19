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

+ (instancetype)untrustedKeyWithOutgoingMessage:(TSOutgoingMessage *)outgoingMessage
                                       inThread:(TSThread *)thread
                                   forRecipient:(NSString *)recipientId
                                   preKeyBundle:(PreKeyBundle *)preKeyBundle;

@property (nonatomic, readonly) NSString *messageId;

@end

NS_ASSUME_NONNULL_END
