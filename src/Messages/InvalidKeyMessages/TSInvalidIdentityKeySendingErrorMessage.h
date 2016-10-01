//
//  TSInvalidIdentityKeySendingErrorMessage.h
//  Signal
//
//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class PreKeyBundle;
@class TSOutgoingMessage;
@class TSThread;

@interface TSInvalidIdentityKeySendingErrorMessage : TSInvalidIdentityKeyErrorMessage

#define TSInvalidPreKeyBundleKey @"TSInvalidPreKeyBundleKey"
#define TSInvalidRecipientKey @"TSInvalidRecipientKey"

+ (instancetype)untrustedKeyWithOutgoingMessage:(TSOutgoingMessage *)outgoingMessage
                                       inThread:(TSThread *)thread
                                   forRecipient:(NSString *)recipientId
                                   preKeyBundle:(PreKeyBundle *)preKeyBundle
                                withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@property (nonatomic, readonly) NSString *recipientId;

@end

NS_ASSUME_NONNULL_END
